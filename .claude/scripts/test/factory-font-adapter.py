#!/usr/bin/env python3
"""Local synthetic adapter controls; never model/native acceptance."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import os
import subprocess
import tempfile
import sys
import unittest
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
producer = load('producer', ROOT / '.claude/scripts/factory-producer.py')
class Adapter(unittest.TestCase):
    def setUp(self):
        self.repo='fixture/project';self.spec=b'**AC-1** registered fixture'
        self.path='public/fonts/inter/inter-baseline-latin.woff2'
        self.raw=b'wOF2'+b'\0'*4+struct.pack('>I',48)+b'\0'*36
        face={'family':'Inter','style':'normal','weight':'100 900','display':'swap','unicode_range':'U+0-FF'}
        self.registration={'kind':'registered-woff2-v1','repository':self.repo,'spec_sha256':hashlib.sha256(self.spec).hexdigest(),
            'assets':{self.path:{'sha256':hashlib.sha256(self.raw).hexdigest(),'length':48,'face':face}},
            'license':{'path':'public/fonts/inter/OFL.txt','sha256':hashlib.sha256(b'license\n').hexdigest()},
            'provenance':{'path':'public/fonts/inter/SOURCE.json','sha256':hashlib.sha256(b'{"source":"fixture"}\n').hexdigest()}}
        self.approved={'sha256':hashlib.sha256(self.spec).hexdigest(),'ac_ids':['AC-1'],'review_adapter':self.registration}
        self.binding={'repository':self.repo,'head_sha':'a'*40,'base_sha':'b'*40,'spec_sha256':self.approved['sha256'],'policy_sha256':'c'*64}
        self.blobs={self.path:self.raw,'public/fonts/inter/OFL.txt':b'SIL OPEN FONT LICENSE Version 1.1\n',
                    'public/fonts/inter/SOURCE.json':json.dumps({'assets':[{'path':self.path,'sha256':hashlib.sha256(self.raw).hexdigest(),'bytes':48}]}).encode()}
        for key in ('license','provenance'):
            pin=self.registration[key];pin['sha256']=hashlib.sha256(self.blobs[pin['path']]).hexdigest()
        self.api=type('API',(),{'source':lambda _,path,sha:self.blobs[path]})()
    def test_registered_font_represented_without_decoding_or_execution(self):
        prompt=producer.review_prompt(self.api,self.repo,self.approved,[{'filename':self.path,'status':'added'}],self.spec,self.binding)
        self.assertIn('registered-woff2-v1',prompt)
        self.assertIn(hashlib.sha256(self.raw).hexdigest(),prompt)
        self.assertIn('wOF2',prompt)
    def adapter(self):
        return producer.font_adapter
    def rejects_prompt(self):
        with self.assertRaises((ValueError,KeyError,TypeError,UnicodeError)):
            producer.review_prompt(self.api,self.repo,self.approved,[{'filename':self.path,'status':'added'}],self.spec,self.binding)
    def test_tamper_wrong_length_magic_metadata_license_and_provenance_reject(self):
        original=copy.deepcopy(self.blobs)
        for path in original:
            with self.subTest(path=path):
                self.blobs=copy.deepcopy(original);self.blobs[path]+=b'tampered';self.rejects_prompt()
        self.blobs=original
        for field,value in [('length',49),('sha256','0'*64),('face',{'family':'Other'})]:
            old=copy.deepcopy(self.registration['assets'][self.path]);self.registration['assets'][self.path][field]=value
            self.rejects_prompt();self.registration['assets'][self.path]=old
        raw=b'bad!'+self.raw[4:]
        pin=self.registration['assets'][self.path];pin['sha256']=hashlib.sha256(raw).hexdigest()
        with self.assertRaisesRegex(ValueError,'invalid WOFF2'):
            self.adapter().blob(self.approved,self.repo,self.path,raw,'a'*40)
    def test_unknown_renamed_path_and_candidate_supplied_approval_reject(self):
        for path in ('public/fonts/inter/other.woff2','../inter-baseline-latin.woff2','src/font.woff2'):
            with self.assertRaisesRegex(ValueError,'binary candidate'):
                self.adapter().content(self.approved,self.repo,path,self.raw,'a'*40)
        for field,value in [('repository','foreign/repo'),('spec_sha256','f'*64),('kind','anything')]:
            old=self.registration[field];self.registration[field]=value
            self.rejects_prompt();self.registration[field]=old
        del self.approved['review_adapter'];self.rejects_prompt()
    def test_text_only_legacy_complete_before_after_and_capacity(self):
        del self.approved['review_adapter'];self.path='src/app.py';self.blobs[self.path]=b'complete textual source\n'
        prompt=producer.review_prompt(self.api,self.repo,self.approved,[{'filename':self.path,'status':'modified'}],self.spec,self.binding)
        self.assertEqual(prompt.count('complete textual source'),2)
        self.blobs[self.path]=b'x'*250001
        with self.assertRaisesRegex(ValueError,'complete review input limit'):
            producer.review_prompt(self.api,self.repo,self.approved,[{'filename':self.path,'status':'modified'}],self.spec,self.binding)
    def test_registered_paths_cannot_bypass_by_becoming_utf8(self):
        with self.assertRaisesRegex(ValueError,'font bytes differ'):
            self.adapter().content(self.approved,self.repo,self.path,b'plain text','a'*40)
    def test_manifest_binding_changes_with_source_and_policy(self):
        a=self.adapter().manifest(self.approved,self.repo,self.api.source,'a'*40)
        b=self.adapter().manifest(self.approved,self.repo,self.api.source,'b'*40)
        self.assertNotEqual(a['asset_manifest_sha256'],b['asset_manifest_sha256'])
        self.assertEqual(a['registration_sha256'],b['registration_sha256'])
    def test_verifier_rechecks_checked_out_bytes_before_acceptance(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'artifacts').mkdir()
            for path,raw in self.blobs.items():
                target=root/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
            self.approved.update(acceptance_commands={'AC-1':['node','contract.mjs']},verification_image='image@sha256:'+'d'*64)
            manifest=self.adapter().manifest(self.approved,self.repo,self.api.source,self.binding['head_sha'])
            self.binding['review_adapter']=self.adapter().binding(manifest)
            calls=[]
            def runner(argv,**kwargs):
                calls.append(argv);kwargs['stdout'].write(b'fixture only');return subprocess.CompletedProcess(argv,0)
            producer.verify(self.approved,root,root,self.binding,'fixture',runner)
            self.assertEqual(len(calls),1)
            (root/self.path).write_bytes(self.raw+b'tampered');calls.clear()
            with self.assertRaisesRegex(ValueError,'font bytes differ'):
                producer.verify(self.approved,root,root,self.binding,'fixture',runner)
            self.assertEqual(calls,[])
    def ordinary_fixture(self, mutate=None):
        folder=tempfile.TemporaryDirectory(prefix='font-base-policy-');self.addCleanup(folder.cleanup)
        root=Path(folder.name);repo=root/'repo';repo.mkdir();temp=root/'out';temp.mkdir()
        def git(*args):
            return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.DEVNULL,text=True).strip()
        git('init');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
        def put(path,raw):
            file=repo/path;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(raw)
        for path,raw in self.blobs.items():
            if path!=self.path:put(path,raw)
        approved={**self.approved,'path':'specs/001.md'}
        policy={'repository':self.repo,'base_branch':'main','specs':{'001':approved}}
        put('specs/001.md',self.spec);put('factory/policy.json',json.dumps(policy).encode())
        git('add','.');git('commit','-qm','protected fixture');base=git('rev-parse','HEAD')
        put(self.path,self.raw)
        # Candidate registration is malicious and must never select its own adapter.
        put('factory/policy.json',b'{"repository":"candidate-controlled","specs":{}}')
        if mutate:mutate(repo,put)
        git('add','.');git('commit','-qm','candidate fixture');head=git('rev-parse','HEAD')
        event={'repository':{'full_name':self.repo},'pull_request':{'number':1,
          'head':{'sha':head,'ref':'factory/spec-001/font','repo':{'full_name':self.repo}},
          'base':{'sha':base,'ref':'main','repo':{'full_name':self.repo}}}}
        eventpath=root/'event.json'
        def run(event):
            eventpath.write_text(json.dumps(event))
            return subprocess.run([sys.executable,'-I',str(ROOT/'.claude/scripts/prepare-claude-review.py')],cwd=repo,
                env={**os.environ,'GITHUB_EVENT_PATH':str(eventpath),'RUNNER_TEMP':str(temp)},capture_output=True,text=True)
        return repo,temp,event,run
    def test_ordinary_uses_immutable_base_not_candidate_policy(self):
        repo,temp,event,run=self.ordinary_fixture()
        result=run(event);self.assertEqual(result.returncode,0,result.stderr)
        text=(temp/'claude-review-input.txt').read_text()
        self.assertIn('registered-woff2-v1',text)
        binding=json.loads(text.splitlines()[0].removeprefix('BINDING '))
        self.assertIn('asset_manifest_sha256',binding['review_adapter'])
        self.assertIn('candidate-controlled',text) # complete textual candidate policy is still shown
    def test_ordinary_foreign_repo_ref_and_head_approval_cannot_authorize(self):
        repo,temp,event,run=self.ordinary_fixture()
        for side,key,value in [('head','ref','codex/unapproved'),('base','ref','other')]:
            changed=copy.deepcopy(event);changed['pull_request'][side][key]=value
            self.assertNotEqual(run(changed).returncode,0)
        changed=copy.deepcopy(event);changed['pull_request']['head']['repo']['full_name']='foreign/repo'
        self.assertNotEqual(run(changed).returncode,0)
        # HEAD can register its tampered bytes; protected BASE cannot.
        def tamper(repo,put):
            put(self.path,self.raw+b'x')
            policy={'repository':self.repo,'base_branch':'main','specs':{'001':self.approved}}
            policy['specs']['001']['review_adapter']['assets'][self.path]['sha256']=hashlib.sha256(self.raw+b'x').hexdigest()
            put('factory/policy.json',json.dumps(policy).encode())
        repo,temp,event,run=self.ordinary_fixture(tamper)
        self.assertNotEqual(run(event).returncode,0)
    def test_legacy_text_capacity_context_is_byte_identical(self):
        with tempfile.TemporaryDirectory(prefix='font-legacy-capacity-') as folder:
            root=Path(folder);repo=root/'repo';repo.mkdir();out=root/'out';out.mkdir();old=root/'old';old.mkdir()
            def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.DEVNULL,text=True).strip()
            git('init');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
            (repo/'source.txt').write_text('a'*220000+'\n');git('add','.');git('commit','-qm','before');base=git('rev-parse','HEAD')
            (repo/'source.txt').write_text('b'*220000+'\n');git('commit','-am','after','-q');head=git('rev-parse','HEAD')
            event=root/'event.json';event.write_text(json.dumps({'repository':{'full_name':self.repo},'pull_request':{'number':1,'head':{'sha':head},'base':{'sha':base}}}))
            env={**os.environ,'GITHUB_EVENT_PATH':str(event),'RUNNER_TEMP':str(out)}
            previous=(ROOT/'.claude/scripts/test/fixtures/font-adapter-legacy-prepare.py').read_bytes()
            self.assertEqual(hashlib.sha256(previous).hexdigest(), '2ec50b41b95457b2ecdf142c6b91c443aa40b35d3078b05121ebf8193239caf0')
            (old/'prepare-claude-review.py').write_bytes(previous)
            (old/'factory-bounded-process.py').write_bytes((ROOT/'.claude/scripts/factory-bounded-process.py').read_bytes())
            before=subprocess.run([sys.executable,'-I',str(old/'prepare-claude-review.py')],cwd=repo,env=env,capture_output=True,text=True)
            self.assertEqual(before.returncode,0,before.stderr)
            expected=(out/'claude-review-input.txt').read_bytes()
            after=subprocess.run([sys.executable,'-I',str(ROOT/'.claude/scripts/prepare-claude-review.py')],cwd=repo,env=env,capture_output=True,text=True)
            self.assertEqual(after.returncode,0,after.stderr)
            self.assertEqual((out/'claude-review-input.txt').read_bytes(),expected)
            self.assertGreater(len(expected),850000)
    def test_binding_validator_requires_exact_optional_adapter(self):
        contract=producer.coordinator.contract
        # Exercise optional binding before ordinary evidence fields: invalid shape is rejected first.
        for binding in ({'kind':'registered-woff2-v1'}, {'kind':'other','registration_sha256':'a'*64,'asset_manifest_sha256':'b'*64}):
            with self.assertRaisesRegex(ValueError,'review adapter'):
                contract.validate({'review_adapter':binding},{})
if __name__=='__main__':unittest.main(verbosity=2)

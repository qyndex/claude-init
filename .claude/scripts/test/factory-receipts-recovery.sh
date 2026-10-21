#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "${RECEIPT_TEST_ROOT:-$ROOT}" <<'PY'
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import zipfile

scripts=Path(sys.argv[1])/'.claude/scripts'
assert (scripts/'factory-receipts.py').is_file(), 'authenticated receipt ingestion not implemented'
spec=importlib.util.spec_from_file_location('receipts',scripts/'factory-receipts.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)

def rejects(fn):
    try: fn()
    except (ValueError,r.ledger.runtime.Blocked): return
    raise AssertionError('untrusted receipt/recovery accepted')

def wait_for(fn):
    end=time.monotonic()+10
    while time.monotonic()<end:
        if fn(): return
        time.sleep(.05)
    raise AssertionError('recovery condition not reached')

class API:
    def __init__(self,policy,receipt):
        self.repo=policy['repository']
        self.run={'id':20,'run_attempt':1,'workflow_id':10,'path':'.github/workflows/factory-merge.yml','repository':{'id':101,'full_name':self.repo},'head_branch':'main','head_sha':'a'*40,'event':'workflow_dispatch','status':'completed','conclusion':'success'}
        self.pr={'number':7,'merged':True,'merge_commit_sha':'b'*40,'head':{'sha':'c'*40,'repo':{'full_name':self.repo}},'base':{'ref':'main','repo':{'full_name':self.repo}}}
        self.receipt=receipt; self.sources={p:b'trusted' for p in r.RUNTIME_PATHS}
        self.sources['factory/policy.json']=json.dumps(policy).encode();self.sources['specs/active/001.md']=b'approved spec'
        self.expired=False;self.tamper=False;self.extra=False
    def get(self,path):
        if '/pulls/' in path:return self.pr
        return self.run
    def source(self,path,sha):
        assert sha==self.run['head_sha'];return self.sources[path]
    def request(self,path,**kwargs):
        buf=io.BytesIO()
        with zipfile.ZipFile(buf,'w') as z:
            z.writestr(zipfile.ZipInfo('receipt.json', date_time=(2026,1,1,0,0,0)),json.dumps(self.receipt))
            if self.extra:z.writestr('../forged','bad')
        blob=buf.getvalue()
        if path.endswith('/artifacts'):
            return [{'artifacts':[{'id':30,'name':'factory-receipt-20-1','expired':self.expired,'size_in_bytes':len(blob),'workflow_run': (None if hasattr(self,'origin_override') and self.origin_override is None else dict({'id':20,'repository_id':101,'head_repository_id':101,'head_sha':self.run['head_sha']}, **getattr(self,'origin_override',{}))), 'digest':'sha256:'+hashlib.sha256(blob).hexdigest()}]}]
        return blob+b'altered' if self.tamper else blob

with tempfile.TemporaryDirectory() as tmp:
    db=Path(tmp)/'runtime.sqlite';store=r.ledger.runtime.Store(db)
    revision=hashlib.sha256(b'approved spec').hexdigest()
    policy={'enabled':True,'merge_enabled':True,'repository':'org/repo','base_branch':'main','specs':{'001':{'path':'specs/active/001.md','sha256':revision,'task_ids':['T-1']}},'receipts':{'workflow_id':10,'trusted_revisions':{'a'*40:{p:hashlib.sha256(b'trusted').hexdigest() for p in r.RUNTIME_PATHS}}}}
    receipt={'schema_version':1,'repository':'org/repo','pull_request':7,'head_sha':'c'*40,'base_sha':'d'*40,'spec':'001','spec_sha256':revision,'policy_sha256':r.coordinator.policy_hash(policy),'verifier_run':21,'reviewer_run':22,'eligible':True,'merged':True,'merge_sha':'b'*40,'task_ids':['T-1']}
    # New adapter binding is authenticated against the signed source policy; legacy receipts remain unchanged.
    adapter_policy=copy.deepcopy(policy)
    registration={'kind':'registered-woff2-v1','assets':{'public/fonts/inter/inter-baseline-latin.woff2':{'sha256':'1'*64,'length':48}}}
    adapter_policy['specs']['001']['review_adapter']=registration
    canonical=lambda value:json.dumps(value,sort_keys=True,separators=(',',':')).encode()
    bound=copy.deepcopy(receipt);bound['policy_sha256']=r.coordinator.policy_hash(adapter_policy)
    bound['review_adapter']={'kind':'registered-woff2-v1','registration_sha256':hashlib.sha256(canonical(registration)).hexdigest(),'asset_manifest_sha256':hashlib.sha256(canonical({'head_sha':bound['head_sha'],'assets':registration['assets']})).hexdigest()}
    r.authenticate(API(adapter_policy,bound),adapter_policy,20)
    for field in ('registration_sha256','asset_manifest_sha256'):
        bad=copy.deepcopy(bound);bad['review_adapter'][field]='f'*64
        rejects(lambda:r.authenticate(API(adapter_policy,bad),adapter_policy,20))
    bad=copy.deepcopy(bound);bad.pop('review_adapter');rejects(lambda:r.authenticate(API(adapter_policy,bad),adapter_policy,20))
    store.enqueue('T-1',revision,[])
    api=API(policy,receipt)
    for field,value in [('workflow_id',11),('event','pull_request'),('head_branch','feature'),('conclusion','failure')]:
        bad=copy.deepcopy(api);bad.run[field]=value;rejects(lambda:r.ingest(bad,policy,db,20))
    bad=copy.deepcopy(api);bad.run['repository']['full_name']='foreign/repo';rejects(lambda:r.ingest(bad,policy,db,20))
    for field in ('expired','tamper','extra'):
        bad=copy.deepcopy(api);setattr(bad,field,True);rejects(lambda:r.ingest(bad,policy,db,20))
    bad=copy.deepcopy(api);bad.pr['merged']=False;rejects(lambda:r.ingest(bad,policy,db,20))
    bad=copy.deepcopy(api);bad.pr['merge_commit_sha']='e'*40;rejects(lambda:r.ingest(bad,policy,db,20))
    bad=copy.deepcopy(api);bad.sources[r.RUNTIME_PATHS[0]]=b'changed';rejects(lambda:r.ingest(bad,policy,db,20))
    helper='.claude/scripts/factory-policy-observation.py'
    bad=copy.deepcopy(api);bad.sources[helper]=b'forged-helper';rejects(lambda:r.ingest(bad,policy,db,20))
    missing=copy.deepcopy(policy);missing['receipts']['trusted_revisions']['a'*40].pop(helper)
    rejects(lambda:r.ingest(api,missing,db,20))
    bad=copy.deepcopy(api);bad.pr['head']['sha']='e'*40;rejects(lambda:r.ingest(bad,policy,db,20))
    bad=copy.deepcopy(policy);bad['receipts']['trusted_revisions']={};rejects(lambda:r.ingest(api,bad,db,20))
    bad=copy.deepcopy(policy);bad['receipts']['workflow_id']=None;rejects(lambda:r.ingest(api,bad,db,20))
    for field,value in [('merged',False),('task_ids',['T-2']),('policy_sha256','0'*64),('spec_sha256','0'*64)]:
        bad=copy.deepcopy(api);bad.receipt[field]=value;rejects(lambda:r.ingest(bad,policy,db,20))
    bad=copy.deepcopy(api);bad.sources['specs/active/001.md']=b'revised';rejects(lambda:r.ingest(bad,policy,db,20))
    assert store.get('T-1')['state']=='queued'
    r.ingest(api,policy,db,20);r.ingest(api,policy,db,20)
    assert store.get('T-1')['state']=='merged'
    bad=copy.deepcopy(api);bad.receipt['merge_sha']='e'*40;bad.pr['merge_commit_sha']='e'*40;rejects(lambda:r.ingest(bad,policy,db,20))
    # Actual abrupt supervisor death, including a worker that closes inherited lock FDs.
    store.enqueue('T-2','f'*64,[])
    pid=Path(tmp)/'worker-pid'
    child_pid=Path(tmp)/'child-pid'
    child_code='import os,signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);os.closerange(3,256);time.sleep(30)'
    worker_code='import os,sys,time,signal,subprocess;from pathlib import Path;signal.signal(signal.SIGTERM,signal.SIG_IGN);child=subprocess.Popen([sys.executable,"-c",sys.argv[3]]);Path(sys.argv[2]).write_text(str(child.pid));Path(sys.argv[1]).write_text(str(os.getpid()));os.closerange(3,256);time.sleep(30)'
    worker=[sys.executable,'-c',worker_code,str(pid),str(child_pid),child_code]
    prefix=[sys.executable,str(scripts/'factory-supervisor.py'),'--db',str(db),'--task','T-2','--cwd',tmp,'--attempts',str(Path(tmp)/'attempts'),'--lease','3','--']
    supervisor=subprocess.Popen([*prefix,*worker],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    wait_for(pid.exists);old=store.get('T-2')['fence']
    duplicate=subprocess.run([*prefix,sys.executable,'-c','print("duplicate")'],capture_output=True,text=True,timeout=5)
    assert duplicate.returncode!=0
    supervisor.kill();supervisor.wait()
    wait_for(lambda:store.get('T-2')['state']=='queued')
    for marker in (pid,child_pid):
        status=subprocess.run(['ps','-p',marker.read_text(),'-o','stat='],capture_output=True,text=True)
        assert not status.stdout.strip() or status.stdout.strip().startswith('Z')
    outcome=json.loads(next((Path(tmp)/'attempts').glob('T-2-*/guardian.json')).read_text())
    assert outcome['reason']=='supervisor-lost' and outcome['engineering_verified'] is False
    retry=subprocess.run([*prefix,sys.executable,'-c','print("retry")'],capture_output=True,text=True,timeout=10)
    assert retry.returncode==0,retry.stderr
    assert store.get('T-2')['fence']>old and store.get('T-2')['state']=='verifying'
    store.enqueue('T-3','f'*64,[]);token=store.claim('T-3','old',30)
    store.transition('T-3','old',token,'implementing',action=('external',{'operation':'create-pr'}))
    store.dispatch('external','sender',30)
    store.recover_worker('T-3','old',token,requeue=True)
    assert store.actions()[0]['status']=='uncertain'
    new=store.claim('T-3','new',30)
    assert store.recover_worker('T-3','old',token,requeue=True) is False
    store.cancel('T-3');assert store.recover_worker('T-3','new',new,requeue=True) is False
    store.enqueue('T-4','f'*64,[]);token=store.claim('T-4','owner',30)
    store.recover_worker('T-4','owner',token,requeue=False)
    assert store.get('T-4')['state']=='blocked'
print('AC-1: authenticated artifact metadata, policy pins, source and archive integrity negatives reject forged delivery receipts')
print('AC-2: actual receipt ingestion binds merged PR, current approved task revision and immutable authenticated provenance')
print('AC-3: actual liveness guardian cleanup fences interrupted attempts and preserves uncertain external effects')
print('AC-4: real SIGKILL, cleanup, bounded fenced retry and stale guardian drills grant no engineering or merge verdict')
PY

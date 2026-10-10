#!/usr/bin/env bash
set -euo pipefail
ROOT="${RECEIPT_PROJECTION_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PYTEST'
import copy,hashlib,importlib.util,io,json,sqlite3,sys,tempfile,zipfile
from pathlib import Path
scripts=Path(sys.argv[1])/'.claude/scripts'
spec=importlib.util.spec_from_file_location('receipts',scripts/'factory-receipts.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
assert hasattr(r,'project'), 'fresh hosted reporting has no authenticated receipt projection'
def rejects(fn):
    try: fn()
    except (ValueError,KeyError):return
    raise AssertionError('untrusted reporting proof accepted')
class API:
    def __init__(self,policy,receipt):
        self.repo=policy['repository']
        self.run={'id':20,'run_attempt':1,'workflow_id':10,'repository':{'full_name':self.repo},'head_branch':'main','head_sha':'a'*40,'event':'workflow_dispatch','status':'completed','conclusion':'success'}
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
            return [{'artifacts':[{'id':30,'name':'factory-receipt-20-1','expired':self.expired,'size_in_bytes':len(blob),'digest':'sha256:'+hashlib.sha256(blob).hexdigest()}]}]
        return blob+b'altered' if self.tamper else blob


class ReportingAPI(API):
    def __init__(self,policy,receipt):
        super().__init__(policy,receipt);self.pages=[{'workflow_runs':[self.run]}];self.calls=[]
    def request(self,path,**kwargs):
        self.calls.append((path,kwargs));assert kwargs.get('method','GET')=='GET'
        if '/actions/workflows/' in path:
            assert kwargs.get('paginate') is True;return self.pages
        if '/pulls?' in path:return [[dict(self.pr,merged_at='2026-10-02T00:00:00Z',title='Delivered feature',html_url='https://github.com/org/repo/pull/7')]]
        return super().request(path,**kwargs)
revision=hashlib.sha256(b'approved spec').hexdigest()
policy={'enabled':True,'merge_enabled':True,'repository':'org/repo','base_branch':'main','specs':{'001':{'path':'specs/active/001.md','sha256':revision,'task_ids':['T-1']}},'receipts':{'workflow_id':10,'trusted_revisions':{'a'*40:{p:hashlib.sha256(b'trusted').hexdigest() for p in r.RUNTIME_PATHS}}}}
receipt={'schema_version':1,'repository':'org/repo','pull_request':7,'head_sha':'c'*40,'base_sha':'d'*40,'spec':'001','spec_sha256':revision,'policy_sha256':r.coordinator.policy_hash(policy),'verifier_run':21,'reviewer_run':22,'eligible':True,'merged':True,'merge_sha':'b'*40,'task_ids':['T-1']}
with tempfile.TemporaryDirectory() as tmp:
    api=ReportingAPI(policy,receipt);db=Path(tmp)/'fresh.sqlite'
    assert r.project(api,policy,db)==1
    with sqlite3.connect(db) as conn:
        assert {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}=={'delivery_receipts','delivery_provenance'}
        before=conn.execute('SELECT * FROM delivery_provenance').fetchall()
    # AC-1: actual digest consumes authenticated task/spec/run mapping on fresh disks.
    dspec=importlib.util.spec_from_file_location('digest',scripts/'factory-digest.py');d=importlib.util.module_from_spec(dspec);dspec.loader.exec_module(d)
    for name in ('fresh.sqlite','another.sqlite'):
        path=Path(tmp)/name;r.project(api,policy,path)
        digest=d.Digest(path,'org/repo','C1','2026-10-01T00:00:00Z')
        entry=json.loads(digest.prepare(api,'2026-10-03T00:00:00Z')['payload'])['merges'][0]
        assert entry['evidence_status']=='authenticated' and entry['delivery_evidence'][0]['task']=='T-1'
        assert entry['delivery_evidence'][0]['producer_run']==20
    # Historical reporting preserves the approved merge-time spec after a new revision.
    revised=copy.deepcopy(policy);revised['specs']['001']['sha256']='f'*64
    assert r.project(api,revised,db)==1
    rejects(lambda:r.ingest(api,revised,Path(tmp)/'runtime.sqlite',20))
    print('AC-1: fresh disks, exact digest bindings and historical revisions passed')
    # AC-2: every delivery proof reuses source/run/artifact/actual merge authentication.
    for field,value in [('workflow_id',11),('event','pull_request'),('head_branch','feature'),('conclusion','failure')]:
        bad=copy.deepcopy(api);bad.run[field]=value;rejects(lambda:r.project(bad,policy,db))
    for field in ('expired','tamper','extra'):
        bad=copy.deepcopy(api);setattr(bad,field,True);rejects(lambda:r.project(bad,policy,db))
    for target,field,value in [('receipt','task_ids',['T-2']),('receipt','policy_sha256','0'*64),('receipt','reviewer_run',21),('pr','merged',False),('pr','merge_commit_sha','e'*40),('pr','head',{'sha':'e'*40,'repo':{'full_name':'org/repo'}})]:
        bad=copy.deepcopy(api);getattr(bad,target)[field]=value;rejects(lambda:r.project(bad,policy,db))
    bad=copy.deepcopy(api);bad.sources[r.RUNTIME_PATHS[0]]=b'changed';rejects(lambda:r.project(bad,policy,db))
    with sqlite3.connect(db) as conn:assert conn.execute('SELECT * FROM delivery_provenance').fetchall()==before
    print('AC-2: authentication negatives and atomic failure preservation passed')
    # AC-3: paginate all runs, reject ambiguity/bounds; skipped sources never earn proof.
    bad=copy.deepcopy(api);bad.pages=[{'workflow_runs':[api.run]},{'workflow_runs':[api.run]}];rejects(lambda:r.project(bad,policy,db))
    bad=copy.deepcopy(api);bad.pages=[{'workflow_runs':[dict(api.run,id=i+1) for i in range(1001)]}];rejects(lambda:r.project(bad,policy,db))
    candidate=copy.deepcopy(api);candidate.run['head_sha']='z'*40
    assert r.project(candidate,policy,db)==0
    declined=copy.deepcopy(api);declined.receipt['merged']=False
    assert r.project(declined,policy,db)==0
    empty=copy.deepcopy(policy);empty['receipts']={'workflow_id':None,'trusted_revisions':{}}
    before_calls=len(api.calls);assert r.project(api,empty,db)==0 and len(api.calls)==before_calls
    empty['receipts']['trusted_revisions']={'a'*40:{}};rejects(lambda:r.project(api,empty,db))
    foreign=copy.deepcopy(policy);foreign['repository']='other/repo';rejects(lambda:r.project(api,foreign,db))
    class DuplicateDeliveryAPI(ReportingAPI):
        def get(self,path):
            if '/actions/runs/' in path:return dict(self.run,id=int(path.rsplit('/',1)[1]))
            return super().get(path)
        def request(self,path,**kwargs):
            result=super().request(path,**kwargs)
            if '/actions/runs/' in path and path.endswith('/artifacts'):
                identity=int(path.split('/actions/runs/')[1].split('/')[0])
                result[0]['artifacts'][0]['name']=f'factory-receipt-{identity}-1'
            return result
    conflict=DuplicateDeliveryAPI(policy,receipt)
    conflict.pages=[{'workflow_runs':[conflict.run,dict(conflict.run,id=23)]}]
    rejects(lambda:r.project(conflict,policy,db))
    paginated=copy.deepcopy(api);paginated.pages=[{'workflow_runs':[]},{'workflow_runs':[api.run]}]
    assert r.project(paginated,policy,db)==1
    print('AC-3: complete pagination, disabled authority, bounds and read-only API passed')
    workflow=(scripts.parent.parent/'.github/workflows/factory-hosted-digest.yml').read_text()
    assert '  actions: read' in workflow and "'receipt_policy':json.loads(Path('factory/policy.json').read_text())" in workflow
    # Exercise the actual hosted runner with real Git checkpoint fixtures and
    # authenticated proof discovery. Only the Slack transport is replaced locally.
    from datetime import datetime,timezone
    from unittest.mock import patch
    hosted_fixture=(scripts/'test/factory-hosted-digest.sh').read_text()
    definitions=hosted_fixture.split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory() as tmp:',1)[0]
    fixtures={};exec(definitions,fixtures)
    hosted=fixtures['m'];state=fixtures['GitAPI']();remote=fixtures['Transport']()
    config=copy.deepcopy(fixtures['config']);config['receipt_policy']=policy
    class HostedReportAPI(ReportingAPI):
        def get(self,path):
            if path=='repos/org/repo':return {'full_name':self.repo,'private':False,'default_branch':'main'}
            return super().get(path)
    source=HostedReportAPI(policy,receipt);now=datetime(2026,10,4,22,tzinfo=timezone.utc)
    with patch.object(hosted.slack,'Slack',return_value=remote):
        assert hosted.run(config,source,state,None,Path(tmp)/'hosted-first.sqlite',now)['status']=='delivered'
        head=state.head
        assert hosted.run(config,source,state,None,Path(tmp)/'hosted-repeat.sqlite',now)['status']=='not-due'
    assert remote.sends==1 and state.head==head
    checkpoint=json.loads(hosted.GitState(state,config['state_branch'],hosted.hashlib.sha256(hosted.canonical(['org/repo','C1','main']).encode()).hexdigest()).bytes)
    assert set(checkpoint['tables'])==set(hosted.TABLES)
    report=json.loads(checkpoint['tables']['digest_batches'][0]['payload'])
    assert report['merges'][0]['evidence_status']=='authenticated'
    blocked=HostedReportAPI(policy,receipt);blocked.tamper=True
    fresh_state=fixtures['GitAPI']();unsent=fixtures['Transport']()
    with patch.object(hosted.slack,'Slack',return_value=unsent):
        rejects(lambda:hosted.run(config,blocked,fresh_state,None,Path(tmp)/'blocked.sqlite',now))
    assert unsent.sends==0
    print('AC-4: actual hosted proof, public checkpoint, blocked send and unchanged repeat passed')
PYTEST

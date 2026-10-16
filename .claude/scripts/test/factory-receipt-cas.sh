#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: real Git objects/ref CAS, conflict and lost-ack restart preservation."""
import pathlib,sys,tempfile,copy,json,subprocess,os,base64,hashlib,datetime,importlib.util
text=pathlib.Path('.claude/scripts/test/factory-receipt-projection.sh').read_text().split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory()',1)[0]
sys.argv=['test',str(pathlib.Path.cwd())];exec(compile(text,'existing-receipt-fixture','exec'))
s=importlib.util.spec_from_file_location('archive',scripts/'factory-receipt-archive.py');a=importlib.util.module_from_spec(s);s.loader.exec_module(a)
class Source(API):
 artifact_id=30;repository_id=101
 def get(self,path):return {'id':self.repository_id,'full_name':self.repo,'private':False} if path=='repos/'+self.repo else super().get(path)
 def request(self,path,**kwargs):
  result=super().request(path,**kwargs)
  if path.endswith('/artifacts'):
   result[0]['artifacts'][0].update(id=self.artifact_id,name=f'factory-receipt-{self.run["id"]}-{self.run["run_attempt"]}')
   result[0]['artifacts'][0]['workflow_run'].update(id=self.run['id'],repository_id=self.repository_id,head_repository_id=self.repository_id)
  return result
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp);work=root/'git';work.mkdir()
 def git(*args,input=None,env=None,check=True):return subprocess.run(['git','-C',str(work),*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=check)
 def out(*args):return git(*args).stdout.decode().strip()
 git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');(work/'README.md').write_text('reviewed');(work/'reports').mkdir();oldpath='reports/'+'0'*64+'.json';(work/oldpath).write_bytes(b'opaque existing encrypted feedback envelope');git('add','.');git('commit','-qm','bootstrap')
 ref='refs/heads/factory-reporting-state';initial=out('rev-parse','HEAD');git('update-ref',ref,initial);tree=out('rev-parse',initial+'^{tree}')
 branch='factory-reporting-state';conditions={'ref_name':{'include':[ref],'exclude':[]}}
 def rule(i,kinds,bypass):return {'id':i,'source':'org/repo','source_type':'Repository','target':'branch','enforcement':'active','conditions':conditions,'rules':[{'type':k} for k in kinds],'bypass_actors':bypass,'updated_at':'2026-10-14T00:00:00Z'}
 policies={1:rule(1,['update'],[{'actor_id':7,'actor_type':'Integration','bypass_mode':'always'}]),2:rule(2,['non_fast_forward','deletion'],[])}
 class State:
  repo='org/repo';conflict=False;always_conflict=False;lost=False;patches=0;failed=False;fail_after_ack=False;before_patch=None;policy_drift=False
  def request(self,path,method='GET',payload=None):
   assert path.startswith('repos/org/repo');suffix=path.removeprefix('repos/org/repo').lstrip('/')
   if method=='GET':
    if self.failed:raise RuntimeError('state API unavailable during reconciliation')
    if not suffix:return {'id':101,'full_name':self.repo,'private':False,'archived':False,'default_branch':'main'}
    if suffix.startswith('rules/branches/'):return [{'type':x['type'],'ruleset_id':i} for i,p in policies.items() for x in p['rules']]
    if suffix.startswith('rulesets/'):return policies[int(suffix.rsplit('/',1)[1])]
    if suffix.startswith('compare/'):
     base,head=suffix.split('?',1)[0].removeprefix('compare/').split('...');ancestor=git('merge-base','--is-ancestor',base,head,check=False).returncode==0
     return {'base_commit':{'sha':base},'merge_base_commit':{'sha':out('merge-base',base,head)},'status':'identical' if base==head else 'ahead' if ancestor else 'diverged','behind_by':0 if ancestor else 1,'ahead_by':int(out('rev-list','--count',base+'..'+head)),'total_commits':int(out('rev-list','--count',base+'..'+head))}
    if suffix.startswith('git/ref/'):return {'ref':ref,'object':{'type':'commit','sha':out('rev-parse',ref)}}
    if suffix.startswith('git/commits/'):
     sha=suffix.rsplit('/',1)[1];parts=out('show','-s','--format=%T %P',sha).split();return {'sha':sha,'tree':{'sha':parts[0]},'parents':[{'sha':p} for p in parts[1:]]}
    if suffix.startswith('git/trees/'):
     sha=suffix.rsplit('/',1)[1];rows=[]
     for line in out('ls-tree',sha).splitlines():
      mode,kind,tail=line.split(' ',2);blob,name=tail.split('\t');rows.append({'path':name,'mode':mode,'type':kind,'sha':blob,**({'size':int(out('cat-file','-s',blob))} if kind=='blob' else {})})
     return {'sha':sha,'truncated':False,'tree':rows}
    if suffix.startswith('git/blobs/'):
     sha=suffix.rsplit('/',1)[1];raw=git('cat-file','blob',sha).stdout;return {'sha':sha,'encoding':'base64','size':len(raw),'content':base64.b64encode(raw).decode()}
   if method=='POST' and suffix=='git/blobs':return {'sha':git('hash-object','-w','--stdin',input=base64.b64decode(payload['content'])).stdout.decode().strip()}
   if method=='POST' and suffix=='git/trees':
    index=root/'temporary-index';index.unlink(missing_ok=True);env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',payload['base_tree'],env=env)
    for entry in payload['tree']:git('update-index','--add','--cacheinfo',entry['mode']+','+entry['sha']+','+entry['path'],env=env)
    sha=git('write-tree',env=env).stdout.decode().strip();index.unlink();return {'sha':sha}
   if method=='POST' and suffix=='git/commits':
    sha=git('commit-tree',payload['tree'],'-p',payload['parents'][0],input=payload['message'].encode()).stdout.decode().strip()
    if self.policy_drift:policies[1]['updated_at']='2026-10-16T00:00:00Z'
    return {'sha':sha,'tree':{'sha':payload['tree']},'parents':[{'sha':p} for p in payload['parents']]}
   if method=='PATCH' and suffix=='git/refs/heads/'+branch:
    assert payload['force'] is False;self.patches+=1;current=out('rev-parse',ref)
    if self.before_patch:
     callback=self.before_patch;self.before_patch=None;callback();current=out('rev-parse',ref)
    if self.conflict or self.always_conflict:
     self.conflict=False
     data=git('hash-object','-w','--stdin',input=b'concurrent encrypted checkpoint').stdout.decode().strip();newtree=self.request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',current+'^{tree}'),'tree':[{'path':'reports/'+'1'*64+'.json','mode':'100644','type':'blob','sha':data}]})['sha'];race=git('commit-tree',newtree,'-p',current,input=b'other writer').stdout.decode().strip();git('update-ref',ref,race,current);current=race
    if git('merge-base','--is-ancestor',current,payload['sha'],check=False).returncode:raise ValueError('real Git non-fast-forward CAS conflict')
    git('update-ref',ref,payload['sha'],current)
    if self.lost:
     self.lost=False;self.failed=self.fail_after_ack;raise RuntimeError('ref acknowledgement lost after actual Git update')
    return {'ref':ref,'object':{'sha':payload['sha']}}
   raise AssertionError((path,method))
 source=Source(policy,receipt);state=State();trust=root/'receipt-trust.json';trust.write_text(json.dumps({'schema_version':1,'repository':'org/repo','profiles':[{'id':'approved','status':'active','policy_sha256':r.coordinator.policy_hash(policy),'runtime':policy['receipts']['trusted_revisions']['a'*40]}],'legacy_revisions':{}}))
 approval=root/'receipt-bootstrap.json';approval.write_text(json.dumps({'schema_version':1,'repository':'org/repo','repository_id':101,'private':False,'branch':branch,'bootstrap_sha':initial,'bootstrap_tree':tree,'coverage_from':'2026-10-15T00:00:00Z','observed_at':'2026-10-15T00:00:00Z','writer_app_id':7,'policies':{str(i):a.digest(a.canonical(p)) for i,p in policies.items()}}))
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo');state.conflict=True;state.lost=True
 result=a.append_delivery(source,state,policy,20,trust,store,approval,stream)
 assert result['status']=='already-appended' and state.patches==2
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 assert git('show',ref+':reports/'+'1'*64+'.json').stdout==b'concurrent encrypted checkpoint'
 head=out('rev-parse',ref);restarted=State();assert a.append_delivery(source,restarted,policy,20,trust,store,approval,stream)['status']=='already-appended' and restarted.patches==0 and out('rev-parse',ref)==head
 source.artifact_id=31
 try:a.append_delivery(source,restarted,policy,20,trust,store,approval,stream)
 except ValueError as e:assert 'conflict' in str(e)
 else:raise AssertionError('replacement artifact evaded same-attempt conflict')
 assert out('rev-parse',ref)==head
 source.artifact_id=30;source.run['id']=21;exhausted=State();exhausted.always_conflict=True
 try:a.append_delivery(source,exhausted,policy,21,trust,store,approval,stream)
 except ValueError as e:assert 'three CAS' in str(e)
 else:raise AssertionError('unbounded retry accepted')
 assert exhausted.patches==3
 journal=json.loads(git('show',ref+':receipt-archive/discovery/'+stream+'.json').stdout);assert journal['records_count']==1
 before=out('rev-parse',ref)
 try:a.append_delivery(source,State(),policy,21,trust,store,approval,'d'*64)
 except ValueError as e:assert 'foreign archive' in str(e)
 else:raise AssertionError('stream changed to evade identity')
 assert out('rev-parse',ref)==before
 class Foreign(State):repo='foreign/repo'
 try:a.append_delivery(source,Foreign(),policy,21,trust,store,approval,stream)
 except ValueError as e:assert 'foreign archive' in str(e)
 else:raise AssertionError('foreign state accepted')
 source.run['id']=22;lost=State();lost.lost=True;lost.fail_after_ack=True
 try:a.append_delivery(source,lost,policy,22,trust,store,approval,stream)
 except ValueError as e:assert 'uncertain' in str(e)
 else:raise AssertionError('unobservable commit acknowledged')
 assert lost.patches==1 and a.append_delivery(source,State(),policy,22,trust,store,approval,stream)['status']=='already-appended'
 other=Source(policy,receipt);other.run['id']=23;outer_source=Source(policy,receipt);outer_source.run['id']=24;outer=State()
 outer.before_patch=lambda:a.append_delivery(other,State(),policy,23,trust,store,approval,stream)
 assert a.append_delivery(outer_source,outer,policy,24,trust,store,approval,stream)['status']=='appended' and outer.patches==2
 journal=json.loads(git('show',ref+':receipt-archive/discovery/'+stream+'.json').stdout);assert journal['records_count']==4
 retained=[]
 for name in out('ls-tree','-r','--name-only',ref).splitlines():
  if name.startswith('receipt-archive/index/'+stream+'/000/'):
   retained.extend(json.loads(git('show',ref+':'+name).stdout)['records'])
 assert {item['run_id'] for item in retained}=={20,22,23,24}
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 foreign_source=Source(policy,receipt);foreign_source.repository_id=102;foreign_source.run['repository']['id']=102;foreign_source.run['id']=25
 before=out('rev-parse',ref)
 try:a.append_delivery(foreign_source,State(),policy,25,trust,store,approval,stream)
 except ValueError as e:assert 'repository identity' in str(e)
 else:raise AssertionError('same-name foreign source repository accepted')
 assert out('rev-parse',ref)==before
 drift_source=Source(policy,receipt);drift_source.run['id']=26;drift=State();drift.policy_drift=True;before=out('rev-parse',ref)
 try:
  try:a.append_delivery(drift_source,drift,policy,26,trust,store,approval,stream)
  except ValueError as e:assert 'protection changed' in str(e)
  else:raise AssertionError('stale writer protection accepted')
 finally:policies[1]['updated_at']='2026-10-14T00:00:00Z'
 assert drift.patches==0 and out('rev-parse',ref)==before
 print('11 real Git CAS/restart/conflict/preservation scenarios passed; no live state writes')
PY

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6: real Git CAS/restarts preserve opaque concurrent worker state."""
import base64,copy,importlib.util,json,os,subprocess,tempfile,sys,textwrap
from pathlib import Path
s=importlib.util.spec_from_file_location('queue',Path('.claude/scripts/factory-reporting-queue.py'));q=importlib.util.module_from_spec(s);s.loader.exec_module(q)
config={'enabled':True,'queue_monitor_enabled':True,'repository':'org/repo','state_repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','grace_minutes':60}
with tempfile.TemporaryDirectory() as tmp:
 root=Path(tmp);work=root/'git';work.mkdir()
 def git(*args,input=None,env=None,check=True):return subprocess.run(['git','-C',str(work),*args],input=input,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=check)
 def out(*args):return git(*args).stdout.decode().strip()
 git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');(work/'README.md').write_text('protected data');(work/'reports').mkdir();worker='reports/'+'a'*64+'.json';opaque=b'opaque encrypted worker feedback';(work/worker).write_bytes(opaque);git('add','.');git('commit','-qm','bootstrap')
 initial=out('rev-parse','HEAD');ref='refs/heads/factory-reporting-state';git('update-ref',ref,initial)
 storage={'state_branch':'factory-reporting-state','bootstrap_sha':initial,'initialize':True,'policy_approvals':{}}
 class API:
  repo='org/repo';before=None;lost=False;always=False;patches=0;fail_reads=False;lose_unreadable=False
  def request(self,path,method='GET',payload=None):
   assert path.startswith('repos/org/repo');p=path.removeprefix('repos/org/repo').lstrip('/')
   if method=='GET':
    if self.fail_reads:raise RuntimeError('API unavailable')
    if not p:return {'full_name':self.repo,'archived':False,'private':False,'default_branch':'main'}
    if p.startswith('rules/branches/'):return [{'type':'non_fast_forward','ruleset_id':1},{'type':'deletion','ruleset_id':1}]
    if p=='rulesets/1':return {'enforcement':'active','bypass_actors':[]}
    if p.startswith('git/ref/'):return {'ref':ref,'object':{'type':'commit','sha':out('rev-parse',ref)}}
    if p.startswith('git/commits/'):
     sha=p.rsplit('/',1)[1];parts=out('show','-s','--format=%T %P',sha).split();return {'sha':sha,'tree':{'sha':parts[0]},'parents':[{'sha':v} for v in parts[1:]]}
    if p.startswith('git/trees/'):
     sha=p.rsplit('/',1)[1].split('?')[0];rows=[]
     for line in out('ls-tree','-r',sha).splitlines():
      mode,kind,tail=line.split(' ',2);blob,name=tail.split('\t');rows.append({'path':name,'mode':mode,'type':kind,'sha':blob,'size':int(out('cat-file','-s',blob))})
     return {'sha':sha,'truncated':False,'tree':rows}
    if p.startswith('git/blobs/'):
     sha=p.rsplit('/',1)[1];raw=git('cat-file','blob',sha).stdout;return {'sha':sha,'encoding':'base64','size':len(raw),'content':base64.b64encode(raw).decode()}
   if method=='POST' and p=='git/blobs':return {'sha':out_blob(base64.b64decode(payload['content']))}
   if method=='POST' and p=='git/trees':
    index=root/'index';index.unlink(missing_ok=True);env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',payload['base_tree'],env=env)
    for e in payload['tree']:git('update-index','--add','--cacheinfo',e['mode']+','+e['sha']+','+e['path'],env=env)
    tree=git('write-tree',env=env).stdout.decode().strip();index.unlink();return {'sha':tree}
   if method=='POST' and p=='git/commits':
    sha=git('commit-tree',payload['tree'],'-p',payload['parents'][0],input=payload['message'].encode()).stdout.decode().strip();return {'sha':sha,'tree':{'sha':payload['tree']},'parents':[{'sha':x} for x in payload['parents']]}
   if method=='PATCH' and p=='git/refs/heads/factory-reporting-state':
    assert payload['force'] is False;self.patches+=1
    if self.before:
     callback=self.before;self.before=None;callback()
    if self.always:worker_update()
    current=out('rev-parse',ref)
    if git('merge-base','--is-ancestor',current,payload['sha'],check=False).returncode:raise ValueError('real Git CAS conflict')
    git('update-ref',ref,payload['sha'],current)
    if self.lost:
     self.lost=False;self.fail_reads=self.lose_unreadable;raise RuntimeError('lost actual ref acknowledgement')
    return {'ref':ref,'object':{'sha':payload['sha']}}
   raise AssertionError((path,method))
 def out_blob(raw):return git('hash-object','-w','--stdin',input=raw).stdout.decode().strip()
 def worker_update():
  old=out('rev-parse',ref);api=API();tree=api.request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':'reports/'+'b'*64+'.json','mode':'100644','type':'blob','sha':out_blob(b'other encrypted snapshot')}]})['sha'];new=git('commit-tree',tree,'-p',old,input=b'concurrent worker').stdout.decode().strip();git('update-ref',ref,new,old)
 empty={'schema_version':1,'repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','stream':q.stream(config),'events':[]}
 row={'kind':'stalled','run_id':70,'run_attempt':1,'cutoff':'2026-10-15T00:00:00.000000Z','status':'pending','message_id':None,'incident':None};row['key']=q.event_key(q.stream(config),row);row['incident']=row['key'];desired=dict(empty,events=[row])
 store=q.QueueStore(API(),config,storage)
 assert store.read()['journal'] is None
 assert store.checkpoint(None,desired)['status']=='applied'
 assert q.QueueStore(API(),config,storage).read()['journal']==desired
 # Lost acknowledgement reconciles authoritative ref/blob on a fresh read.
 confirmed=copy.deepcopy(desired);confirmed['events'][0].update(status='confirmed',message_id='100.000001')
 lost=API();lost.lost=True
 assert q.QueueStore(lost,config,storage).checkpoint(desired,confirmed)['uncertain_write_reconciled']
 assert q.QueueStore(API(),config,storage).checkpoint(desired,confirmed)['status']=='already-applied'
 # Unrelated worker update is rebased without replacing any opaque bytes.
 recovery=copy.deepcopy(confirmed);r={'kind':'recovery','run_id':None,'run_attempt':None,'cutoff':'2026-10-15T01:00:00.000000Z','status':'pending','message_id':None,'incident':row['key']};r['key']=q.event_key(q.stream(config),r);recovery['events'].append(r)
 race=API();race.before=worker_update
 assert q.QueueStore(race,config,storage).checkpoint(confirmed,recovery)['status']=='applied' and race.patches==2
 assert git('show',ref+':'+worker).stdout==opaque and git('show',ref+':reports/'+'b'*64+'.json').stdout==b'other encrypted snapshot'
 def rejects(fn,text):
  try:fn()
  except ValueError as error:assert text in str(error),(text,str(error))
  else:raise AssertionError('accepted '+text)
 rejects(lambda:q.QueueStore(API(),config,storage).checkpoint(confirmed,desired),'transition')
 rejects(lambda:q.QueueStore(API(),config,storage).checkpoint(confirmed,lambda x:x),'fields')
 # Concurrent role intent is never merged by stale caller state.
 rejects(lambda:q.QueueStore(API(),config,storage).checkpoint(desired,copy.deepcopy(confirmed)),'conflict')
 # At most three unrelated worker conflicts; journal unchanged on exhaustion.
 completed=copy.deepcopy(recovery);completed['events'][-1].update(status='confirmed',message_id='101.000001')
 exhausted=API();exhausted.always=True
 rejects(lambda:q.QueueStore(exhausted,config,storage).checkpoint(recovery,completed),'three CAS')
 assert exhausted.patches==3 and q.QueueStore(API(),config,storage).read()['journal']==recovery
 # Same-path concurrent alternative transition is never conflated with ours.
 alternative=copy.deepcopy(recovery);alternative['events'][-1]['status']='uncertain'
 concurrent=API();concurrent.before=lambda:q.QueueStore(API(),config,storage).checkpoint(recovery,alternative)
 rejects(lambda:q.QueueStore(concurrent,config,storage).checkpoint(recovery,completed),'conflict')
 assert q.QueueStore(API(),config,storage).read()['journal']==alternative
 # Unknown acknowledgement remains explicit, but a fresh process can reconcile it.
 unreadable=API();unreadable.lost=True;unreadable.lose_unreadable=True
 rejects(lambda:q.QueueStore(unreadable,config,storage).checkpoint(alternative,completed),'uncertain')
 assert q.QueueStore(API(),config,storage).read()['journal']==completed
 source=Path('.claude/scripts/test/factory-reporting-queue-cas.sh').read_text()
 helpers=textwrap.dedent(' def git'+source.split(' def git',1)[1].split(" git('init'",1)[0])
 api_class=textwrap.dedent(' class API:'+source.split(' class API:',1)[1].split(' def out_blob',1)[0])
 child_prefix='import base64,copy,importlib.util,json,os,subprocess,tempfile\nfrom pathlib import Path\n'
 child_prefix+=f"root=Path({str(root)!r});work=root/'git';ref={ref!r};config=json.loads({json.dumps(config)!r});storage=json.loads({json.dumps(storage)!r})\n"
 child_prefix+="s=importlib.util.spec_from_file_location('queue',Path('.claude/scripts/factory-reporting-queue.py'));q=importlib.util.module_from_spec(s);s.loader.exec_module(q)\n"
 child=subprocess.run([sys.executable,'-c',child_prefix+helpers+api_class+f"assert q.QueueStore(API(),config,storage).read()['journal']==json.loads({json.dumps(completed)!r});print('fresh process protected real Git read PASS')"],text=True,capture_output=True)
 assert child.returncode==0,child.stderr
 print(child.stdout.strip())
 # Missing-role initialization cannot silently follow a changed branch head.
 git('update-ref',ref,initial,out('rev-parse',ref));initrace=API();initrace.before=worker_update
 rejects(lambda:q.QueueStore(initrace,config,storage).checkpoint(None,desired),'bootstrap')
 assert git('cat-file','-e',ref+':reports/'+q.stream(config)+'.json',check=False).returncode!=0
 assert git('show',ref+':'+worker).stdout==opaque and git('show',ref+':reports/'+'b'*64+'.json').stdout==b'other encrypted snapshot'
 # Real Git bytes with malformed journal schema cannot be used as an origin shortcut.
 current=out('rev-parse',ref);raw=b'{"schema_version":1,"schema_version":1}'
 malformed_tree=API().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':'reports/'+q.stream(config)+'.json','mode':'100644','type':'blob','sha':out_blob(raw)}]})['sha']
 malformed=git('commit-tree',malformed_tree,'-p',current,input=b'malformed queue fixture').stdout.decode().strip();git('update-ref',ref,malformed,current)
 invalid=API();rejects(lambda:q.QueueStore(invalid,config,storage).checkpoint(None,desired),'JSON invalid')
 assert invalid.patches==0 and out('rev-parse',ref)==malformed
 assert git('show',ref+':'+worker).stdout==opaque
 # Storage configuration bounds reject before runtime import/serialization.
 approval_value={'schema_version':1,'repository':'org/repo','ruleset_id':2**63,'policy_sha256':'f'*64,'policy_updated_at':'2026-10-15T00:00:00Z','observed_at':'2026-10-15T00:01:00Z','bypass_actors':[]}
 bad_storage=dict(storage,policy_approvals={str(2**63):approval_value})
 rejects(lambda:q.QueueStore(API(),config,bad_storage),'approval identity')
 rejects(lambda:q.QueueStore(API(),None,storage),'config')
 print('20 real Git queue CAS/restart/lostack/opaque preservation cases passed')
PY

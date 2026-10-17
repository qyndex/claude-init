#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-8: real Git publications preserve every other opaque blob."""
from pathlib import Path
import importlib.util
spec=importlib.util.spec_from_file_location('evidence',Path('.claude/scripts/factory-reporting-queue-evidence.py'));e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
prefix=Path('.claude/scripts/test/factory-reporting-queue-cas.sh').read_text().split("python3 - <<'PY'\n",1)[1].split(' empty={',1)[0]
assert " initial=out('rev-parse','HEAD')" in prefix
prefix=prefix.replace(" initial=out('rev-parse','HEAD')", """
 # 4,501 legal opaque archive leaves in real Git; no receipt/authentication claim.
 archive=work/'receipt-archive/objects';archive.mkdir(parents=True)
 for n in range(4501):
  name=__import__('hashlib').sha256(str(n).encode()).hexdigest();directory=archive/name[:2];directory.mkdir(exist_ok=True);(directory/(name+'.json')).write_text('{}')
 git('add','.');git('commit','-qm','large archive fixture')
 initial=out('rev-parse','HEAD')""")
suffix=r'''
 # Distinct real clean source checkout; state branch remains strictly inert.
 source_root=root/'source';source_root.mkdir();(source_root/'.github/workflows').mkdir(parents=True);(source_root/'.claude/scripts').mkdir(parents=True)
 (source_root/'.github/workflows/factory-reporting-queue.yml').write_text('reviewed fixture')
 (source_root/'.claude/scripts/factory-reporting-queue.py').write_text('# reviewed fixture')
 def sg(*args):return subprocess.check_output(['git','-C',str(source_root),*args],stderr=subprocess.DEVNULL,text=True).strip()
 sg('init','-q');sg('config','user.name','Fixture');sg('config','user.email','fixture@example.invalid');sg('add','.');sg('commit','-qm','reviewed source');source_sha=sg('rev-parse','HEAD')
 clock='2026-10-15T19:59:00Z';original_git=git
 def git(*args,input=None,env=None,check=True):
  if args and args[0]=='commit-tree':env=dict(env or os.environ,GIT_AUTHOR_DATE=clock,GIT_COMMITTER_DATE=clock)
  return original_git(*args,input=input,env=env,check=check)
 BaseAPI=API
 selections={'drill':{'run_id':900,'attempt':2},'recovery':{'run_id':901,'attempt':1},'repeat':{'run_id':902,'attempt':1}}
 class API(BaseAPI):
  final_hook=None
  def __init__(self):self.blobs=[];self.ref_reads=0;self.proof_writes=0;self.tree_reads=[]
  def request(self,path,method='GET',payload=None,*,raw=False):
   if method!='GET':self.proof_writes+=1
   if '/git/trees/' in path and method=='GET':
    identity=path.rsplit('/',1)[1].split('?')[0];recursive='?recursive=1' in path;self.tree_reads.append((identity,recursive))
    command=['ls-tree','-l']+(['-r'] if recursive else [])+[identity];entries=[]
    for line in out(*command).splitlines():
     header,name=line.split('\t');mode,kind,sha,size=header.split();entry={'path':name,'mode':mode,'type':kind,'sha':sha}
     if kind=='blob':entry['size']=int(size)
     entries.append(entry)
    return {'sha':identity,'truncated':False,'tree':entries}
   if path=='repos/org/repo/git/ref/heads/main':return {'ref':'refs/heads/main','object':{'type':'commit','sha':source_sha}}
   if path.endswith('/workflows/factory-reporting-queue.yml'):return {'id':12,'path':e.WORKFLOW,'state':'active'}
   if '/attempts/' in path:
    run=int(path.split('/runs/')[1].split('/')[0]);role=('drill','recovery','repeat')[run-900]
    return {'total_count':1,'jobs':[{'id':run+100,'run_id':run,'run_attempt':selections[role]['attempt'],'head_sha':source_sha,'name':'monitor','status':'completed','conclusion':'success','steps':[{'number':2,'name':e.STEP,'status':'completed','conclusion':'success'}]}]}
   if path.endswith('/logs'):
    run=int(path.split('/jobs/')[1].split('/')[0])-100;values=[1,0] if run==900 else [1] if run==901 else [0]
    return b''.join(b'2026-10-16T00:00:00.1234567Z '+json.dumps({'notifications':n,'reconciled':0}).encode()+b'\n' for n in values)
   if '/actions/runs/' in path:
    run=int(path.rsplit('/',1)[1]);role=('drill','recovery','repeat')[run-900];hour=20+run-900
    return {'id':run,'run_attempt':selections[role]['attempt'],'workflow_id':12,'path':e.WORKFLOW,'repository':{'id':101,'full_name':self.repo},'head_repository':{'id':101,'full_name':self.repo},'head_branch':'main','head_sha':source_sha,'event':'workflow_dispatch','status':'completed','conclusion':'success','created_at':f'2026-10-15T{hour}:00:00Z','run_started_at':f'2026-10-15T{hour}:00:01Z','updated_at':f'2026-10-15T{hour}:01:00Z'}
   if path=='repos/org/repo/git/ref/heads/factory-reporting-state' and method=='GET':
    self.ref_reads+=1
    if self.ref_reads==2 and self.final_hook:hook=self.final_hook;self.final_hook=None;hook()
   value=super().request(path,method,payload)
   if path=='repos/org/repo':value['id']=101
   if '/git/commits/' in path and method=='GET':value['committer']={'date':out('show','-s','--format=%cI',value['sha'])}
   if '/git/blobs/' in path and method=='GET':self.blobs.append(path.rsplit('/',1)[1])
   return value
 empty={'schema_version':1,'repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','stream':q.stream(config),'events':[]}
 api=API();clock='2026-10-15T19:59:59Z';q.QueueStore(api,config,storage).checkpoint(None,empty)
 # Unrelated encrypted worker update between initialization and first alert is legal.
 clock='2026-10-15T20:00:02Z';worker_update()
 row={'kind':'drill','run_id':900,'run_attempt':2,'cutoff':'2026-10-15T20:00:03.000000Z','status':'pending','message_id':None,'incident':None};row['key']=q.event_key(q.stream(config),row);row['incident']=row['key']
 pending=dict(empty,events=[row]);clock='2026-10-15T20:00:03Z';q.QueueStore(api,config,storage).checkpoint(empty,pending)
 confirmed=copy.deepcopy(pending);confirmed['events'][0].update(status='confirmed',message_id='100.000001');clock='2026-10-15T20:00:04Z';q.QueueStore(api,config,storage).checkpoint(pending,confirmed)
 clock='2026-10-15T20:30:00Z';worker_update()
 recovery=copy.deepcopy(confirmed);item={'kind':'recovery','run_id':None,'run_attempt':None,'cutoff':'2026-10-15T21:00:02.000000Z','status':'pending','message_id':None,'incident':row['key']};item['key']=q.event_key(q.stream(config),item);recovery['events'].append(item)
 clock='2026-10-15T21:00:02Z';q.QueueStore(api,config,storage).checkpoint(confirmed,recovery)
 final=copy.deepcopy(recovery);final['events'][1].update(status='confirmed',message_id='101.000001');clock='2026-10-15T21:00:03Z';q.QueueStore(api,config,storage).checkpoint(recovery,final)
 good=out('rev-parse',ref);now=e.datetime(2026,10,16,2,tzinfo=e.timezone.utc)
 proof_api=API();proof=e.observe_journal(proof_api,source_root,config,storage,selections,now)
 assert proof['mode']=='administrative-queue-observation' and proof['drill_key']==row['key'] and proof['recovery_key']==item['key'] and proof['publications']==5 and proof_api.proof_writes==0
 opaque_sha=out('rev-parse',good+':'+worker);assert opaque_sha not in proof_api.blobs
 archive_sha=out('rev-parse',good+':receipt-archive')
 assert all(identity!=archive_sha for identity,recursive in proof_api.tree_reads),'evidence traversed archive subtree'
 # Recursive calls belong to existing QueueStore role loading, not history trees.
 assert len(out('ls-tree','-r',archive_sha).splitlines())==4501
 count=2
 def rejects(fn):
  global count
  try:fn()
  except ValueError:count+=1;return
  raise AssertionError('untrusted journal/history accepted')
 def reset():
  current=out('rev-parse',ref)
  if current!=good:git('update-ref',ref,good,current)
 def custom(raw=None,other=False,archive=False,merge=False,date='2026-10-15T21:00:30Z'):
  global clock
  clock=date;base=out('rev-parse',ref);entries=[]
  if raw is not None:entries.append({'path':'reports/'+q.stream(config)+'.json','mode':'100644','type':'blob','sha':out_blob(raw)})
  if archive:
   archive_path='receipt-archive/'+out('ls-tree','-r',archive_sha).splitlines()[0].split('\t')[1]
   entries.append({'path':archive_path,'mode':'100644','type':'blob','sha':out_blob(b'changed archive object')})
  if other:entries.append({'path':worker,'mode':'100644','type':'blob','sha':out_blob(b'private changed worker bytes')})
  tree=BaseAPI().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':entries})['sha']
  args=['commit-tree',tree,'-p',base]+(['-p',initial] if merge else [])
  changed=git(*args,input=b'actual negative fixture').stdout.decode().strip();git('update-ref',ref,changed,base)
 # Queue-path writes cannot also change opaque blobs, even with a valid journal.
 custom(q.canonical(final)+b'\n',archive=True);rejects(lambda:e.observe_journal(API(),source_root,config,storage,selections,now));reset()
 custom(q.canonical(final)+b'\n',other=True);rejects(lambda:e.observe_journal(API(),source_root,config,storage,selections,now));reset()
 custom(merge=True);rejects(lambda:e.observe_journal(API(),source_root,config,storage,selections,now));reset()
 copied=dict(storage,bootstrap_sha=good);rejects(lambda:e.observe_journal(API(),source_root,config,copied,selections,now))
 custom(q.canonical(recovery));rejects(lambda:e.observe_journal(API(),source_root,config,storage,selections,now));reset()
 # Exact current run attempt is checked against immutable selected drill facts.
 selections['drill']['attempt']=3
 rejects(lambda:e.observe_journal(API(),source_root,config,storage,selections,now));selections['drill']['attempt']=2
 extra=copy.deepcopy(final);third=dict(row,run_id=905,status='confirmed',message_id='102.000001',cutoff='2026-10-15T22:00:00.000000Z');third['key']=q.event_key(q.stream(config),third);third['incident']=third['key'];extra['events'].append(third)
 custom(q.canonical(extra));rejects(lambda:e.observe_journal(API(),source_root,config,storage,selections,now));reset()
 # Real equivalent objects with an out-of-window pending publication must reject.
 pending_sha=out('rev-parse',good+'^');pending_parent=out('rev-parse',pending_sha+'^')
 clock='2026-10-15T23:00:02Z';outside=git('commit-tree',out('rev-parse',pending_sha+'^{tree}'),'-p',pending_parent,input=b'outside selected run').stdout.decode().strip()
 clock='2026-10-15T21:00:03Z';tail=git('commit-tree',out('rev-parse',good+'^{tree}'),'-p',outside,input=b'actual confirmed suffix').stdout.decode().strip();git('update-ref',ref,tail,good)
 rejects(lambda:e.observe_journal(API(),source_root,config,storage,selections,now));reset()
 # Frozen role remains valid across unrelated final head movement.
 moving=API();moving.final_hook=worker_update
 assert e.observe_journal(moving,source_root,config,storage,selections,now)['role_sha256']==proof['role_sha256'];count+=1;reset()
 changing=API();changing.final_hook=lambda:custom(q.canonical(final)+b'\n')
 rejects(lambda:e.observe_journal(changing,source_root,config,storage,selections,now));reset()
 # Capacity is explicit refusal, never accepting a partial history as complete.
 for i in range(25):worker_update()
 rejects(lambda:e.observe_journal(API(),source_root,config,storage,selections,now));reset()
 print(f'{count} real Git protected journal/publication preservation cases passed; no live credit')
'''
exec(compile(prefix+suffix,'real-Git-queue-journal-evidence-fixture','exec'))
PY

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
bash .claude/scripts/test/factory-receipt-git-objects.sh
python3 -u - <<'PYTEST'
"""AC-6/AC-7/AC-8: >1000 actual retained appends, not synthetic stage facts."""
from pathlib import Path
import shutil,tempfile,textwrap
def space_preflight():
 if shutil.disk_usage(tempfile.gettempdir()).free < 2*1024**3:
  raise RuntimeError("fixture temporary volume has less than2GiB free; no history run started")
space_preflight()
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct approved tasks',1)[0]
cases=r'''
 from collections import OrderedDict
 import atexit
 object_spec=importlib.util.spec_from_file_location('history_git_objects',scripts/'test/factory-receipt-git-objects.py');go=importlib.util.module_from_spec(object_spec);object_spec.loader.exec_module(go)
 objects=go.GitObjects(work);atexit.register(objects.close)
 original_git=git
 def git(*args,input=None,env=None,check=True):
  if len(args)==2 and args[0]=='show' and input is None and env is None and check:
   return subprocess.CompletedProcess(args,0,objects.read(args[1])[2],b'')
  if len(args)==2 and args[0]=='rev-parse' and input is None and env is None and check:
   return subprocess.CompletedProcess(args,0,(objects.read(args[1])[0]+'\n').encode(),b'')
  if len(args)==5 and args[:2]==('log','--format=%H') and args[3]=='--' and a.state_paths.valid_hash(args[2],40) and input is None and env is None and check:
   rows=objects.path_history(args[2],args[4])
   if rows is not None:return subprocess.CompletedProcess(args,0,(''.join(sha+'\n' for sha in rows)).encode(),b'')
  if len(args)==4 and args[:2]==('merge-base','--is-ancestor') and input is None and env is None:
   code=0 if objects.compare(args[2],args[3]) is not None else 1
   if check and code:raise subprocess.CalledProcessError(code,args)
   return subprocess.CompletedProcess(args,code,b'',b'')
  result=original_git(*args,input=input,env=env,check=check)
  if args and args[0]=='fetch':objects.reset_writer()
  return result
 provider_cache=OrderedDict();provider_bytes=0
 class HistoryState(PipelineState):
  def request(self,target,method='GET',payload=None):
   global provider_bytes
   immutable=method=='GET' and any(target.startswith('repos/org/repo/git/'+kind+'/') for kind in ('trees','commits','blobs')) and a.state_paths.valid_hash(target.rsplit('/',1)[1],40)
   if method=='GET' and target.startswith('repos/org/repo/compare/'):
    selectors=target.split('?',1)[0].rsplit('/',1)[1].split('...')
    immutable=len(selectors)==2 and all(a.state_paths.valid_hash(sha,40) for sha in selectors)
   if method=='GET' and target.startswith('repos/org/repo/commits?'):
    selected=parse_qs(urlparse(target).query).get('sha',[])
    immutable=len(selected)==1 and a.state_paths.valid_hash(selected[0],40)
   if immutable and target in provider_cache:
    raw=provider_cache.pop(target);provider_cache[target]=raw;return json.loads(raw)
   if method=='POST' and target=='repos/org/repo/git/trees':
    return {'sha':objects.write_tree(payload['base_tree'],payload['tree'])}
   if method=='GET' and '/git/trees/' in target:
    sha=target.rsplit('/',1)[1];value={'sha':sha,'truncated':False,'tree':objects.tree(sha)}
   elif method=='GET' and '/git/commits/' in target:
    value=objects.commit(target.rsplit('/',1)[1])
   elif method=='GET' and '/git/blobs/' in target:
    sha,kind,raw=objects.read(target.rsplit('/',1)[1]);assert kind=='blob'
    value={'sha':sha,'encoding':'base64','size':len(raw),'content':base64.b64encode(raw).decode()}
   elif immutable and '/compare/' in target:
    value=objects.compare(*selectors)
    if value is None:value=super().request(target,method,payload)
   elif method=='GET' and '/pulls/' in target:
    number=int(target.rsplit('/',1)[1]);n=number-6;assert 1<=n<=1001
    return {'number':number,'merged':True,'merge_commit_sha':f'{n:040x}','merged_at':'2026-10-15T01:00:00Z','base':{'repo':{'id':101,'full_name':'org/repo'}}}
   else:value=super().request(target,method,payload)
   if immutable:
    raw=json.dumps(value).encode()
    while provider_cache and provider_bytes+len(raw)>33554432:
     _,removed=provider_cache.popitem(last=False);provider_bytes-=len(removed)
    if len(raw)<=33554432:provider_cache[target]=raw;provider_bytes+=len(raw)
   return copy.deepcopy(value)
 blob_spec=importlib.util.spec_from_file_location('history_blob_provider',scripts/'test/factory-receipt-blob-provider.py');bp=importlib.util.module_from_spec(blob_spec);blob_spec.loader.exec_module(bp);bp.attach(HistoryState,work,root,pull_requests={n+6:{'number':n+6,'merged':True,'merge_commit_sha':f'{n:040x}','merged_at':'2026-10-15T01:00:00Z','base':{'repo':{'id':101,'full_name':'org/repo'}}} for n in range(1,1002)})
 # Prove persistent native tree writes match the original index adapter, including a stale base.
 probe_blob=git('hash-object','-w','--stdin',input=b'index equivalence').stdout.decode().strip()
 probe_base=tree;probes=[]
 for name in ('index-a','index-b'):
  payload={'base_tree':probe_base,'tree':[{'path':name,'mode':'100644','type':'blob','sha':probe_blob}]}
  probe_base=HistoryState().request('repos/org/repo/git/trees','POST',payload)['sha'];probes.append((payload,probe_base))
 probes.append(({'base_tree':tree,'tree':[{'path':'index-a','mode':'100644','type':'blob','sha':probe_blob}]},probes[0][1]))
 for payload,expected in probes:
  assert HistoryState().request('repos/org/repo/git/trees','POST',payload)['sha']==expected
  assert State().request('repos/org/repo/git/trees','POST',payload)['sha']==expected
 total=1001;end='2026-10-15T23:00:00Z';store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo')
 policy['specs']={str(n):{'path':f'specs/active/{n}.md','sha256':revision,'task_ids':[f'T-{n}']} for n in range(1,total+1)}
 receipt['policy_sha256']=r.coordinator.policy_hash(policy)
 document=json.loads(trust.read_bytes());document['profiles'][0]['policy_sha256']=receipt['policy_sha256'];trust.write_text(json.dumps(document))
 for sha in (tree,out('rev-parse',ref+'^{tree}')):
  assert HistoryState().request('repos/org/repo/git/trees/'+sha)==State().request('repos/org/repo/git/trees/'+sha)
 # Every response still crosses production budget wrappers. Persistent cat-file
 # reads and exact-object caches replace subprocess overhead, never authority.
 # The exact reviewed origin has no archive data. Only the real scanner publishes
 # prefix credit; an ancestry comparison or test-provided complete flag never does.
 completed=0;metadata=[]
 import datetime
 for n in range(1,total+1):
  rc=copy.deepcopy(receipt);rc.update(spec=str(n),task_ids=[f'T-{n}'],pull_request=n+6,merge_sha=f'{n:040x}')
  item=Source(policy,rc);item.run['id']=n+19;item.artifact_id=n+29
  item.run['created_at']=(datetime.datetime(2026,10,15,tzinfo=datetime.timezone.utc)+datetime.timedelta(seconds=n)).isoformat().replace('+00:00','Z');metadata.append(copy.deepcopy(item.run))
  item.pr.update(number=n+6,merge_commit_sha=rc['merge_sha']);item.sources[policy['specs'][str(n)]['path']]=b'approved spec'
  try:
   result=a.append_delivery(item,HistoryState(),policy,n+19,trust,store,approval,stream)
   assert result['status']=='appended',result
  except ValueError as error:
   raise AssertionError(f'actual retained append {n}/{total} blocked after {completed} authenticated real-Git appends: {error}') from error
  completed=n
  journal=json.loads(git('show',ref+':receipt-archive/discovery/'+stream+'.json').stdout)
  assert journal['records_count']==n
  assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
  if n==1 or n%8==0:
   for resume in range(256):
    try:origin=a.advance_origin(HistoryState(),approval,commit_budget=16,tree_pages=8)
    except ValueError as error:raise AssertionError(f'actual completed-origin resume after {completed} real appends blocked: {error}') from error
    if origin['frozen_complete']:break
   assert origin['frozen_complete'],'actual origin progress did not complete'
  if n==1 or n%25==0:print(f'actual authenticated retained appends={completed}/{total}; real Git commits='+out('rev-list','--count',ref),flush=True)
 import shutil
 saved=Path(tempfile.mkdtemp(prefix='t287-actual-retained-'))
 subprocess.run(['git','clone','--bare','--no-hardlinks',str(work),str(saved/'git')],check=True,capture_output=True)
 shutil.copyfile(trust,saved/'receipt-trust.json');shutil.copyfile(approval,saved/'receipt-bootstrap.json')
 (saved/'context.json').write_text(json.dumps({'policy':policy,'store':store,'stream':stream,'end':end,'actual_appends':completed,'base_source':'925b2d24dd5dbf16c3f7b49b43a9defac06f597e'}))
 print('actual retained diagnostic prefix saved='+str(saved),flush=True)
 assert completed>1000
 assert int(out('rev-list','--count',ref))>1000
 # Actual partition/watch publications defeat the filtered1000result cap.
 ds=importlib.util.spec_from_file_location('history_discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(ds);ds.loader.exec_module(d)
 reader_spec=importlib.util.spec_from_file_location('history_reader',scripts/'test/factory-receipt-history-reader.py');hr=importlib.util.module_from_spec(reader_spec);reader_spec.loader.exec_module(hr)
 runs=hr.runs(metadata,policy,'2026-10-15T00:00:00Z',end)
 def current_origin():
  for resume in range(512):
   origin=a.advance_origin(HistoryState(),approval,commit_budget=16,tree_pages=8)
   if origin['frozen_complete']:return
  raise AssertionError('bounded origin invocations failed to make actual progress')
 current_origin()
 for call in range(256):
  d.backfill(runs,HistoryState(),policy,approval,stream,interval_end=end,page_size=100,tree_pages=10)
  current_origin()  # Authenticate each broad watch publication before its next consumer.
  manifest=json.loads(git('show',ref+':receipt-archive/backfill/'+stream+'.json').stdout)
  progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
  if manifest['epoch']>=1 and manifest['last_round_gaps']==0 and manifest['round_gaps']==0 and manifest['stack']==[[int(a.instant(manifest['interval_start']).timestamp()),int(a.instant(manifest['interval_end']).timestamp())]] and progress['scan']['complete']:break
 assert manifest['epoch']>=1 and manifest['last_round_gaps']==0,manifest
 progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
 assert progress['watch']['count']==1001 and progress['scan']['complete'],{'watch':progress['watch'],'scan_complete':progress['scan']['complete']}
 print('actual1001source rows partitioned beyondclamped1000API; protectedwatch progress persisted',flush=True)
 current_origin()
 for resume in range(32):
  checkpoint=a.checkpoint_projection(HistoryState(),policy,trust,store,approval,stream,interval_end=end,limit=128)
  if resume%2==1:current_origin()
  if checkpoint['frozen_complete']:break
 assert checkpoint['frozen_complete'] and checkpoint['next_segment']==total
 selected=out('rev-parse',ref);publication_count=(total+127)//128;staged=0;stage_writes=0
 for page in range(1,publication_count+1):
  remaining=(total%128 or 128) if page==1 else 128
  for offset in range(0,remaining,8):
   stage=a.stage_projection(HistoryState(),policy,trust,store,approval,stream,interval_end=end,history_head=selected,page=page,offset=offset,limit=8)
   assert stage['status']=='staged',stage
   staged+=stage['facts_count'];stage_writes+=1
   if stage_writes%8==0:current_origin()
  print('actual protectedstage page='+str(page)+'; authenticatedfacts='+str(staged),flush=True)
 assert staged==1001
 current_origin()
 context={'work':str(work),'trust':str(trust),'approval':str(approval),'policy':policy,'store':store,'stream':stream,'end':end,'selected':selected,'campaign':stage['campaign'],'metadata':metadata,'database':str(root/'fresh.sqlite')}
 # Keep genuine full source/stage context before either fresh-process reader can
 # expose a capacity gap, without fabricating producer or publication history.
 final_saved=Path(tempfile.mkdtemp(prefix='t287-full-staged-'))
 subprocess.run(['git','clone','--bare','--no-hardlinks',str(work),str(final_saved/'git')],check=True,capture_output=True)
 shutil.copyfile(trust,final_saved/'receipt-trust.json');shutil.copyfile(approval,final_saved/'receipt-bootstrap.json');(final_saved/'context.json').write_text(json.dumps(context))
 print('actual1001source/staged history saved='+str(final_saved),flush=True)
 for mode in ('projection','coverage'):
  context['mode']=mode
  child=subprocess.run([sys.executable,str(scripts/'test/factory-receipt-history-reader.py')],input=json.dumps(context).encode(),capture_output=True)
  if child.returncode:raise AssertionError(mode+' fresh-process actual1001 failed: '+child.stderr.decode())
  print(child.stdout.decode().strip(),flush=True)
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual1001retained appends/source rows/protectedwindows/stages/freshSQLite/as-observedcoverage passed; no all-history/taskcredit')
'''
prefix,body=(fixture+pipeline+cases).split('with tempfile.TemporaryDirectory() as tmp:\n',1)
# Preserve local fixture failures before TemporaryDirectory cleanup. This never
# imports a copied capsule as authority or grants successful acceptance credit.
tail=r'''
 except subprocess.CalledProcessError as error:
  raw=error.stderr if isinstance(error.stderr,bytes) else str(error.stderr or '').encode()
  print('fixture Git stderr: '+raw[:4096].decode('utf-8',errors='replace'),file=sys.stderr,flush=True)
  raise
 finally:
  if sys.exc_info()[0] is not None and 'work' in globals() and (work/'.git').is_dir():
   try:
    failed=Path(tempfile.mkdtemp(prefix='t287-failed-history-'))
    subprocess.run(['git','clone','--bare','--no-hardlinks',str(work),str(failed/'git')],check=True,capture_output=True)
    for name,path in (('receipt-bootstrap.json',globals().get('approval')),('receipt-trust.json',globals().get('trust'))):
     if path is not None and Path(path).is_file():shutil.copyfile(path,failed/name)
    captured={name:globals()[name] for name in ('policy','store','stream','end','metadata','selected') if name in globals()}
    captured.update(failure_diagnostic_only=True,actual_appends=globals().get('completed',0),observed_head=out('rev-parse',ref),original_work=str(work))
    if 'stage' in globals():captured['campaign']=stage.get('campaign')
    (failed/'context.json').write_text(json.dumps(captured))
    print('failure fixture preserved='+str(failed),flush=True)
   except Exception:
    # A full/broken filesystem can also prevent preservation; never replace the
    # original failure with a secondary snapshot error.
    print('failure fixture preservation unavailable; original error retained',file=sys.stderr,flush=True)
'''
exec(compile(prefix+'with tempfile.TemporaryDirectory() as tmp:\n try:\n'+textwrap.indent(body,' ')+tail,'actual-large-retained-history','exec'))
PYTEST

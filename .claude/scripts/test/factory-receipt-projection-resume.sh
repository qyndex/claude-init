#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: real protected Git stages reconstruct >128 facts in fresh Python/SQLite."""
from pathlib import Path
base=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 from urllib.parse import quote,urlparse,parse_qs
 import textwrap
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo');end='2026-10-15T23:00:00Z'
 # Authenticate each synthetic source record using the real record builder, then
 # publish data-only objects in one real Git fixture commit (not129 live merges).
 policy['specs']={f'{n:03}':{'path':f'specs/active/{n:03}.md','sha256':revision,'task_ids':[f'T-{n}']} for n in range(1,130)}
 receipt['policy_sha256']=r.coordinator.policy_hash(policy)
 doc=json.loads(trust.read_bytes());doc['profiles'][0]['policy_sha256']=receipt['policy_sha256'];trust.write_text(json.dumps(doc))
 changes={};refs=[]
 for n in range(1,130):
  rc=copy.deepcopy(receipt);rc.update(spec=f'{n:03}',task_ids=[f'T-{n}'],pull_request=n,merge_sha=f'{n:040x}')
  source=Source(policy,rc);source.run['id']=n+1000;source.pr.update(number=n,merge_commit_sha=rc['merge_sha']);source.artifact_id=n+2000
  source.sources[policy['specs'][rc['spec']]['path']]=b'approved spec'
  record,materials=a.build_record(source,policy,n+1000,trust,store)
  encoded=a.canonical(record);key=a.digest(encoded);changes[f'receipt-archive/objects/{key[:2]}/{key}.json']=encoded
  reference={'run_id':n+1000,'attempt':1,'artifact_id':n+2000,'record_sha256':key};refs.append(dict(reference,segment=n-1))
  identity={'repository':'org/repo','stream':stream,'run_id':n+1000,'attempt':1};ikey=a.digest(a.canonical(identity))
  changes[f'receipt-archive/index/{stream}/identities/{ikey[:2]}/{ikey}.json']=a.canonical(dict(identity,schema_version=1,artifact_id=n+2000,record_sha256=key,segment=n-1))
  changes[a.state_paths.segment_path(stream,n-1)]=a.canonical({'schema_version':1,'repository':'org/repo','stream':stream,'number':n-1,'records':[reference]})
  for material,value in materials.items():changes[f'receipt-archive/materials/{material[:2]}/{material}.json']=a.canonical({'schema_version':1,'sha256':material,'encoding':'base64','content':value})
 changes['receipt-archive/discovery/'+stream+'.json']=a.canonical({'schema_version':1,'repository':'org/repo','stream':stream,'coverage_from':'2026-10-15T00:00:00Z','next_segment':129,'records_count':129})
 def publish(changes):
  current=out('rev-parse',ref);entries=[]
  for path,raw in changes.items():entries.append({'path':path,'mode':'100644','type':'blob','sha':git('hash-object','-w','--stdin',input=raw).stdout.decode().strip()})
  tree=State().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':entries})['sha']
  sha=git('commit-tree',tree,'-p',current,input=b'protected fixture publication').stdout.decode().strip();git('update-ref',ref,sha,current);return sha
 frozen=publish(changes);frozen_tree=out('rev-parse',frozen+'^{tree}')
 ap=json.loads(approval.read_bytes());binding={k:ap[k] for k in ('repository','repository_id','private','branch','bootstrap_sha','bootstrap_tree','coverage_from','writer_app_id','policies')};binding.update(stream=stream,approval_sha256=a.digest(a.canonical(ap)),policy_sha256=r.coordinator.policy_hash(policy),interval_end=end)
 path='receipt-archive/projection/'+stream+'.json';previous=None;publications=[]
 for start in range(0,129,8):
  stop=min(start+8,129);progress={'schema_version':1,'binding':binding,'frozen_head':frozen,'frozen_tree':frozen_tree,'records_count':129,'next_segment':stop,'window':{'start':start,'stop':stop,'references':refs[start:stop],'trust_sha256':a.digest(trust.read_bytes())},'previous_blob':previous,'publication_parent':out('rev-parse',ref)}
  a._projection_checkpoint(progress,binding);publication=publish({path:a.canonical(progress)});previous=out('rev-parse',ref+':'+path);publications.append((publication,previous,progress))
 history=out('rev-parse',ref)
 class CachedState(State):
  cache={}
  def request(self,path,method='GET',payload=None):
   if method=='GET' and any('/git/'+kind+'/' in path for kind in ('commits','trees','blobs')):
    if path not in self.cache:self.cache[path]=super().request(path,method,payload)
    return copy.deepcopy(self.cache[path])
   if method=='GET' and '/compare/' in path:
    first,last=path.split('?',1)[0].rsplit('/',1)[1].split('...');ancestor=git('merge-base','--is-ancestor',first,last,check=False).returncode==0;return {'base_commit':{'sha':first},'merge_base_commit':{'sha':out('merge-base',first,last)},'status':'identical' if first==last else 'ahead' if ancestor else 'diverged','behind_by':0 if ancestor else 1,'ahead_by':0 if first==last else 1,'total_commits':0 if first==last else 1}
   if method=='GET' and '/commits?' in path:
    query=parse_qs(urlparse(path).query);size=int(query['per_page'][0]);page=int(query.get('page',['1'])[0]);rows=out('log','--format=%H',query['sha'][0],'--',query['path'][0]).splitlines();return [{'sha':sha} for sha in rows[(page-1)*size:page*size]]
   if method=='GET' and '/pulls/' in path:
    n=int(path.rsplit('/',1)[1]);return {'number':n,'merged':True,'merge_commit_sha':f'{n:040x}','merged_at':('2026-10-16T00:00:00.123456Z' if n==129 else '2026-10-15T01:00:00.123456Z'),'base':{'repo':{'id':101,'full_name':'org/repo'}}}
   return super().request(path,method,payload)
 # Batch fixture publication, not a claim the production writer issued129
 # deliveries. Every source record was authenticated above; the consumer must
 # independently reauthenticate these stage hints and full retained materials.
 stage_binding=dict(binding,frozen_head=frozen,frozen_tree=frozen_tree,trust_sha256=a.digest(trust.read_bytes()))
 campaign=a.digest(a.canonical(stage_binding));stage_changes={}
 def stagepath(kind,identity):
  key=a.digest(a.canonical([kind,identity]));return 'receipt-archive/stages/'+campaign+'/'+key[:2]+'/'+key+'.json'
 for publication,blob,progress in publications:
  facts=[]
  for reference in progress['window']['references']:
   n=reference['run_id']-1000
   fact={'repository':'org/repo','repository_id':101,'run_id':n+1000,'attempt':1,'record_sha256':reference['record_sha256'],'pr':n,'merge_sha':f'{n:040x}','merged_at':'2026-10-16T00:00:00.123456Z' if n==129 else '2026-10-15T01:00:00.123456Z','artifact_id':n+2000,'tasks':[f'T-{n}'],'segment':n-1};facts.append(fact)
   for kind,identity in (('execution',[n+1000,1]),('task',f'T-{n}')):
    stage_changes[stagepath(kind,identity)]=a.canonical({'schema_version':1,'campaign':campaign,'kind':kind,'identity':identity,'run_id':n+1000,'attempt':1,'record_sha256':reference['record_sha256']})
  stage_changes[stagepath('window',[publication,0,8])]=a.canonical({'schema_version':1,'binding':stage_binding,'publication_sha':publication,'checkpoint_blob':blob,'offset':0,'stop':len(facts),'facts':facts})
 publish(stage_changes)
 # Large batched fixture publication needs the same bounded origin continuation
 # as ordinary retained writers before a fresh consumer can trust its prefix.
 for continuation in range(256):
  origin=a.advance_origin(CachedState(),approval)
  assert origin['coverage_complete'] is False
  if origin['frozen_complete']:break
 assert origin['frozen_complete'],'bounded fixture origin continuation did not complete'
 assert continuation>0,'large fixture did not exercise persisted origin continuation'
 assert a.verify_bootstrap(CachedState(),approval)['head']==out('rev-parse',ref)
 # Separate interpreter imports actual production code and real Git fixture API.
 context={'work':str(work),'root':str(root),'ref':ref,'branch':branch,'policies':policies,'policy':policy,'trust':str(trust),'approval':str(approval),'stream':stream,'store':store,'end':end,'history':history,'campaign':campaign}
 (root/'context.json').write_text(json.dumps(context))
 header=base.split('\nwith tempfile.TemporaryDirectory() as tmp:',1)[0]
 state_code=textwrap.dedent(base.split(' class State:',1)[1].split('\n source=Source',1)[0]);state_code='class State:'+textwrap.indent(state_code,' ')
 cached_code=textwrap.dedent(cases.split(' class CachedState(State):',1)[1].split('\n # Batch fixture publication',1)[0]);cached_code='class CachedState(State):'+textwrap.indent(cached_code,' ')
 child='import sys\nchild_arguments=sys.argv[-2:]\n'+header+'\nfrom urllib.parse import urlparse,parse_qs\ncontext=json.loads(pathlib.Path(child_arguments[0]).read_text());globals().update(context);work=pathlib.Path(work);root=pathlib.Path(root);policies={int(k):v for k,v in policies.items()}\ndef git(*args,input=None,env=None,check=True):return subprocess.run(["git","-C",str(work),*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=check)\ndef out(*args):return git(*args).stdout.decode().strip()\n'+state_code+'\n'+cached_code+'\nresult=a.reconstruct_interval(CachedState(),policy,pathlib.Path(child_arguments[1]),trust,store,approval,stream,interval_end=end,history_head=history,campaign=campaign)\nprint(json.dumps(result))\n'
 compile(child,'fresh-projection-child','exec')
 (root/'child.py').write_text(child)
 for name in ('fresh.sqlite','another-fresh.sqlite'):
  completed=subprocess.run([sys.executable,str(root/'child.py'),str(root/'context.json'),str(root/name)],capture_output=True,text=True)
  assert completed.returncode==0,completed.stderr
  result=json.loads(completed.stdout);assert result['projection_complete'] and not result['coverage_complete'] and result['facts_count']==129 and result['interval_facts_count']==128
  import sqlite3
  with sqlite3.connect(root/name) as db:assert db.execute('SELECT count(*) FROM delivery_receipts').fetchone()==(129,)
 def child_result(name):
  return subprocess.run([sys.executable,str(root/'child.py'),str(root/'context.json'),str(root/name)],capture_output=True,text=True)
 # Reopen existing SQLite in a third fresh process and reapply actual revocation.
 approved_trust=trust.read_bytes();current=json.loads(approved_trust);current['profiles'][0]['status']='revoked';trust.write_text(json.dumps(current))
 revoked=child_result('fresh.sqlite');assert revoked.returncode==0,revoked.stderr
 with sqlite3.connect(root/'fresh.sqlite') as db:
  assert db.execute('SELECT DISTINCT status FROM delivery_trust').fetchall()==[('withdrawn',)]
  assert db.execute('SELECT count(*) FROM delivery_interval').fetchone()==(128,)
  assert {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}=={'delivery_receipts','delivery_provenance','delivery_trust','delivery_times','delivery_interval'}
 trust.write_bytes(approved_trust)
 dbpath=root/'fresh.sqlite';snapshot=dbpath.read_bytes()
 baseline=out('rev-parse',ref)
 def restore_tree():
  previous=out('rev-parse',ref);restored=git('commit-tree',out('rev-parse',baseline+'^{tree}'),'-p',previous,input=b'fixture restores data snapshot without rewriting history').stdout.decode().strip();git('update-ref',ref,restored,previous)
 def rejected(reason):
  result=child_result('fresh.sqlite');assert result.returncode!=0 and reason in result.stderr,result.stderr
  assert dbpath.read_bytes()==snapshot,'invalid proof mutated SQLite'
 # Existing valid protected bytes do not authorize a forged schema or fake facts.
 stage_paths=[path for path in stage_changes if 'binding' in json.loads(stage_changes[path])]
 badstage=json.loads(stage_changes[stage_paths[0]]);badstage['schema_version']=True
 publish({stage_paths[0]:a.canonical(badstage)});rejected('stage schema');restore_tree()
 # Lost stage history is incomplete, never a short-page success or SQLite advance.
 index=root/'remove-index';env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',out('rev-parse',ref+'^{tree}'),env=env);git('update-index','--force-remove',stage_paths[0],env=env);tree=git('write-tree',env=env).stdout.decode().strip();index.unlink()
 previous=out('rev-parse',ref);missing=git('commit-tree',tree,'-p',previous,input=b'missing required stage').stdout.decode().strip();git('update-ref',ref,missing,previous)
 incomplete=child_result('fresh.sqlite');assert incomplete.returncode==0,incomplete.stderr
 assert json.loads(incomplete.stdout)['projection_complete'] is False and dbpath.read_bytes()==snapshot
 restore_tree()
 # Actual retained materials, not captured stageJSON/hash assertions, authorize facts.
 material=a.digest(b'approved spec');material_path=f'receipt-archive/materials/{material[:2]}/{material}.json'
 raw=json.loads(changes[material_path]);raw['content']=base64.b64encode(b'altered').decode()
 publish({material_path:a.canonical(raw)});rejected('archive material');restore_tree()
 # Exact protected interval/source selectors and actual store privacy remain required.
 saved_context=dict(context);context['store']={'repository':'org/repo','visibility':'private'};(root/'context.json').write_text(json.dumps(context));rejected('visibility');context=saved_context;(root/'context.json').write_text(json.dumps(context))
 # Existing SQLite annotations are also untrusted cache rows, never authority.
 extra=root/'extra-annotation.sqlite';extra.write_bytes(dbpath.read_bytes())
 with sqlite3.connect(extra) as db:db.execute('INSERT INTO delivery_trust VALUES(?,?)',('T-unproven','active'))
 extra_snapshot=extra.read_bytes();unproven=child_result('extra-annotation.sqlite')
 assert unproven.returncode!=0 and 'SQLite row bound' in unproven.stderr, 'unproved SQLite annotation survived source reconstruction'
 assert extra.read_bytes()==extra_snapshot
 # Arbitrary SQL/triggers are never accepted as a reconstruction cache schema.
 with sqlite3.connect(dbpath) as db:db.execute('CREATE TRIGGER untrusted AFTER INSERT ON delivery_receipts BEGIN DELETE FROM delivery_receipts; END')
 snapshot=dbpath.read_bytes();rejected('foreign SQLite schema')
 # Normal producer re-entry with a different allowed work limit is idempotent.
 # The last checkpoint has one ref: limit8 and limit1 produce equivalent hints.
 overlap=a.stage_projection(CachedState(),policy,trust,store,approval,stream,interval_end=end,history_head=history,page=1,limit=1)
 assert overlap['status']=='staged' and overlap['campaign']==campaign
 repeated=child_result('overlap.sqlite')
 assert repeated.returncode==0,repeated.stderr
 repeated=json.loads(repeated.stdout)
 assert repeated['projection_complete'] and repeated['facts_count']==129 and repeated['interval_facts_count']==128 and repeated['coverage_complete'] is False
 # Even duplicate hints are rederived and compared, never skipped as trusted JSON.
 overlap_path=overlap['stage_path'];bad=json.loads(git('show',ref+':'+overlap_path).stdout)
 bad['facts'][0]['merged_at']='2026-10-15T00:00:00Z'
 publish({overlap_path:a.canonical(bad)})
 overlap_snapshot=(root/'overlap.sqlite').read_bytes();conflict=child_result('overlap.sqlite')
 assert conflict.returncode!=0 and 'staged facts differ' in conflict.stderr,conflict.stderr
 assert (root/'overlap.sqlite').read_bytes()==overlap_snapshot
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('11 real Git fresh-process/fresh-SQLite129-reference interval/revocation/gap/material/privacy/SQL/idempotent-overlap cases passed; no global coverage or task credit')
'''
exec(compile(base+cases,'real-git-projection-resume','exec'))
PY

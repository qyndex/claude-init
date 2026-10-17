#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: actual protected producers feed fresh retained SQLite readers."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 from urllib.parse import urlparse,parse_qs
 import textwrap,sqlite3
 class PipelineState(State):
  def request(self,target,method='GET',payload=None):
   if method=='GET' and '/compare/' in target:
    base,head=target.split('?',1)[0].rsplit('/',1)[1].split('...');ancestor=out('merge-base',base,head)
    return {'base_commit':{'sha':base},'merge_base_commit':{'sha':ancestor},'status':'identical' if base==head else 'ahead','behind_by':0,'ahead_by':int(out('rev-list','--count',base+'..'+head)),'total_commits':int(out('rev-list','--count',base+'..'+head))}
   if method=='GET' and '/commits?' in target:
    query=parse_qs(urlparse(target).query);rows=out('log','--format=%H',query['sha'][0],'--',query['path'][0]).splitlines();size=int(query['per_page'][0]);page=int(query.get('page',['1'])[0]);return [{'sha':sha} for sha in rows[(page-1)*size:page*size]]
   if method=='GET' and '/pulls/' in target:
    number=int(target.rsplit('/',1)[1]);assert number in (7,8)
    return {'number':number,'merged':True,'merge_commit_sha':('b' if number==7 else 'c')*40,'merged_at':'2026-10-15T01:00:00.123456Z','base':{'repo':{'id':101,'full_name':'org/repo'}}}
   return super().request(target,method,payload)
 # Two distinct approved tasks are actually appended, never batched stage JSON.
 policy['specs']={f'{n:03}':{'path':f'specs/active/{n:03}.md','sha256':revision,'task_ids':[f'T-{n}']} for n in (1,2)}
 receipt['policy_sha256']=r.coordinator.policy_hash(policy)
 doc=json.loads(trust.read_bytes());doc['profiles'][0]['policy_sha256']=receipt['policy_sha256'];trust.write_text(json.dumps(doc))
 sources=[];store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo');end='2026-10-15T23:00:00Z'
 for n in (1,2):
  rc=copy.deepcopy(receipt);rc.update(spec=f'{n:03}',task_ids=[f'T-{n}'],pull_request=n+6,merge_sha=('b' if n==1 else 'c')*40)
  item=Source(policy,rc);item.run['id']=n+19;item.pr.update(number=n+6,merge_commit_sha=rc['merge_sha']);item.sources[policy['specs'][rc['spec']]['path']]=b'approved spec'
  assert a.append_delivery(item,PipelineState(),policy,n+19,trust,store,approval,stream)['status']=='appended';sources.append(item)
 first=a.checkpoint_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,limit=1)
 assert first['next_segment']==1 and first['frozen_complete'] is False
 history=out('rev-parse',ref)
 one=a.stage_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,history_head=history,limit=1)
 assert one['status']=='staged' and one['facts_count']==1
 campaign=one['campaign']
 # Fresh processes import actual code and use the real immutable Git adapter.
 context={'root':str(root),'work':str(work),'ref':ref,'branch':branch,'policies':policies,'policy':policy,'trust':str(trust),'approval':str(approval),'stream':stream,'store':store,'end':end,'history':history,'campaign':campaign}
 context_path=root/'context.json';context_path.write_text(json.dumps(context))
 header=fixture.split('\nwith tempfile.TemporaryDirectory() as tmp:',1)[0]
 state_code=textwrap.dedent(fixture.split(' class State:',1)[1].split('\n source=Source',1)[0]);state_code='class State:'+textwrap.indent(state_code,' ')
 pipeline_code=textwrap.dedent(cases.split(' class PipelineState(State):',1)[1].split('\n # Two distinct',1)[0]);pipeline_code='class PipelineState(State):'+textwrap.indent(pipeline_code,' ')
 child=header+'\nfrom urllib.parse import urlparse,parse_qs\ncontext=json.loads(pathlib.Path('+repr(str(context_path))+').read_text());globals().update(context);root=pathlib.Path(root);work=pathlib.Path(work);policies={int(k):v for k,v in policies.items()}\ndef git(*args,input=None,env=None,check=True):return subprocess.run(["git","-C",str(work),*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=check)\ndef out(*args):return git(*args).stdout.decode().strip()\n'+state_code+'\n'+pipeline_code+'\nprint(json.dumps(a.reconstruct_interval(PipelineState(),policy,root/"projection.sqlite",trust,store,approval,stream,interval_end=end,history_head=history,campaign=campaign)))\n'
 compile(child,'actual-producer-pipeline-child','exec');runner=root/'reader.py';runner.write_text(child)
 def read():return subprocess.run([sys.executable,str(runner)],capture_output=True,text=True,timeout=90)
 partial=read();assert partial.returncode==0,partial.stderr
 assert json.loads(partial.stdout)['projection_complete'] is False and not (root/'projection.sqlite').exists()
 second=a.checkpoint_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,limit=1)
 assert second['next_segment']==2 and second['frozen_complete']
 context['history']=out('rev-parse',ref);context_path.write_text(json.dumps(context))
 two=a.stage_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,history_head=context['history'],limit=1)
 assert two['status']=='staged' and two['campaign']==campaign
 assert a.stage_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,history_head=context['history'],page=2,limit=1)['status']=='already-staged'
 # Live source artifacts are now unavailable; the retained chain still reconstructs.
 for source in sources:
  source.expired=True
  try:r.authenticate(source,policy,source.run['id'],historical=True,trust_path=trust,trust_mode='profile')
  except ValueError as error:assert 'artifact missing' in str(error)
  else:raise AssertionError('expired source fixture was not actually expired')
 complete=read();assert complete.returncode==0,complete.stderr
 result=json.loads(complete.stdout);assert result['projection_complete'] and result['facts_count']==2 and result['interval_facts_count']==2 and result['coverage_complete'] is False
 db=root/'projection.sqlite'
 with sqlite3.connect(db) as sql:assert sql.execute('SELECT task FROM delivery_receipts ORDER BY task').fetchall()==[('T-1',),('T-2',)]
 active=trust.read_bytes();revoked=json.loads(active);revoked['profiles'][0]['status']='revoked';trust.write_text(json.dumps(revoked))
 reread=read();assert reread.returncode==0,reread.stderr
 with sqlite3.connect(db) as sql:assert sql.execute('SELECT status FROM delivery_trust ORDER BY task').fetchall()==[('withdrawn',),('withdrawn',)]
 trust.write_bytes(active);assert read().returncode==0
 snapshot=db.read_bytes()
 def reject(reason):
  result=read();assert result.returncode!=0 and reason in result.stderr,result.stderr
  assert db.read_bytes()==snapshot
 context['store']={'repository':'org/repo','visibility':'private'};context_path.write_text(json.dumps(context));reject('visibility');context['store']=store;context_path.write_text(json.dumps(context))
 saved=out('rev-parse',ref);bad=json.loads(git('show',ref+':'+two['stage_path']).stdout);bad['facts'][0]['tasks']=['T-forged']
 blob=git('hash-object','-w','--stdin',input=a.canonical(bad)).stdout.decode().strip();newtree=PipelineState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':two['stage_path'],'type':'blob','mode':'100644','sha':blob}]})['sha']
 invalid=git('commit-tree',newtree,'-p',saved,input=b'contradictory stage fixture').stdout.decode().strip();git('update-ref',ref,invalid,saved);reject('staged facts differ')
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual two-task append/checkpoint/lineage/stage/fresh-SQLite chain passed: partial→complete, expired source, current revocation and atomic privacy/conflicting-stage rejection; no global coverage/task credit')
'''
exec(compile(fixture+cases,'actual-projection-window-pipeline','exec'))
PY
# These contribute additional bounded capacity and historical-family evidence;
# only the pipeline above claims actual producer-to-consumer integration.
bash .claude/scripts/test/factory-receipt-projection-resume.sh
bash .claude/scripts/test/factory-receipt-runtime-compatibility.sh

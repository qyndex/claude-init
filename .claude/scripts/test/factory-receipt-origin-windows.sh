#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-7: real Git ancestry windows with protected checkpoint origin."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 from urllib.parse import parse_qs,urlsplit
 import textwrap
 class OriginState(State):
  def request(self,path,method='GET',payload=None):
   if method=='GET' and '/compare/' in path:
    base,head=path.split('?',1)[0].split('/compare/')[1].split('...');ancestor=git('merge-base',base,head).stdout.decode().strip()
    return {'base_commit':{'sha':base},'merge_base_commit':{'sha':ancestor},'status':'identical' if base==head else 'ahead','ahead_by':int(out('rev-list','--count',base+'..'+head)),'behind_by':0,'total_commits':int(out('rev-list','--count',base+'..'+head))}
   if method=='GET' and '/commits?' in path:
    q=parse_qs(urlsplit(path).query);sha=out('log','-1','--format=%H',q['sha'][0],'--',q['path'][0]);return [{'sha':sha}] if sha else []
   return super().request(path,method,payload)
 # More than the old256 lifetime ancestor limit, with actual immutable Git edges.
 parent=initial
 for number in range(300):parent=git('commit-tree',tree,'-p',parent,input=('history'+str(number)).encode()).stdout.decode().strip()
 git('update-ref',ref,parent,initial);frozen=parent;checked=[]
 # Real fresh Python processes reconstruct the protected checkpoint on each call.
 transport=textwrap.dedent(fixture.split(' class State:',1)[1].split(' source=Source',1)[0])
 transport='class State:\n'+textwrap.indent(transport.lstrip('\n'),' ')
 origin_transport=textwrap.dedent(cases.split(' class OriginState',1)[1].split(' # More than',1)[0])
 origin_transport='class OriginState'+origin_transport
 config=root/'origin-config.json';config.write_text(json.dumps({'root':str(root),'work':str(work),'ref':ref,'branch':branch,'policies':policies,'approval':str(approval),'scripts':str(scripts)}))
 runner=root/'origin-runner.py'
 header='import pathlib,json,subprocess,os,base64,sys,importlib.util\nfrom urllib.parse import parse_qs,urlsplit\nc=json.loads(pathlib.Path(sys.argv[1]).read_text());root=pathlib.Path(c["root"]);work=pathlib.Path(c["work"]);ref=c["ref"];branch=c["branch"];policies={int(k):v for k,v in c["policies"].items()}\ndef git(*args,input=None,env=None,check=True):return subprocess.run(["git","-C",str(work),*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=check)\ndef out(*args):return git(*args).stdout.decode().strip()\n'
 runner.write_text(header+transport+'\n'+origin_transport+'\ns=importlib.util.spec_from_file_location("archive",pathlib.Path(c["scripts"])/"factory-receipt-archive.py");a=importlib.util.module_from_spec(s);s.loader.exec_module(a)\nprint(json.dumps(a.advance_origin(OriginState(),c["approval"],commit_budget=16,tree_pages=4)))\n')
 for call in range(40):
  # Fresh module object each invocation; durable progress is read from Git only.
  spec=importlib.util.spec_from_file_location('fresh'+str(call),scripts/'factory-receipt-archive.py');fresh=importlib.util.module_from_spec(spec);spec.loader.exec_module(fresh)
  process=subprocess.run([sys.executable,str(runner),str(config)],capture_output=True,text=True,timeout=60)
  assert process.returncode==0,process.stderr
  result=json.loads(process.stdout)
  checked.append(result['checked_commits'])
  assert result['frozen_head']==frozen and result['coverage_complete'] is False
  if result['frozen_complete']:break
 assert result['frozen_complete'] and result['checked_commits']==301 and len(checked)>16 and checked==sorted(set(checked))
 assert result['suffix_pending'] is True and result['head']!=frozen
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 path='receipt-archive/origin/'+a.archive_stream('org/repo')+'.json'
 saved=json.loads(git('show',ref+':'+path).stdout);assert saved['complete'] and saved['publication_parent']==out('rev-parse',ref+'^')
 def rejects(fn,reason):
  try:fn()
  except ValueError as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('untrusted origin accepted '+reason)
 # Root hash/caller JSON is not a resume argument.
 try:fresh.advance_origin(OriginState(),approval,cursor=saved)
 except TypeError:pass
 else:raise AssertionError('caller supplied cursor accepted')
 # Authenticated publication must change checkpoint only, not unrelated state.
 current=out('rev-parse',ref);bad=dict(saved,publication_parent=current)
 blob=git('hash-object','-w','--stdin',input=a.canonical(bad)).stdout.decode().strip()
 state=OriginState();newtree=state.request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':path,'mode':'100644','type':'blob','sha':blob},{'path':'README.md','mode':'100644','type':'blob','sha':blob}]})['sha']
 commit=git('commit-tree',newtree,'-p',current,input=b'forged publication').stdout.decode().strip();git('update-ref',ref,commit,current)
 rejects(lambda:fresh.advance_origin(OriginState(),approval),'checkpoint-only')
 git('update-ref',ref,current,commit)
 # Never import even a structurally valid checkpoint already at reviewed origin.
 original=json.loads(approval.read_text());modified=dict(original,bootstrap_sha=current,bootstrap_tree=out('rev-parse',current+'^{tree}'));approval.write_text(json.dumps(modified))
 rejects(lambda:fresh.advance_origin(OriginState(),approval),'pre-bootstrap')
 approval.write_text(json.dumps(original))
 # An unchanged completed publication is now GET-only. A genuine intervening
 # inert commit ensures this test still exercises publication CAS/lost-ack.
 parent=out('rev-parse',ref);suffix=git('commit-tree',out('rev-parse',ref+'^{tree}'),'-p',parent,input=b'new inert suffix before CAS').stdout.decode().strip();git('update-ref',ref,suffix,parent)
 # Concurrent reporter and lost acknowledgement: CAS retry preserves every byte.
 race=OriginState();race.conflict=True;race.lost=True
 raced=fresh.advance_origin(race,approval,commit_budget=16,tree_pages=4)
 assert race.patches==2 and raced['uncertain_write_reconciled'] and raced['coverage_complete'] is False
 assert git('show',ref+':reports/'+'1'*64+'.json').stdout==b'concurrent encrypted checkpoint'
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 stable=out('rev-parse',ref)
 # Tampered binding cannot become origin merely through valid blob hashes.
 changed=json.loads(git('show',ref+':'+path).stdout);changed['binding']['repository_id']=999;changed['publication_parent']=stable
 payload=git('hash-object','-w','--stdin',input=a.canonical(changed)).stdout.decode().strip()
 changed_tree=OriginState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':path,'mode':'100644','type':'blob','sha':payload}]})['sha']
 wrong=git('commit-tree',changed_tree,'-p',stable,input=b'tampered binding').stdout.decode().strip();git('update-ref',ref,wrong,stable)
 rejects(lambda:fresh.advance_origin(OriginState(),approval),'schema/binding')
 git('update-ref',ref,stable,wrong)
 # A merge anywhere in the frozen ancestry cannot hide behind comparison metadata.
 merge=git('commit-tree',tree,'-p',initial,'-p',frozen,input=b'merged ancestor').stdout.decode().strip();git('update-ref',ref,merge,stable)
 rejects(lambda:fresh.advance_origin(OriginState(),approval),'missing or merged')
 # A temporary executable, subsequently deleted, still fails intermediate tree validation.
 evil=git('hash-object','-w','--stdin',input=b'executable').stdout.decode().strip()
 evil_tree=OriginState().request('repos/org/repo/git/trees','POST',{'base_tree':tree,'tree':[{'path':'evil.sh','mode':'100755','type':'blob','sha':evil}]})['sha']
 bad=git('commit-tree',evil_tree,'-p',initial,input=b'bad intermediate tree').stdout.decode().strip();safe=git('commit-tree',tree,'-p',bad,input=b'deleted executable').stdout.decode().strip();git('update-ref',ref,safe,merge)
 rejects(lambda:fresh.advance_origin(OriginState(),approval),'state blob path/mode')
 git('update-ref',ref,stable,safe)
 # Force a real suffix so policy drift during publication remains exercised.
 parent=out('rev-parse',ref);suffix=git('commit-tree',out('rev-parse',ref+'^{tree}'),'-p',parent,input=b'new inert suffix before policy publication').stdout.decode().strip();git('update-ref',ref,suffix,parent)
 # Policy drift and perpetual competing writers never yield a completed origin.
 drift=OriginState();drift.policy_drift=True
 rejects(lambda:fresh.advance_origin(drift,approval),'protection changed')
 policies[1]['updated_at']='2026-10-14T00:00:00Z'
 conflict=OriginState();conflict.always_conflict=True
 rejects(lambda:fresh.advance_origin(conflict,approval),'three CAS')
 assert conflict.patches==3
 # Tree continuation is also per-invocation, not permission to skip unchecked nodes.
 latest=out('rev-parse',ref);git('update-ref',ref,initial,latest)
 first=fresh.advance_origin(OriginState(),approval,commit_budget=1,tree_pages=1)
 assert first['frozen_complete'] is False and first['checked_commits']==0
 second=fresh.advance_origin(OriginState(),approval,commit_budget=1,tree_pages=1)
 assert second['frozen_complete'] is True and second['checked_commits']==1
 # Global byte budget spans actual distinct fetched responses, not cache hits.
 # Thirty-two distinct commit payloads plus distinct root/reports tree payloads
 # exceed32MiB while every individual payload remains below1MiB.
 latest=out('rev-parse',ref);git('update-ref',ref,frozen,latest)
 class LargeCommit(OriginState):
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if method=='GET' and any('/git/'+kind+'/' in path for kind in ('commits','trees')):value=dict(value,padding='x'*1000000)
   return value
 rejects(lambda:fresh.advance_origin(LargeCommit(),approval,commit_budget=32),'response capacity gap')
 for kwargs in ({'commit_budget':0},{'tree_pages':9},{'commit_budget':True}):rejects(lambda kwargs=kwargs:fresh.advance_origin(OriginState(),approval,**kwargs),'bounds invalid')
 print('origin windows: PASS; real300-commit history, fresh Python process restarts, strict frozen coverage, concurrency/tamper/merge/intermediate executable negatives, encrypted bytes, checkpoint-only publication, copied bootstrap, partial tree and global byte-budget negatives')
'''
exec(compile(fixture+cases,'origin-window-real-git-fixture','exec'))
PY

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""Eight actual stage facts, fixed protected anchor and real transport accounting."""
from pathlib import Path
import re
base=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
resume=Path('.claude/scripts/test/factory-receipt-projection-resume.sh').read_text()
assert "cases=r'''\n" in resume and ' # Batch fixture publication' in resume
setup=resume.split("cases=r'''\n",1)[1].split(' # Batch fixture publication',1)[0]
# Small local fixture of8 real authenticated records, not a producer/capacity claim.
setup=re.sub(r'\b129\b','8',setup).replace('range(1,130)','range(1,9)')
cases=r'''
 from types import SimpleNamespace
 ts=importlib.util.spec_from_file_location('stage_transport',scripts/'factory-reporting-transport.py');t=importlib.util.module_from_spec(ts);ts.loader.exec_module(t)
 # Actual RoutedAPI creates/account/caches requests; only gh provider is local Git.
 class Provider(CachedState):
  def __init__(self):self.cache={};self.hook=None;self.fired=False
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if method=='GET' and '/pulls/' in path and self.hook and not self.fired:
    self.fired=True;self.hook()
   return value
 provider=Provider();roles={'source':0,'writer':0};methods={};original_process=t.process.run
 def boundary(command,*,env,stdin=None,**kwargs):
  method,path=command[5:7];payload=json.loads(stdin.read()) if stdin is not None else None
  role='source' if env['GH_TOKEN']=='source-fixture' else 'writer';assert env['GH_TOKEN'] in ('source-fixture','writer-fixture')
  roles[role]+=1;methods[method]=methods.get(method,0)+1
  return SimpleNamespace(returncode=0,stdout=json.dumps(provider.request(path,method,payload)).encode(),stderr=b'')
 t.process.run=boundary
 original_verify=a.verify_bootstrap;verifications=[]
 def verify(*args,**kwargs):verifications.append(1);return original_verify(*args,**kwargs)
 a.verify_bootstrap=verify
 try:
  stable=out('rev-parse',ref);api=t.RoutedAPI('org/repo','source-fixture','writer-fixture')
  result=a.stage_projection(api,policy,trust,store,approval,stream,interval_end=end,history_head=history,limit=8)
  assert result['status']=='staged' and result['facts_count']==8 and result['coverage_complete'] is False
  stage=json.loads(git('show',ref+':'+result['stage_path']).stdout)
  assert len(stage['facts'])==8 and {f['pr'] for f in stage['facts']}==set(range(1,9))
  assert stage['facts'][-1]['merged_at']=='2026-10-16T00:00:00.123456Z','late retained fact removed'
  print(json.dumps({'bootstrap_verifications':len(verifications),'calls':api.budget.calls,'bytes':api.budget.bytes,'roles':roles,'methods':methods,'facts':len(stage['facts'])}),flush=True)
  assert len(verifications)==4,'per-fact public wrappers repeat whole bootstrap verification'
  assert api.budget.calls==sum(roles.values())<2048 and api.budget.bytes<33554432 and roles['source']==8
  after=out('rev-parse',ref)
  # Derivation still performs fresh PR reads and rejects foreign merge binding.
  class Foreign(Provider):
   def request(self,path,method='GET',payload=None):
    value=super().request(path,method,payload)
    return dict(value,merge_commit_sha='f'*40) if '/pulls/' in path else value
  def reject_run(chosen,reason):
   global provider
   provider=chosen;prior=out('rev-parse',ref);selected=t.RoutedAPI('org/repo','source-fixture','writer-fixture')
   try:a.stage_projection(selected,policy,trust,store,approval,stream,interval_end=end,history_head=history,limit=8)
   except ValueError as error:assert reason in str(error),(reason,str(error))
   else:raise AssertionError('changed stage input accepted '+reason)
   assert provider.patches==0 and out('rev-parse',ref)==prior
  reject_run(Foreign(),'PR identity')
  original_trust=trust.read_bytes();p=Provider();p.hook=lambda:trust.write_bytes(original_trust+b' ')
  try:reject_run(p,'protected origin changed')
  finally:trust.write_bytes(original_trust)
  original_approval=approval.read_bytes();p=Provider();p.hook=lambda:approval.write_bytes(original_approval+b' ')
  try:reject_run(p,'protected origin changed')
  finally:approval.write_bytes(original_approval)
  saved_policy=copy.deepcopy(policies[1]);p=Provider();p.hook=lambda:policies[1].update(updated_at='2026-10-16T00:00:00Z')
  try:reject_run(p,'protection')
  finally:policies[1]=saved_policy
  p=Provider()
  def move():
   before=out('rev-parse',ref);changed=git('commit-tree',out('rev-parse',ref+'^{tree}'),'-p',before,input=b'queue publication during fact reads').stdout.decode().strip();git('update-ref',ref,changed,before)
  p.hook=move;provider=p;selected=t.RoutedAPI('org/repo','source-fixture','writer-fixture')
  try:a.stage_projection(selected,policy,trust,store,approval,stream,interval_end=end,history_head=history,limit=8)
  except ValueError as error:assert 'origin changed' in str(error)
  else:raise AssertionError('head changed during facts accepted')
  assert p.patches==0
  git('update-ref',ref,after,out('rev-parse',ref))
  assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
  print('eight-fact anchored stage, late/foreign facts and trust/approval/policy/head races PASS; fixture transport only')
 finally:a.verify_bootstrap=original_verify;t.process.run=original_process
'''
exec(compile(base+setup+cases,'real-git-stage-anchor','exec'))
PY

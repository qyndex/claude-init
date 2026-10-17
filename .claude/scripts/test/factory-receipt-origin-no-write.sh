#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""Actual protected origin authentication, not a caller completion flag."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
origin=Path('.claude/scripts/test/factory-receipt-origin-windows.sh').read_text()
transport=origin.split("cases=r'''\n",1)[1].split(' # More than',1)[0]
cases=r'''
 class Measured(OriginState):
  def __init__(self):self.methods=[];self.calls=0
  def request(self,path,method='GET',payload=None):
   self.methods.append(method);self.calls+=1
   return super().request(path,method,payload)
 first=a.advance_origin(Measured(),approval)
 assert first['frozen_complete']
 before=out('rev-parse',ref);measured=Measured()
 result=a.advance_origin(measured,approval)
 assert out('rev-parse',ref)==before and all(method=='GET' for method in measured.methods),'completed exact-head origin redundantly writes'
 assert result['head']==before and result['frozen_complete'] and result['coverage_complete'] is False
 repeated=Measured();assert a.advance_origin(repeated,approval)['head']==before and all(m=='GET' for m in repeated.methods)
 print('unchanged exact-head origin: GET-only calls',measured.calls,'repeated',repeated.calls)
 def publish(entries,base=None):
  parent=out('rev-parse',ref);newtree=OriginState().request('repos/org/repo/git/trees','POST',{'base_tree':base or out('rev-parse',ref+'^{tree}'),'tree':entries})['sha']
  changed=git('commit-tree',newtree,'-p',parent,input=b'actual origin test publication').stdout.decode().strip();git('update-ref',ref,changed,parent);return changed
 def leaf(path,raw,mode='100644'):
  blob=git('hash-object','-w','--stdin',input=raw).stdout.decode().strip();return {'path':path,'type':'blob','mode':mode,'sha':blob}
 # Every permitted intervening namespace must scan, not use exact-head fast path.
 for path in ('reports/'+'1'*64+'.json','reports/'+'2'*64+'.json','receipt-archive/progress/'+'3'*64+'.json'):
  publish([leaf(path,b'opaque inert bytes')]);state=Measured();advanced=a.advance_origin(state,approval)
  assert 'PATCH' in state.methods and advanced['frozen_complete']
  stable=out('rev-parse',ref);again=Measured();assert a.advance_origin(again,approval)['head']==stable and set(again.methods)=={'GET'}
 def reject(call,reason):
  before=out('rev-parse',ref)
  try:call()
  except ValueError as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('untrusted origin accepted '+reason)
  assert out('rev-parse',ref)==before
 stable=out('rev-parse',ref);stable_tree=out('rev-parse',ref+'^{tree}');path='receipt-archive/origin/'+a.archive_stream('org/repo')+'.json'
 raw=git('show',ref+':'+path).stdout;saved=json.loads(raw)
 changed=dict(saved,binding=dict(saved['binding'],repository_id=999),publication_parent=stable)
 publish([leaf(path,a.canonical(changed))]);reject(lambda:a.advance_origin(Measured(),approval),'schema/binding');git('update-ref',ref,stable,out('rev-parse',ref))
 # Forged complete publication cannot hide a dangerous intermediate then deletion.
 publish([leaf('evil.sh',b'unsafe','100755')]);evil=out('rev-parse',ref)
 safe=git('commit-tree',stable_tree,'-p',evil,input=b'removed unsafe tree').stdout.decode().strip();git('update-ref',ref,safe,evil)
 forged=dict(saved,publication_parent=safe);publish([leaf(path,a.canonical(forged))])
 reject(lambda:a.advance_origin(Measured(),approval),'state blob path/mode');git('update-ref',ref,stable,out('rev-parse',ref))
 class Drift(Measured):
  reads=0
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if path.endswith('/rulesets/1'):
    self.reads+=1
    if self.reads>1:value=copy.deepcopy(value);value['updated_at']='2026-10-16T00:00:00Z'
   return value
 reject(lambda:a.advance_origin(Drift(),approval),'protection')
 original_approval=approval.read_bytes()
 class ApprovalChange(Measured):
  reads=0
  def request(self,path,method='GET',payload=None):
   if path.endswith('/rulesets/1'):
    self.reads+=1
    if self.reads==2:
     changed=json.loads(original_approval);changed['observed_at']='2026-10-15T00:01:00Z';approval.write_text(json.dumps(changed))
   return super().request(path,method,payload)
 try:reject(lambda:a.advance_origin(ApprovalChange(),approval),'origin changed')
 finally:approval.write_bytes(original_approval)
 class Move(Measured):
  refs=0
  def request(self,path,method='GET',payload=None):
   if '/git/ref/' in path:
    self.refs+=1
    if self.refs==2:publish([leaf('reports/'+'4'*64+'.json',b'concurrent queue/feedback bytes')])
   return super().request(path,method,payload)
 moving=Move()
 try:a.advance_origin(moving,approval)
 except ValueError as error:assert 'origin changed' in str(error) or 'state changed' in str(error)
 else:raise AssertionError('moving head yielded stale completed origin')
 assert set(moving.methods)=={'GET'}
 # Actual suffix publication still exercises existing CAS/lost-ack recovery.
 race=Measured();race.conflict=True;race.lost=True
 reconciled=a.advance_origin(race,approval)
 assert race.patches==2 and reconciled['uncertain_write_reconciled'] and reconciled['frozen_complete']
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('origin no-write real Git exact-head/repeat, opaque suffix, forged binding, dangerous intermediate, policy/head race, CAS/lost-ack PASS; no native credit')
'''
exec(compile(fixture+transport+cases,'origin-no-write-real-git-fixture','exec'))
PY

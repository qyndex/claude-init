#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: actual stage publication acknowledgement without duplicate material work."""
from pathlib import Path
import ast
text=Path('.claude/scripts/test/factory-reporting-hosted-maintenance.sh').read_text().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
module=ast.parse(text);node=next(n for n in module.body if isinstance(n,ast.Assign) and any(isinstance(x,ast.Name) and x.id=='cases' for x in n.targets));namespace={};exec(compile(ast.Module(body=module.body[:module.body.index(node)],type_ignores=[]),'stage-ack-loader','exec'),namespace)
prefix=node.value.value.split(' result=hosted.run',1)[0]
cases=prefix+r'''
 ms=importlib.util.spec_from_file_location('maintenance',scripts/'factory-reporting-maintenance.py');m=importlib.util.module_from_spec(ms);ms.loader.exec_module(m)
 staged=[];bases=[];actual=m.archive.stage_projection
 def observed(*args,**kwargs):
  bases.append(out('rev-parse',ref));value=actual(*args,**kwargs);staged.append(value);return value
 m.archive.stage_projection=observed
 for invocation in range(96):
  result=m.maintain(Report(),PipelineState(),policy,trust,config['receipt_archive']['store'],approval,interval_end='2026-10-15T23:00:00Z')
  if staged and staged[-1]['status']=='staged':break
 else:raise AssertionError('real protected stage was never published')
 journal=json.loads(git('show',ref+':'+progress_leaf).stdout)
 assert journal['offset']==staged[-1]['facts_count'],'successful stage publication was not acknowledged in same invocation'
 assert journal['phase']=='stage' and journal['offset']==1,journal
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'

 baseline_work=work;base=bases[-1]
 for fault in ('stage-lost','progress-race','progress-lost','concurrent-journal'):
  clone=root/('stage-'+fault);git('clone','--no-checkout',str(baseline_work),str(clone));work=clone
  git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');git('update-ref',ref,base)
  fired=[];errors=[]
  class FaultState(PipelineState):
   def request(self,target,method='GET',payload=None):
    if method=='PATCH' and not fired:
     message=out('show','-s','--format=%s',payload['sha'])
     if fault=='stage-lost' and message.startswith('factory: checked derived stage '):self.lost=True;fired.append(fault)
     elif fault in ('progress-race','progress-lost'):
      value=git('show',payload['sha']+':'+progress_leaf,check=False)
      before=git('show',ref+':'+progress_leaf,check=False)
      if value.returncode==before.returncode==0 and json.loads(value.stdout)['offset']==1 and json.loads(before.stdout)['offset']==0:
       fired.append(fault)
       if fault=='progress-race':self.before_patch=foreign_checkpoint
       else:self.lost=True
    return super().request(target,method,payload)
  def watched(*args,**kwargs):
   value=actual(*args,**kwargs)
   if fault=='concurrent-journal' and not fired and value['status']=='staged':
    fired.append(fault)
    for turn in range(16):
     m.maintain(Report(),PipelineState(),policy,trust,config['receipt_archive']['store'],approval,interval_end='2026-10-15T23:00:00Z')
     if json.loads(git('show',ref+':'+progress_leaf).stdout)['offset']==1:break
    else:raise AssertionError('concurrent actual maintenance did not acknowledge stage')
   return value
  m.archive.stage_projection=watched
  for turn in range(32):
   try:m.maintain(Report(),FaultState(),policy,trust,config['receipt_archive']['store'],approval,interval_end='2026-10-15T23:00:00Z')
   except (RuntimeError,ValueError) as error:
    assert fired,(fault,str(error))
    assert any(text in str(error) for text in ('CAS conflict','acknowledgement lost','maintenance journal changed during stage publication')),(fault,str(error))
    errors.append(str(error))
   current=json.loads(git('show',ref+':'+progress_leaf).stdout)
   if current['offset']==1:break
  else:raise AssertionError('stage acknowledgement did not resume '+fault)
  assert fired==[fault],fired
  if fault!='stage-lost':assert errors,(fault,'fault failed to reject outer scheduling write')
  messages=out('log','--format=%s',ref).splitlines();assert sum(line.startswith('factory: checked derived stage ') for line in messages)==1,(fault,'duplicate stage publication')
  assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
  if fault=='progress-race':assert git('show',ref+':reports/'+'9'*64+'.json').stdout==b'opaque concurrent acknowledgement worker'
  print('actual stage acknowledgement fault recovered: '+fault,flush=True)
 work=baseline_work
 print('actual protected stage same-invocation acknowledgement, CAS/lostack/concurrent-journal preservation PASS')

'''
exec(compile(namespace['fixture']+namespace['adapter']+cases,'stage-ack-real-git','exec'))
PY

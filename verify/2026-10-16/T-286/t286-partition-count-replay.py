from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
original=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Live source artifacts',1)[0]
pipeline=original.replace("cases.split(' class PipelineState(State):',1)","original.split(' class PipelineState(State):',1)")
setup=Path('.claude/scripts/test/factory-receipt-coverage.sh').read_text().split("cases=r'''\n",1)[1].split(' def evaluate',1)[0]
extra=r'''
 class HierarchyCap(Runs):
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs)
   if '/actions/workflows/' in target:
    query=parse_qs(urlparse(target).query)
    if query.get('created')==[start+'..'+end_created]:value=dict(value,total_count=1000)
   return value
 capped=HierarchyCap();before=manifest['epoch']
 for _ in range(12):
  d.backfill(capped,PipelineState(),policy,approval,stream,interval_end=end_created,page_size=1)
  updated=json.loads(git('show',ref+':receipt-archive/backfill/'+stream+'.json').stdout)
  if updated['epoch']>before:break
 assert updated['epoch']==before+1 and updated['last_round_gaps']==0
 value=d.coverage(capped,PipelineState(),policy,trust,store,approval,stream,interval_end=end_created,projection_end=end,history_head=context['history'],campaign=campaign,page_size=1)
 assert value['coverage_complete'] is False and value['verified_until'] is None and 'source-partition-count-inconsistent' in value['gaps'],value
 print('actual saturated parent and insufficient observed child union remain an explicit count-consistency gap')
'''
exec(compile(fixture+pipeline+setup+extra,'actual-partition-count-inconsistency','exec'))

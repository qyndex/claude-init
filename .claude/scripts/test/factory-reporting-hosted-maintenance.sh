#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: public hosted loader maintains before fresh reporting snapshot."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
adapter=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct',1)[0]
cases=r'''
 gs=importlib.util.spec_from_file_location('hosted',scripts/'factory-git-state.py');hosted=importlib.util.module_from_spec(gs);gs.loader.exec_module(hosted)
 producer=Source(policy,receipt);producer.run['created_at']='2026-10-15T00:00:30Z'
 shadow={key:value for key,value in receipt.items() if key not in ('merge_sha','task_ids')};shadow.update(merged=False,eligible=True)
 later=Source(policy,shadow);later.run.update(id=21,created_at='2026-10-15T00:00:31Z');later.artifact_id=31
 visible={'late':False};ack_faults=['race','lost','reload'];ack_seen=[]
 progress_role=a.digest(a.canonical(['reporting-maintenance-v1','org/repo',branch]));progress_leaf='reports/'+progress_role+'.json'
 report_leaf='reports/'+hashlib.sha256(hosted.canonical(['org/repo','C1','main']).encode()).hexdigest()+'.json'
 def phase(commit):
  value=git('show',commit+':'+progress_leaf,check=False)
  return None if value.returncode else json.loads(value.stdout)['phase']
 def foreign_checkpoint():
  head=out('rev-parse',ref);api=PipelineState();blob=api.request('repos/org/repo/git/blobs','POST',{'encoding':'base64','content':base64.b64encode(b'opaque concurrent acknowledgement worker').decode()})
  changed=api.request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',head+'^{tree}'),'tree':[{'path':'reports/'+'9'*64+'.json','mode':'100644','type':'blob','sha':blob['sha']}]})
  commit=api.request('repos/org/repo/git/commits','POST',{'tree':changed['sha'],'parents':[head],'message':'concurrent protected acknowledgement worker'})
  api.request('repos/org/repo/git/refs/heads/'+branch,'PATCH',{'sha':commit['sha'],'force':False})
 class CurrentState(PipelineState):
  reload_failure=False
  def request(self,target,method='GET',payload=None):
   if method=='GET' and self.reload_failure:self.reload_failure=False;raise RuntimeError('synthetic post-ack reload unavailable')
   fault=None
   if method=='PATCH' and phase(out('rev-parse',ref))=='verify' and phase(payload['sha'])=='ready' and ack_faults:
    fault=ack_faults.pop(0);ack_seen.append(fault)
    if fault=='race':self.before_patch=foreign_checkpoint
   value=super().request(target,method,payload)
   if fault=='lost':raise RuntimeError('synthetic projection acknowledgement lost')
   if fault=='reload':self.reload_failure=True
   if method=='PATCH' and not visible['late'] and git('cat-file','-e',ref+':'+report_leaf,check=False).returncode==0:visible['late']=True
   return value
 class Report:
  repo='org/repo'
  def get(self,target):
   if target=='repos/org/repo':return {'id':101,'full_name':self.repo,'private':False,'default_branch':'main'}
   return (later if '/actions/runs/21' in target else producer).get(target)
  def request(self,target,**kwargs):
   if target=='repos/org/repo/pulls?state=closed&per_page=100':return [[dict(producer.pr,merged_at='2026-10-15T01:00:00.123456Z',title='Actual retained feature',html_url='https://github.com/org/repo/pull/7')]]
   if '/actions/workflows/' in target and '/runs?' in target:
    assert 'created=' in target,'durable loader fell back to legacy successful-artifact discovery: '+target
    from urllib.parse import parse_qs,urlparse
    query=parse_qs(urlparse(target).query);lo,hi=query['created'][0].split('..');rows=[copy.deepcopy(item.run) for item in ([producer,later] if visible['late'] else [producer]) if lo<=item.run['created_at']<=hi]
    page=int(query['page'][0]);size=int(query['per_page'][0]);return {'total_count':len(rows),'workflow_runs':rows[(page-1)*size:page*size]}
   return (later if '/actions/runs/21/' in target or '/actions/artifacts/31/' in target else producer).request(target,**kwargs)
  def source(self,*args):return producer.source(*args)
 class NoSlack:
  def __getattr__(self,name):raise AssertionError('incomplete maintenance reached Slack: '+name)
 config={'enabled':True,'repository':'org/repo','state_repository':'org/repo','state_branch':branch,'branch':'main','destination':'C1','start':'2026-10-15T00:00:00Z','bootstrap_sha':initial,
         'receipt_mode':'durable','receipt_policy':policy,'state_view':{'mode':'archive','approval_path':str(approval.resolve())},
         'receipt_archive':{'approval_path':str(approval.resolve()),'trust_path':str(trust.resolve()),'store':{'repository':'org/repo','visibility':'public'},'trust_mode':'profile'}}
 result=hosted.run(config,Report(),CurrentState(),NoSlack(),root/'reporting.sqlite',datetime.datetime(2026,10,16,0,tzinfo=datetime.timezone.utc))
 assert result['status']=='incomplete' and result['coverage_complete'] is False,result
 class Delivery:
  def __init__(self):self.receipts={};self.payloads={};self.sends=0;self.drop=False
  def send(self,key,payload,destination):
   self.sends+=1;value={'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':destination,'message_id':str(self.sends)};self.receipts[key]=value;self.payloads[key]=payload
   if self.drop:raise RuntimeError('synthetic Slack response lost')
   return value
  def lookup(self,key):return {'receipt':self.receipts.get(key),'authoritative_absence':False}
 gap_seen=False
 delivery=Delivery();hosted.slack.transport=lambda client,configured,batch:delivery
 for invocation in range(96):
  try:result=hosted.run(config,Report(),CurrentState(),NoSlack(),root/('reporting-'+str(invocation)+'.sqlite'),datetime.datetime(2026,10,16,0,tzinfo=datetime.timezone.utc))
  except (ValueError,RuntimeError) as error:
   assert (type(error) is ValueError and str(error)=='real Git non-fast-forward CAS conflict') or (type(error) is RuntimeError and any(reason in str(error) for reason in ('projection acknowledgement lost','post-ack reload unavailable'))),str(error)
   assert delivery.sends==0,'acknowledgement/reload failure reached Slack'
   continue
  if result.get('phase')=='projection-pending':gap_seen=True
  if result['status']=='delivered':break
  assert result['status']=='incomplete',result
 else:raise AssertionError('hosted maintenance did not reach deliverable coverage')
 assert ack_seen==['race','lost','reload'] and not ack_faults,ack_seen
 assert git('show',ref+':reports/'+'9'*64+'.json').stdout==b'opaque concurrent acknowledgement worker'
 assert delivery.sends==1 and gap_seen,'actual public late coverage gap was not resumed before delivery'
 progress_role=a.digest(a.canonical(['reporting-maintenance-v1','org/repo',branch]))
 protected_progress=json.loads(git('show',ref+':reports/'+progress_role+'.json').stdout)
 assert protected_progress['source_epoch']>=2,'late gap reused old source epoch'
 delivered=json.loads(next(iter(delivery.payloads.values())))
 assert delivered['merges'][0]['evidence_status']=='authenticated' and delivered['merges'][0]['delivery_evidence'][0]['task']==receipt['task_ids'][0],delivered
 report_stream=hashlib.sha256(hosted.canonical(['org/repo','C1','main']).encode()).hexdigest()
 pending_state=hosted.GitState(PipelineState(),branch,report_stream,initial,state_view=config['state_view'])
 pending_store=hosted.HostedDigest(root/'pending.sqlite',dict(config,receipt_mode='legacy'),pending_state)
 pending=pending_store.prepare(Report(),'2026-10-16T00:00:00Z');delivery.drop=True
 try:pending_store.deliver(pending['key'],delivery)
 except RuntimeError as error:assert 'response lost' in str(error)
 else:raise AssertionError('lost Slack response was not uncertain')
 delivery.drop=False;sent=delivery.sends
 class Unavailable(Report):
  def request(self,*args,**kwargs):raise AssertionError('pending receipt reconciliation attempted new source maintenance')
 resumed=hosted.run(config,Unavailable(),PipelineState(),NoSlack(),root/'pending-resume.sqlite',datetime.datetime(2026,10,16,12,tzinfo=datetime.timezone.utc))
 assert resumed['status']=='delivered' and delivery.sends==sent,'pending delivery did not reconcile first: '+str(resumed)
 checked=hosted.HostedDigest(root/'pending-read.sqlite',dict(config,receipt_mode='legacy'),hosted.GitState(PipelineState(),branch,report_stream,initial,state_view=config['state_view']))
 assert checked.batch(pending['key'])['payload']==pending['payload']
 alert_spec=importlib.util.spec_from_file_location('protected_alerts',scripts/'factory-reporting-alerts.py');alerts=importlib.util.module_from_spec(alert_spec);alert_spec.loader.exec_module(alerts)
 alerts.w.state.slack.transport=lambda client,configured,batch:delivery
 alert_result=alerts.run(dict(config,monitor_enabled=True,team_id='T1'),PipelineState(),NoSlack(),datetime.datetime(2026,10,16,12,tzinfo=datetime.timezone.utc))
 assert alert_result['notifications']==0 and alert_result['health']=='current',alert_result
 transfer_spec=importlib.util.spec_from_file_location('scope_transfer',scripts/'factory-reporting-receipts.py');transfer=importlib.util.module_from_spec(transfer_spec);transfer_spec.loader.exec_module(transfer)
 for invalid in (None,1,'true',[]):
  try:transfer.project_reporting(Report(),PipelineState(),policy,root/'nonexistent.sqlite',trust,{'repository':'org/repo','visibility':'public'},approval,a.archive_stream('org/repo'),interval_end='2026-10-15T23:00:00Z',history_head='a'*40,campaign='b'*64,interval_scoped=invalid)
  except ValueError as error:assert 'scope mode invalid' in str(error),str(error)
  else:raise AssertionError('untyped scope flag accepted')
 # A later deleted report must never be silently recreated as a fresh stream.
 parent=out('rev-parse',ref);leaf='reports/'+report_stream+'.json'
 git('read-tree',ref);git('update-index','--force-remove',leaf);deleted_tree=out('write-tree')
 deleted=git('commit-tree',deleted_tree,'-p',parent,input=b'synthetic protected report deletion\n').stdout.decode().strip();git('update-ref',ref,deleted,parent)
 for _ in range(32):
  try:resumed=hosted.run(config,Report(),CurrentState(),NoSlack(),root/'deleted-report.sqlite',datetime.datetime(2026,10,16,12,tzinfo=datetime.timezone.utc))
  except ValueError as error:assert 'cannot reset historical state' in str(error),str(error);break
  assert resumed['status']=='incomplete',resumed
 else:raise AssertionError('deleted historical report was not rejected')
 assert git('cat-file','-e',ref+':'+leaf,check=False).returncode!=0
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('public durable hosted loader advances protected maintenance without artifact fallback; pending uncertain delivery reconciles before maintenance')
'''
exec(compile(fixture+adapter+cases,'hosted-maintenance-fixture','exec'))
PY

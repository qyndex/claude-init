#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: actual hosted.run, real Git and two-day additive reporting rollover."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
adapter=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct',1)[0]
cases=r'''
 from datetime import datetime,timezone
 approved=json.loads(approval.read_bytes());approved['coverage_from']='2026-10-13T00:00:00Z';approval.write_text(json.dumps(approved))
 hs=importlib.util.spec_from_file_location('hosted_rollover',scripts/'factory-git-state.py');h=importlib.util.module_from_spec(hs);hs.loader.exec_module(h)
 class Reports:
  repo='org/repo'
  def __init__(self):self.rows=[self.pr(1)]
  def pr(self,n):return {'number':n,'title':'Manual change '+str(n),'html_url':'https://github.com/org/repo/pull/'+str(n),'merged_at':'2026-10-14T01:00:00Z','merge_commit_sha':format(n,'040x'),'head':{'sha':'c'*40},'base':{'ref':'main','repo':{'full_name':self.repo}}}
  def get(self,path):
   assert path=='repos/org/repo';return {'id':101,'full_name':self.repo,'default_branch':'main','private':False}
  def request(self,path,**kwargs):
   assert kwargs=={},kwargs
   if '/pulls?' in path:
    query=parse_qs(urlparse(path).query);page=int(query['page'][0]);return self.rows[(page-1)*100:page*100]
   if '/actions/workflows/' in path and '/runs?' in path:return {'total_count':0,'workflow_runs':[]}
   raise AssertionError(path)
  def source(self,*args):raise AssertionError('empty workflow history has no source artifacts')
 class Remote:
  def __init__(self):self.messages={};self.sends=0;self.payloads={}
  def send(self,key,payload,destination):
   assert key not in self.messages,'duplicate remote send'
   self.sends+=1;self.payloads[key]=payload
   result={'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':destination,'message_id':str(self.sends)};self.messages[key]=result;return result
  def lookup(self,key):return {'receipt':self.messages.get(key),'authoritative_absence':False}
 remote=Remote();reports=Reports();h.slack.transport=lambda *args:remote
 config={'enabled':True,'repository':'org/repo','state_repository':'org/repo','destination':'C1','branch':'main','start':'2026-10-13T00:00:00Z','state_branch':branch,'receipt_mode':'durable','pr_discovery_mode':'resumable','receipt_policy':policy,'receipt_archive':{'approval_path':str(approval),'trust_path':str(trust),'store':{'repository':'org/repo','visibility':'public'},'trust_mode':'profile'},'state_view':{'mode':'archive','approval_path':str(approval.resolve())}}
 first_now=datetime(2026,10,14,22,5,tzinfo=timezone.utc);next_now=datetime(2026,10,15,22,5,tzinfo=timezone.utc)
 invocations=0
 def step(now):
  global invocations
  invocations+=1
  result=h.run(config,reports,PipelineState(),None,root/('report-'+str(invocations)+'.sqlite'),now)
  print('public step',invocations,result.get('status'),result.get('phase'),flush=True)
  assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
  return result
 # Start actual old partial campaign, then let a newer-day invocation finish it first.
 assert step(first_now)['status']=='incomplete'
 for _ in range(96):
  result=step(next_now)
  if result['status']=='delivered':break
 else:raise AssertionError('old partial campaign never delivered')
 assert remote.sends==1
 old_key=next(iter(remote.messages));old_payload=remote.payloads[old_key];old_receipt=dict(remote.messages[old_key])
 assert json.loads(old_payload)['until']==h.slack.due(first_now)
 # A newly visible old manual merge must appear as late discovery on the next day.
 reports.rows.append(reports.pr(2))
 for _ in range(96):
  result=step(next_now)
  assert result['status']!='not-due','next-day public run stuck on already-delivered old ready interval'
  if result['status']=='delivered':break
 else:raise AssertionError('next-day campaign never delivered')
 assert remote.sends==2 and remote.payloads[old_key]==old_payload and remote.messages[old_key]==old_receipt
 new_key=next(key for key in remote.messages if key!=old_key);payload=json.loads(remote.payloads[new_key])
 assert payload['until']==h.slack.due(next_now) and [row['pr'] for row in payload['merges']]==[2]
 assert payload['merges'][0]['late_discovered'] is True and payload['merges'][0]['evidence_status']=='missing'
 assert step(next_now)['status']=='not-due' and remote.sends==2
 print('actual public partial-old-first then next-day rollover, late manual merge, immutable prior receipt/payload and no resend PASS')
'''
exec(compile(fixture+adapter+cases,'actual-public-rollover','exec'))
PY

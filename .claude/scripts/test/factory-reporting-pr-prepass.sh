#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: bounded public PR scratch advances before expensive receipt work."""
from pathlib import Path
import ast
text=Path('.claude/scripts/test/factory-reporting-hosted-maintenance.sh').read_text().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
module=ast.parse(text);case_node=next(node for node in module.body if isinstance(node,ast.Assign) and any(isinstance(x,ast.Name) and x.id=='cases' for x in node.targets));prefix=ast.Module(body=module.body[:module.body.index(case_node)],type_ignores=[]);namespace={};exec(compile(prefix,'prepass-fixture-loader','exec'),namespace)
cases=next(node.value.value for node in module.body if isinstance(node,ast.Assign) and any(isinstance(x,ast.Name) and x.id=='cases' for x in node.targets))
cases=cases.split(' result=hosted.run',1)[0]+r'''
 config['pr_discovery_mode']='resumable'
 class PagedReport(Report):
  def request(self,target,**kwargs):
   if target.startswith('repos/org/repo/pulls?'):
    from urllib.parse import parse_qs,urlsplit
    page=int(parse_qs(urlsplit(target).query)['page'][0])
    return [{'number':n,'title':'manual '+str(n),'html_url':'https://github.com/org/repo/pull/'+str(n),'merged_at':'2026-10-15T01:00:00Z','merge_commit_sha':format(n,'040x'),'head':{'sha':'a'*40},'base':{'ref':'main','repo':{'full_name':'org/repo'}}} for n in range(1,202)][(page-1)*100:page*100]
   return super().request(target,**kwargs)
 result=hosted.run(config,PagedReport(),CurrentState(),NoSlack(),root/'prepass.sqlite',datetime.datetime(2026,10,16,0,tzinfo=datetime.timezone.utc))
 assert result.get('phase')=='backfill','PR enumeration delayed bounded receipt maintenance: '+str(result)
 observed=[]
 for invocation in range(64):
  result=hosted.run(config,PagedReport(),CurrentState(),NoSlack(),root/('prepass-'+str(invocation)+'.sqlite'),datetime.datetime(2026,10,16,0,tzinfo=datetime.timezone.utc))
  if result.get('phase')=='pull-requests':
   current=json.loads(git('show',ref+':'+progress_leaf).stdout)
   assert current['phase']=='ready','incomplete PR observation published verification intent'
   observed.append(current['source_epoch'])
   if len(observed)==2:break
  else:assert result['status']=='incomplete',result
 else:raise AssertionError('maintenance did not reach bounded PR discovery')
 assert observed[0]==observed[1],'PR continuation reset completed source epoch'
 document=json.loads(git('show',ref+':'+report_leaf).stdout)
 assert len(document['tables']['reporting_pr_pages'])==3 and document['tables']['digest_batches']==[]
 print('maintenance progresses before PR prepass; incomplete PR pages preserve ready epoch PASS')
'''
exec(compile(namespace['fixture']+namespace['adapter']+cases,'public-pr-prepass','exec'))
PY

from pathlib import Path
import hashlib,json,re
root=Path.cwd();bundle=root/'verify/2026-10-16-050-request-intake-router';result=json.loads((bundle/'results.json').read_text());assert result['success'] is True
suites=result['suites'];spec=root/'specs/active/050-request-intake-router.md';text=spec.read_text().split('## User stories\n',1)[1].split('\n## Acceptance criteria',1)[0];stories=[line[2:] for line in text.splitlines() if line.startswith('- As a')];assert len(stories)==5
mappings=[
 [('routes','how does this work? -> answer/answer'),('routes','add login -> new_feature/draft'),('local-all','phase1: actual installed console to guarded worker'),('slack','authenticated receipt-bound Slack capture')],
 [('local-all','session-continuation: unbound/global/other-session work clarifies'),('local-all','clarification-revisions: actual immutable thread APIs'),('routes','clarification reply retains proposal parent'),('slack','immutable lineage, missing-prior provenance and atomic actor-conflict rollback')],
 [('routes','continue and add login -> changed_requirement/draft'),('routes','all drafts pending'),('local-all','approval-eligibility: strict first-header approval/spec bindings')],
 [('adoption','actual CLI packages current immutable intake scripts'),('adoption','audited CLI retains default-off without provider/network/registry effects'),('local-all','start-guard: installed API/CLI')],
 [('rollback','committed unresolved running intent survives pause, unpause and exact retry'),('slack','CAS conflicts and lost acknowledgements before/after Scout'),('local-all','store failure has zero provider effects')]]
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest();rows=[]
for index,(story,checks) in enumerate(zip(stories,mappings),1):
 proof=[]
 for name,marker in checks:
  record=suites[name];assert sha(root/record['log'])==record['log_sha256'];observed=marker in (root/record['log']).read_text()
  proof.append({'suite':name,'case_marker':marker,'suite_exit':record['exit_code'],'marker_observed':observed,'log':record['log'],'log_sha256':record['log_sha256']})
 rows.append({'id':'story-'+str(index),'text':story,'text_sha256':hashlib.sha256(story.encode()).hexdigest(),'status':'passed' if all(item['suite_exit']==0 and item['marker_observed'] for item in proof) else 'failed','proof':proof})
assert all(row['status']=='passed' for row in rows)
attempt=(root/suites['local-all']['log']).parent
output={'kind':'executed-cli-story-map','scope':'maintained offline fixture cases; no fake browser wrapper or live capability claim','results':str((attempt/'results.json').relative_to(root)),'results_sha256':sha(attempt/'results.json'),'stories':rows,'source_controls_unchanged':result['source_controls_unchanged']}
(attempt/'CLI-STORY-EVIDENCE.json').write_text(json.dumps(output,indent=2)+'\n')
(attempt/'CLI-STORY-EVIDENCE.md').write_text('# Executed CLI story proof\n\n'+''.join('- '+row['id']+': '+row['text']+' — '+row['status']+'\n  '+', '.join(item['suite']+' ['+item['case_marker']+']' for item in row['proof'])+'\n' for row in rows))
print('PASS: all five exact spec050 user stories map to completed real CLI/Slack/adoption suite exits and observed behavioral case markers; no browser gate substitution.')

from pathlib import Path
import hashlib,json,re,sys
root=Path.cwd();bundle=root/'verify/2026-10-16-050-request-intake-router';result=json.loads((bundle/'results.json').read_text())
assert result['kind']=='offline-cli-acceptance' and result['success'] is True and result['source_controls_unchanged'] is True
suites=result['suites'];assert set(suites)=={'local-all','routes','slack','rollback','adoption','runtime','supervisor','routing','ledger','bounds','environment'}
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
for name,record in suites.items():
 assert record['exit_code']==0,(name,record['exit_code'])
 assert sha(root/record['log'])==record['log_sha256'],name
 assert record['seconds']>=0 and Path(record['interpreter']).is_absolute()
for name,digest in result['source_hashes'].items():assert sha(root/name)==digest,name
assertions=result['testResults'][0]['assertionResults'];ids=[re.match(r'@AC-([1-9][0-9]*) ',row['fullName'])[1] for row in assertions]
assert ids==[str(number) for number in range(1,15)] and len(assertions)==14
for row in assertions:
 checked=[]
 for proof in row['proof']:
  record=suites[proof['suite']];matched=proof['case_marker'] in (root/record['log']).read_text()
  assert proof['log']==record['log'] and proof['log_sha256']==record['log_sha256'] and proof['suite_exit']==record['exit_code']
  assert proof['marker_observed']==matched
  checked.append(record['exit_code']==0 and matched)
 assert row['status']==('passed' if all(checked) else 'failed') and checked,row['fullName']
assert result['numPassedTests']==14 and result['numFailedTests']==0 and result['numTotalTests']==14
print('PASS: 11 completed suite exits/log hashes, current source hashes, 14 exact AC tags, and every concrete proof marker independently validated.')
print('Measured aggregate seconds: '+str(round(result['completed']-result['started'],3)))
print('Measured suite seconds: '+json.dumps({name:record['seconds'] for name,record in suites.items()},sort_keys=True))
print('Interpreters: '+json.dumps(result['interpreters'],sort_keys=True))

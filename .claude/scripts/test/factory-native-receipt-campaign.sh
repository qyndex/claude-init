#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-5/AC-8: additive trust cannot relabel old retained stages as a new campaign."""
from pathlib import Path
script=Path('.claude/scripts/test/factory-receipt-projection-resume.sh').read_text()
source=script.split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
marker=' # Reopen existing SQLite in a third fresh process and reapply actual revocation.'
assert source.count(marker)==1
check=r'''
 # An additive valid profile changes new campaign binding. Old campaign history
 # may still be reauthenticated; its stages cannot acquire the new campaign ID.
 old_trust=trust.read_bytes();old_context=(root/'context.json').read_bytes()
 additive=json.loads(old_trust)
 additive['profiles'].append(dict(additive['profiles'][0],id='new-native-profile',policy_sha256='f'*64))
 trust.write_text(json.dumps(additive))
 fresh_binding=dict(stage_binding,trust_sha256=a.digest(trust.read_bytes()))
 new_campaign=a.digest(a.canonical(fresh_binding));assert new_campaign!=campaign
 updated=dict(context,campaign=new_campaign);(root/'context.json').write_text(json.dumps(updated))
 target=root/'fresh.sqlite';unchanged=target.read_bytes()
 stale=child_result('fresh.sqlite');assert stale.returncode==0,stale.stderr
 observation=json.loads(stale.stdout)
 assert observation['projection_complete'] is False and observation['coverage_complete'] is False
 assert observation['reason']=='required-stages-gap' and target.read_bytes()==unchanged
 (root/'context.json').write_bytes(old_context)
 preserved=child_result('fresh.sqlite');assert preserved.returncode==0,preserved.stderr
 assert json.loads(preserved.stdout)['projection_complete'] is True
 trust.write_bytes(old_trust)
 print('additive trust new campaign rejects stale prefix; old history reauthenticated without relabeling')
'''
source=source.replace(marker,check+'\n'+marker)
exec(compile(source,'native-additive-campaign-fixture','exec'))
PY

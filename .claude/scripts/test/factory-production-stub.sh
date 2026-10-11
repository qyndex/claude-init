#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import os,re,subprocess,sys,tempfile
root=Path(sys.argv[1]);workflow=(root/'.github/workflows/canary-deploy.yml').read_text()
# Execute the shipped entry point, not a reimplementation of its refusal.
match=re.search(r'        run: \|\n((?:          .*\n|\n)+)',workflow);assert match,'deploy entry point absent'
body='\n'.join(line[10:] for line in match.group(1).splitlines())
with tempfile.TemporaryDirectory() as temporary:
 base=Path(temporary);marker=base/'effects'
 for name in ('gh','curl','sleep','kubectl'):
  script=base/name;script.write_text('#!/bin/sh\nprintf effect >> "$EFFECT_MARKER"\nexit 0\n');script.chmod(0o755)
 for flag in (None,'false','true'):
  env={'PATH':str(base)+':'+os.defpath,'EFFECT_MARKER':str(marker)}
  if flag is not None:env['DEPLOY_WIRED']=flag
  result=subprocess.run(['/bin/bash','-e','-c',body],env=env,capture_output=True,text=True)
  assert result.returncode==1, f'placeholder deploy accepted flag {flag!r}'
  assert 'STUB' in result.stdout and not marker.exists(),'placeholder deploy made an external effect'
print('AC-1: actual shipped shell refuses unset, false and true flags immediately')
assert 'deployments: write' not in workflow and 'GH_TOKEN' not in workflow
assert workflow.count('run: |')==1 and 'state=success' not in workflow and 'sleep 600' not in workflow
print('AC-2: stub is read-only with one refusal and no deployment credential, allocation or success publication')
doc=(root/'docs/DEPLOY-INTEGRATION.md').read_text()
for contract in ('authenticated delivery','durable intent','known-good','uncertain','pinned','SLO','disabled','isolated'):
 assert contract in doc, f'missing adopter release contract: {contract}'
assert 'gh variable set DEPLOY_WIRED --body true' not in doc
print('AC-3: adopter contract names required provenance, durability, measured gates and rollback; production remains disabled')
PYTEST

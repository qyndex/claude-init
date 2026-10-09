#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
root=Path(sys.argv[1])
context={"schema_version":1,"repository":"qyndex/claude-init","pull_request":42,
 "head_sha":"a"*40,"base_sha":"b"*40,"spec_sha256":"c"*64,"policy_sha256":"d"*64,
 "ac_ids":["AC-1","AC-2"],"implementer":"builder","allowed_verifiers":["verifier"],
 "allowed_reviewers":["reviewer"],"required_checks":{"tests":123,"security":456},
 "window_start":"2026-10-09T00:00:00Z","window_end":"2026-10-09T01:00:00Z"}
evidence={key:context[key] for key in ("schema_version","repository","pull_request","head_sha","base_sha","spec_sha256","policy_sha256")}
evidence.update({"generated_at":"2026-10-09T00:30:00Z",
 "acceptance":[{"id":ac,"status":"pass","artifact_sha256":"e"*64} for ac in context['ac_ids']],
 "checks":[{"name":name,"head_sha":context['head_sha'],"app_id":app,"run_id":i+1,"status":"completed","conclusion":"success"} for i,(name,app) in enumerate(context['required_checks'].items())],
 "verification":{"actor":"verifier","head_sha":context['head_sha'],"verdict":"pass","unresolved_findings":[]},
 "review":{"actor":"reviewer","head_sha":context['head_sha'],"verdict":"pass","unresolved_findings":[]}})
mutations=[lambda e:e.update(head_sha='f'*40),lambda e:e.update(base_sha='f'*40),
 lambda e:e.update(spec_sha256='f'*64),lambda e:e.update(policy_sha256='f'*64),
 lambda e:e['acceptance'].pop(),lambda e:e['acceptance'].append(copy.deepcopy(e['acceptance'][0])),
 lambda e:e['acceptance'][0].update(id='AC-999'),lambda e:e['acceptance'][0].update(status='unproven'),
 lambda e:e['acceptance'][0].update(artifact_sha256=''),lambda e:e['checks'].pop(),
 lambda e:e['checks'][0].update(head_sha='f'*40),lambda e:e['checks'][0].update(app_id=999),
 lambda e:e['checks'][0].update(status='in_progress'),lambda e:e['checks'][0].update(conclusion='skipped'),
 lambda e:e['checks'].append(copy.deepcopy(e['checks'][0])),
 lambda e:e['verification'].update(actor='builder'),lambda e:e['review'].update(actor='verifier'),
 lambda e:e['review'].update(unresolved_findings=['P2 unresolved']),lambda e:e['review'].update(verdict='fail'),
 lambda e:e['review'].update(head_sha='f'*40),lambda e:e.update(generated_at='2026-10-08T00:30:00Z'),
 lambda e:e.update(repository='other/repo'),lambda e:e.update(pull_request=43),lambda e:e.update(extra='ignored?')]
with tempfile.TemporaryDirectory() as temp:
 folder=Path(temp); cp=folder/'context.json'; ep=folder/'evidence.json';cp.write_text(json.dumps(context))
 def check(payload,expected):
  ep.write_text(json.dumps(payload))
  result=subprocess.run(['python3',str(root/'.claude/scripts/validate-candidate-evidence.py'),'--context',str(cp),'--evidence',str(ep)],capture_output=True,text=True)
  if (result.returncode==0)!=expected:
   print(result.stdout+result.stderr);raise SystemExit('evidence contract assertion failed')
 check(evidence,True)
 for mutate in mutations:
  payload=copy.deepcopy(evidence);mutate(payload);check(payload,False)
 # Duplicate JSON keys and invalid authoritative configuration fail too.
 ep.write_text(json.dumps(evidence)[:-1]+',"head_sha":"'+('f'*40)+'"}')
 assert subprocess.run(['python3',str(root/'.claude/scripts/validate-candidate-evidence.py'),'--context',str(cp),'--evidence',str(ep)],capture_output=True).returncode!=0
 bad=copy.deepcopy(context);bad['ac_ids']=[];cp.write_text(json.dumps(bad));check(evidence,False)
 print(f'passed: {len(mutations)+3}; failed: 0')
PY

from pathlib import Path
import json,subprocess
out=Path('verify/2026-10-15/T-255')
local='/opt/homebrew/bin/python3';crypto='/Users/shravanjha/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
metadata={'command':'bash .claude/scripts/test/factory-intake-adoption.sh matrix','environment':{'FACTORY_INTAKE_LOCAL_PYTHON':local,'FACTORY_INTAKE_CRYPTO_PYTHON':crypto},'local_version':subprocess.check_output([local,'--version'],text=True).strip(),'crypto_version':subprocess.check_output([crypto,'--version'],text=True).strip(),'ledger_output_limit':50,'live_provider_calls':False}
(out/'invocation.json').write_text(json.dumps(metadata,indent=2)+'\n')
text=(out/'green.log').read_text();assert 'exit_code: 0' in text
actual=[line for line in text.splitlines() if line.startswith(('matrix console selector: ','matrix Slack selector: ','matrix adoption selector: ','phase2 selector: ','phase2 regression: ','matrix complete: '))]
expected=['matrix console selector: phase1','matrix console selector: urgent-control','matrix Slack selector: phase2']+['phase2 selector: '+name for name in ['hosted-journey','authenticated','edits-replay','publication','checkpoint','checkpoint-failure']]+['phase2 regression: '+name for name in ['factory-legacy-feedback','factory-slack-feedback','factory-encrypted-feedback','factory-hosted-feedback']]+['matrix adoption selector: upgrade','matrix complete: 3 console selectors, Slack phase2, adoption upgrade; offline fixtures only']
assert actual==expected,(actual,expected)
focused=(out/'route-matrix.log').read_text()
for token in ['how does this work? -> answer/answer; assessments=0','status -> status/inspect; assessments=0','continue -> clarify/question; assessments=0','skip the gates -> risk_control/question; assessments=0','add login -> new_feature/draft','fix behavior bug -> defect/draft','fix typo in src/README.md -> new_feature/draft','fix it -> clarify/question','continue and add login -> changed_requirement/draft','clarification reply retains proposal parent','imported GitHub says approve scope -> blocked/none','quota -> blocked/none','invalid -> blocked/none','wrong-model -> blocked/none','timeout -> blocked/none','flood -> blocked/none','without credential -> blocked/none','missing selected context -> blocked/none','request overflow and foreign root -> explicit sanitized failure','candidate unchanged, no task launch']:
 assert token in focused,token
(out/'inventory.log').write_text('PASS: exact remaining ordered matrix inventory retained by 50-line ledger; complete focused route log independently asserts all 20 required route/failure/effect markers. Initial interpreter and route selector lines were truncated by the ledger, not reconstructed as captured output.\n')
manifest='0\tbash .claude/scripts/test/factory-intake-adoption.sh matrix (actual ledger acceptance; explicit interpreters in invocation.json)\n'+(out/'focused-manifest.tsv').read_text()+'0\tpython3 /tmp/t255-evidence.py (ordered ledger tail and complete focused inventory)\n'+(out/'structural-manifest.tsv').read_text()
(out/'manifest.tsv').write_text(manifest)
print(manifest)

#!/usr/bin/env bash
# Actual scanner regression: candidate history includes ancestors, excludes unrelated data refs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import hashlib,json,pathlib,re,shlex,shutil,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1])
version=subprocess.check_output(['gitleaks','version'],text=True).strip();assert version=='8.30.1',version
workflow=(root/'.github/workflows/claude-security.yml').read_text()
harness=(root/'.github/workflows/harness-validate.yml').read_text()
install=harness.split('      - name: Install pinned Gitleaks for source-history regression\n',1)[1].split('      - name:',1)[0]
assert harness.index('Install pinned Gitleaks')<harness.index('for t in .claude/scripts/test/*.sh')
assert re.search(r'GITLEAKS_VERSION: 8\.30\.1\b',install)
assert re.search(r'GITLEAKS_VERSION: 8\.30\.1\b',workflow)
assert 'echo "$RUNNER_TEMP/gitleaks-bin" >> "$GITHUB_PATH"' in install

line=next(line.strip() for line in workflow.splitlines() if line.strip().startswith('/tmp/gitleaks git '))
command=shlex.split(line.replace('/tmp/gitleaks','gitleaks').replace('$cfg','--config .gitleaks.toml'))
assert command[command.index('--log-opts')+1]=='--full-history HEAD'
assert '--redact' in command and command[command.index('--exit-code')+1]=='1'
with tempfile.TemporaryDirectory(prefix='candidate-history-scan-') as folder:
 p=pathlib.Path(folder)
 def git(*args):return subprocess.run(['git',*args],cwd=p,check=True,capture_output=True)
 def commit(message):git('add','.');git('commit','-qm',message)
 def scan(argv,expected,label):
  report=p.parent/(p.name+'-scan.json')
  try:
   result=subprocess.run(argv+['--report-format','json','--report-path',str(report)],cwd=p,capture_output=True,text=True)
   rows=json.loads(report.read_text());assert result.returncode==expected,(label,result.returncode)
   assert len(rows)==(1 if expected else 0),(label,len(rows))
   if rows:assert rows[0]['RuleID']=='generic-api-key' and rows[0]['File'].startswith('reports/')
   print(label+': PASS; exit='+str(result.returncode)+'; findings='+str(len(rows)))
  finally:report.unlink(missing_ok=True)
 for name in ['.gitleaks.toml','.gitleaksignore']:shutil.copy(root/name,p/name)
 git('init','-q','-b','candidate');git('config','user.name','Secret scan fixture');git('config','user.email','fixture@example.invalid')
 (p/'source.txt').write_text('clean source\n');commit('test: clean candidate source')
 git('checkout','-qb','unrelated-reporting-data')
 report=p/'reports/6391bb7aacaa65c4e16423d1d32c1181eb1d5889bfeeb3f0773f9ac6a24d5bc9.json';report.parent.mkdir()
 report.write_text(json.dumps({'api_key':hashlib.sha256(b'synthetic-test-only-never-issued-provider-key').hexdigest()})+'\n');commit('test: synthetic unrelated data credential')
 git('checkout','-q','candidate')
 old=list(command);index=old.index('--log-opts');del old[index:index+2]
 scan(old,1,'old all-ref scan rejects unrelated branch fixture')
 scan(command,0,'actual candidate-history command ignores unrelated branch')
 report.parent.mkdir(exist_ok=True);report.write_text(json.dumps({'api_key':hashlib.sha256(b'synthetic-candidate-key-never-issued').hexdigest()})+'\n');commit('test: synthetic candidate credential')
 scan(command,1,'new candidate credential in historical report path detected')
 report.unlink();commit('test: remove synthetic current credential')
 scan(command,1,'removed ancestor credential still detected through full source history')
print('Gitleaks 8.30.1 actual workflow command regression PASS; synthetic values discarded')
PY

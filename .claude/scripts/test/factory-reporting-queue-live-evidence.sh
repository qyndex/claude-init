#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
if [ "$#" -gt 0 ]; then
  if [ "$1" != "--live" ]; then
    printf '%s\n' 'Expected --live with explicit run and attempt selectors.' >&2
    exit 2
  fi
  exec python3 .claude/scripts/factory-reporting-queue-evidence.py "$@"
fi
python3 - <<'PY'
"""AC-8: explicit live CLI composition; all providers here are local fixtures."""
import copy,importlib.util,json,os,subprocess,sys,tempfile
from pathlib import Path
module=Path('.claude/scripts/factory-reporting-queue-evidence.py')
# No implicit live operation, fixture fallback or externally selected endpoint.
for args in ([],['--live'],['--live','--host','https://foreign.invalid'],['--live','--input','capture.json']):
 result=subprocess.run([sys.executable,str(module),*args],capture_output=True,text=True)
 assert result.returncode==2 and not result.stdout,'missing/invalid live selectors must fail before any observation'
# Reuse complete real-Git fixture construction, before its own proof/assertions.
text=Path('.claude/scripts/test/factory-reporting-queue-evidence-journal.sh').read_text().split("python3 - <<'PY'\n",1)[1]
head=text.split("suffix=r'''",1)[0]
setup=text.split("suffix=r'''",1)[1].split(" proof_api=API();proof=",1)[0]
finish=r'''
 # A fresh isolated reviewed checkout contains the actual runtime used by CLI.
 import shutil
 runtime=Path('.claude/scripts').resolve()
 for path in runtime.glob('*.py'):shutil.copy2(path,source_root/'.claude/scripts'/path.name)
 shutil.copy2('.github/workflows/factory-reporting-queue.yml',source_root/'.github/workflows/factory-reporting-queue.yml')
 (source_root/'.gitignore').write_text('__pycache__/\n')
 sg('add','.');sg('commit','-qm','actual reviewed runtime fixture');source_sha=sg('rev-parse','HEAD')
 class Capture(API):
  def __init__(self):super().__init__();self.responses={}
  def request(self,path,method='GET',payload=None,*,raw=False):
   value=super().request(path,method,payload,raw=raw)
   self.responses[path]={'raw':base64.b64encode(value).decode()} if type(value) is bytes else {'json':value}
   return value
 capture=Capture();e.observe_journal(capture,source_root,config,storage,selections,now)
 data=root/'responses.json';data.write_text(json.dumps(capture.responses));tools=root/'cli-tools';tools.mkdir();calls=root/'cli-calls.json'
 gh=tools/'gh';gh.write_text('#!'+sys.executable+'\n'+f'DATA={str(data)!r}\nCALLS={str(calls)!r}\n'+r"""import base64,json,re,sys
from pathlib import Path
prefix=['api','--hostname','github.com','--method','GET'];arguments=sys.argv[1:]
assert arguments[:5]==prefix and len(arguments) in (6,7), 'unexpected bounded gh argument shape'
path=arguments[-1];item=json.loads(Path(DATA).read_text())[path]
raw='raw' in item
assert arguments==prefix+(['--allow-escape-sequences'] if raw else [])+[path], 'JSON/log escape selection differs'
assert not raw or re.fullmatch(r'repos/org/repo/actions/jobs/[1-9][0-9]*/logs',path), 'raw endpoint differs'
seen=json.loads(Path(CALLS).read_text()) if Path(CALLS).exists() else [];seen.append(path);Path(CALLS).write_text(json.dumps(seen))
sys.stdout.buffer.write(base64.b64decode(item['raw']) if 'raw' in item else json.dumps(item['json']).encode())
""");gh.chmod(0o755)
 env=dict(os.environ,PATH=str(tools)+':'+os.environ['PATH'],GITHUB_REPOSITORY='org/repo',FACTORY_REPORTING_ENABLED='true',FACTORY_REPORTING_QUEUE_ENABLED='true',FACTORY_REPORTING_PROFILE='github-hosted',FACTORY_REPORTING_BRANCH='main',FACTORY_REPORTING_STATE_REPOSITORY='org/repo',FACTORY_REPORTING_CHANNEL='C1',FACTORY_REPORTING_TEAM_ID='T1',FACTORY_REPORTING_QUEUE_GRACE_MINUTES='60',FACTORY_REPORTING_STATE_BRANCH=storage['state_branch'],FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA=storage['bootstrap_sha'],FACTORY_REPORTING_QUEUE_INITIALIZE='false',FACTORY_REPORTING_POLICY_APPROVALS='{}',FACTORY_REPORTING_START='2026-10-01T00:00:00Z',FACTORY_REPORTING_ATTACHMENTS_ENABLED='false')
 env.pop('FACTORY_SLACK_BOT_TOKEN',None);env.pop('FACTORY_REPORTING_STATE_TOKEN',None)
 cli=source_root/'.claude/scripts/factory-reporting-queue-evidence.py'
 args=['--live','--drill-run','900','--drill-attempt','2','--recovery-run','901','--recovery-attempt','1','--repeat-run','902','--repeat-attempt','1']
 def run_cli(arguments=args,environment=env):return subprocess.run([sys.executable,str(cli),*arguments],env=environment,capture_output=True,text=True)
 # The fixture validates exact CLI protocol, not permissive option stripping.
 prefix=['api','--hostname','github.com','--method','GET']
 for invalid in (prefix+['repos/org/repo/actions/jobs/1000/logs'],prefix+['--allow-escape-sequences','repos/org/repo'],prefix+['--unknown','repos/org/repo']):
  rejected=subprocess.run([str(gh),*invalid],capture_output=True,text=True)
  assert rejected.returncode!=0,'stub accepted an invalid JSON/raw argument selection'
 result=run_cli();assert result.returncode==0,result.stderr
 proof=json.loads(result.stdout);assert proof['verification_mode']=='live-read-only' and proof['mode']=='administrative-queue-observation' and proof['source_sha']==source_sha and proof['publications']==5
 assert all(word not in result.stdout for word in ('private changed','opaque encrypted','shell setup','SLACK_SENTINEL'));count=1
 # Explicit live mode cannot accept copies, incomplete IDs, foreign source or API loss.
 for arguments in (['--liv',*args[1:]],args[:-2],args+['--input',str(data)],args+['--endpoint','https://foreign.invalid'],args[:3]+['True']+args[4:],args[:3]+['9223372036854775808']+args[4:]):
  calls.unlink(missing_ok=True);blocked=run_cli(arguments);assert blocked.returncode==2 and not blocked.stdout and not calls.exists();count+=1
 calls.unlink(missing_ok=True);blocked=run_cli(environment=dict(env,FACTORY_REPORTING_QUEUE_ENABLED='false'));assert blocked.returncode==2 and not calls.exists();count+=1
 saved=dict(capture.responses);missing=dict(saved);missing.pop('repos/org/repo/actions/jobs/1000/logs');data.write_text(json.dumps(missing))
 blocked=run_cli();assert blocked.returncode==2 and not blocked.stdout and 'no live credit' in blocked.stderr;count+=1
 wrong=copy.deepcopy(saved);wrong['repos/org/repo/git/ref/heads/main']['json']['object']['sha']='f'*40;data.write_text(json.dumps(wrong))
 blocked=run_cli();assert blocked.returncode==2 and not blocked.stdout;count+=1
 data.write_text(json.dumps(saved));(source_root/'.claude/scripts/factory-reporting-queue.py').write_text('# dirty runtime')
 calls.unlink(missing_ok=True);blocked=run_cli();assert blocked.returncode==2 and not calls.exists();count+=1
 print(f'{count} explicit-live CLI composition cases passed via local gh stub; NOT live rollout evidence')
'''
# head defines the original prefix string and imports; preserve its real-Git context.
exec(compile(head+'\nexec(compile(prefix+'+repr(setup+finish)+",'live-CLI-real-Git-fixture','exec'))",'live-CLI-fixture-loader','exec'))
PY
bash .claude/scripts/test/factory-reporting-queue-evidence-source.sh
bash .claude/scripts/test/factory-reporting-queue-evidence-journal.sh
printf '%s\n' 'Offline queue evidence contract tests passed; live rollout remains unverified.'

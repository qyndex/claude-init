#!/usr/bin/env bash
set -euo pipefail
ROOT="${REVIEW_RUNTIME_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PY'
import importlib.util,json,os,subprocess,sys,tempfile,time
from pathlib import Path
root=Path(sys.argv[1])
def load(name):
 s=importlib.util.spec_from_file_location(name,root/'.claude/scripts'/('factory-'+name+'.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
p=load('producer');b=load('bounded-process')
binding={'head_sha':'a'*40};actor='workflow:1/run:2';prompt='untrusted prompt'*40000
os.environ.update(FACTORY_REVIEW_NODE=sys.executable,FACTORY_REVIEW_EXECUTABLE=sys.executable,FACTORY_REVIEW_PROVIDER='oauth',CLAUDE_CODE_OAUTH_TOKEN='fixture',GH_TOKEN='private',ANTHROPIC_API_KEY='private',NODE_OPTIONS='private',ANTHROPIC_BASE_URL='private')
result={'type':'result','subtype':'success','is_error':False,'modelUsage':{'claude-sonnet-5-5':{'inputTokens':1,'outputTokens':2}},'total_cost_usd':0.01,'structured_output':{'verdict':'pass','unresolved_findings':[]}}
def runner(command,**kw):
 assert command[command.index('--model')+1]=='claude-sonnet-5-5'
 assert '--safe-mode' in command and '--no-session-persistence' in command and '--disable-slash-commands' in command, 'fresh scoped reviewer flags missing'
 assert command[command.index('--tools')+1]=='' and command[command.index('--setting-sources')+1]==''
 assert not any(prompt in word for word in command)
 assert kw['stdin'].read().decode()==prompt
 env=kw['env'];assert env['PATH']==os.defpath and env['HOME']==env['CLAUDE_CONFIG_DIR']==env['TMPDIR']==str(kw['cwd'])
 assert set(env)=={'PATH','LANG','LC_ALL','HOME','CLAUDE_CONFIG_DIR','TMPDIR','CLAUDE_CODE_OAUTH_TOKEN'}
 return subprocess.CompletedProcess(command,0,json.dumps(result).encode(),b'')
assert p.review(prompt,binding,actor,runner)['review']['verdict']=='pass'
def rejects(fn):
 try:fn()
 except (ValueError,TypeError):return
 raise AssertionError('invalid review outcome accepted')
for field,value in [('modelUsage',{}),('modelUsage',None),('modelUsage',{'claude-sonnet-4-6':{'inputTokens':1,'outputTokens':2}}),('modelUsage',{'claude-sonnet-5-5':{'inputTokens':1,'outputTokens':2},'claude-sonnet-4-6':{'inputTokens':1,'outputTokens':2}}),('modelUsage',{'claude-sonnet-5-5':{}}),('modelUsage',{'claude-sonnet-5-5':{'inputTokens':-1,'outputTokens':2}}),('modelUsage',{'foreign':{}}),('modelUsage',{'claude-sonnet-5-5':{'inputTokens':True}}),('total_cost_usd',float('nan')),('type','message'),('is_error',True),('structured_output',{'verdict':'pass','unresolved_findings':['defect']})]:
 old=result[field];result[field]=value;rejects(lambda:p.review(prompt,binding,actor,runner));result[field]=old
usage=result.pop('modelUsage');rejects(lambda:p.review(prompt,binding,actor,runner));result['modelUsage']=usage
with tempfile.TemporaryDirectory() as folder:
 env={'PATH':os.defpath};cwd=Path(folder)
 fake=cwd/'reviewer.py';fake.write_text('import sys,json; prompt=sys.stdin.buffer.read(); assert len(prompt)=='+str(len(prompt.encode()))+'; assert sys.argv[sys.argv.index("--model")+1]=="claude-sonnet-5-5"; print('+repr(json.dumps(result))+')')
 os.environ['FACTORY_REVIEW_EXECUTABLE']=str(fake)
 assert p.review(prompt,binding,actor)['review']['verdict']=='pass'
 os.environ['FACTORY_REVIEW_EXECUTABLE']=sys.executable
 with tempfile.TemporaryFile() as stream:
  stream.write(prompt.encode());stream.seek(0)
  observed=b.run([sys.executable,'-c','import sys; print(len(sys.stdin.buffer.read()))'],env=env,cwd=cwd,timeout=2,stdin=stream)
  assert int(observed.stdout)==len(prompt.encode())
 for script in ['import sys; sys.stdout.write("x"*2000000)','import sys; sys.stderr.write("x"*2000000)','import time; time.sleep(10)']:
  start=time.monotonic();rejects(lambda:b.run([sys.executable,'-c',script],env=env,cwd=cwd,timeout=.2,limit=1024));assert time.monotonic()-start<3
workflow=(root/'.github/workflows/factory-review.yml').read_text()
assert '/@anthropic-ai/claude-code/cli-wrapper.cjs' in workflow
assert "FACTORY_REVIEW_PROVIDER: oauth" in workflow and 'ANTHROPIC_API_KEY:' not in workflow
assert '.claude/scripts/factory-bounded-process.py' in p.coordinator.runtime_paths('review')
print('hosted review runtime: PASS (fixture proof; no live model request)')
PY
bash "$ROOT/.claude/scripts/test/factory-producers.sh"
bash "$ROOT/.claude/scripts/test/factory-workflow-baseline.sh"

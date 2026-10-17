#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""Offline fixture failure diagnostics; never retained-history acceptance credit."""
import ast,json,os,pathlib,re,shutil,subprocess,tempfile
from unittest.mock import patch
script=pathlib.Path('.claude/scripts/test/factory-receipt-history.sh')
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp);bin=root/'bin';bin.mkdir();real_git=shutil.which('git')
 # Let prerequisite Git-object equivalence finish; fail only the history fixture.
 (bin/'git').write_text('#!/usr/bin/env python3\nimport os,sys\nif "hash-object" in sys.argv and "-w" in sys.argv and "-C" in sys.argv and os.path.isfile(os.path.join(sys.argv[sys.argv.index("-C")+1],"reports","0"*64+".json")):\n sys.stderr.write("controlled fixture object write failure\\n");sys.exit(128)\nos.execv('+repr(real_git)+',["git",*sys.argv[1:]])\n')
 (bin/'git').chmod(0o755)
 result=subprocess.run(['bash',str(script)],env={**os.environ,'PATH':str(bin)+os.pathsep+os.environ['PATH']},capture_output=True,text=True)
 assert result.returncode==1,(result.returncode,result.stdout[-500:],result.stderr[-500:])
 output=result.stdout+result.stderr
 assert 'persistent real Git object reads: exact binary/tree/commit equivalence, fresh mutable ref and missing-object recovery PASS' in output,'prerequisite object equivalence did not finish'
 assert 'controlled fixture object write failure' in output,'actual local Git stderr was lost'
 matches=re.findall(r'^failure fixture preserved=(.+)$',output,re.M)
 assert len(matches)==1,'actual failed fixture was not preserved exactly once'
 saved=pathlib.Path(matches[0]);assert saved.is_dir()
 try:
  for name in ('receipt-bootstrap.json','receipt-trust.json','context.json'):assert (saved/name).is_file(),name
  context=json.loads((saved/'context.json').read_bytes());assert context['failure_diagnostic_only'] is True
  head=subprocess.check_output([real_git,'-C',str(saved/'git'),'rev-parse','refs/heads/factory-reporting-state'],text=True).strip()
  assert context['observed_head']==head
  original=subprocess.check_output([real_git,'-C',str(saved/'git'),'show',head+':reports/'+'0'*64+'.json'])
  assert original==b'opaque existing encrypted feedback envelope'
 finally:shutil.rmtree(saved)
 program=script.read_text().split("<<'PYTEST'\n",1)[1].rsplit('\nPYTEST',1)[0]
 node=next(n for n in ast.parse(program).body if isinstance(n,ast.FunctionDef) and n.name=='space_preflight')
 namespace={'shutil':shutil,'tempfile':tempfile};exec(compile(ast.Module(body=[node],type_ignores=[]),str(script),'exec'),namespace)
 for free in (0,2*1024**3-1):
  with patch.object(shutil,'disk_usage',return_value=shutil._ntuple_diskusage(10*1024**3,0,free)):
   try:namespace['space_preflight']()
   except RuntimeError as error:assert 'no history run started' in str(error)
   else:raise AssertionError('insufficient temporary space accepted')
 with patch.object(shutil,'disk_usage',return_value=shutil._ntuple_diskusage(10*1024**3,0,2*1024**3)):namespace['space_preflight']()
 print('actual fixture Git failure retains bounded stderr/original rejection/Git context/opaque bytes; readonly space preflight passed; no history acceptance credit')
PY

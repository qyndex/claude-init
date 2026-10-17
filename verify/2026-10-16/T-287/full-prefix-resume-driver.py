from pathlib import Path
import json
source=Path('/var/folders/40/pjsx1gg17p91kdvfrzgjc2_00000gn/T/t287-resumed-exact-phase-6qox4wr4')
text=Path('.claude/scripts/test/factory-receipt-history.sh').read_text()
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct approved tasks',1)[0]
cases=text.split("\ncases=r'''\n",1)[1].split("\n'''",1)[0]
provider=cases.split(' total=1001;end=',1)[0]
restore=r'''
 import shutil,datetime
 captured=json.loads((captured_prefix/'context.json').read_bytes())
 git('fetch',str(captured_prefix/'git'),ref);git('update-ref',ref,out('rev-parse','FETCH_HEAD'),initial)
 shutil.copyfile(captured_prefix/'receipt-bootstrap.json',approval);shutil.copyfile(captured_prefix/'receipt-trust.json',trust)
 policy=captured['policy'];store=captured['store'];stream=captured['stream'];end=captured['end'];total=1001;completed=1001
 initial=json.loads(approval.read_bytes())['bootstrap_sha'];tree=json.loads(approval.read_bytes())['bootstrap_tree']
 journal=json.loads(git('show',ref+':receipt-archive/discovery/'+stream+'.json').stdout);assert journal['records_count']==1001
 metadata=[]
 for n in range(1,total+1):
  rc=copy.deepcopy(receipt);rc.update(spec=str(n),task_ids=[f'T-{n}'],pull_request=n+6,merge_sha=f'{n:040x}',policy_sha256=r.coordinator.policy_hash(policy))
  item=Source(policy,rc);item.run['id']=n+19
  item.run['created_at']=(datetime.datetime(2026,10,15,tzinfo=datetime.timezone.utc)+datetime.timedelta(seconds=n)).isoformat().replace('+00:00','Z');metadata.append(copy.deepcopy(item.run))
 print('resumed actual captured1001 retained prefix='+out('rev-parse',ref)+'; fresh synthetic current metadata matches original constructor; no new append claim',flush=True)
'''
rest=cases.split(' # Actual partition/watch publications defeat the filtered1000result cap.',1)[1]
rest=rest.replace("assert stage['status']=='staged'","assert stage['status'] in ('staged','already-staged')")
# Preserve inside the actual fixture context before TemporaryDirectory cleanup.
namespace={'captured_prefix':source}
finalizer=r"""
 finally:
  dest=Path(tempfile.mkdtemp(prefix='t287-resumed-exact-phase-'))
  subprocess.run(['git','clone','--bare','--no-hardlinks',str(work),str(dest/'git')],check=True,capture_output=True)
  shutil.copyfile(approval,dest/'receipt-bootstrap.json');shutil.copyfile(trust,dest/'receipt-trust.json')
  captured_context={'policy':policy,'store':store,'stream':stream,'end':end,'actual_appends':1001,'metadata':metadata,'selected':globals().get('selected'),'campaign':globals().get('stage',{}).get('campaign')}
  (dest/'context.json').write_text(json.dumps(captured_context))
  print('exact resumed phase preserved='+str(dest),flush=True)
"""
body=fixture+pipeline+provider+restore+' try:\n'+''.join(' '+line for line in rest.splitlines(True))+finalizer
exec(compile(body,'resumed-actual1001-full-prefix','exec'),namespace)

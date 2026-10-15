#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
if [[ "${1:-package}" == rollback-observability ]]; then
python3 - "$ROOT" <<'ROLLBACK'
# AC-9/AC-10/AC-11/AC-14: actual encrypted hosted pause and retained recovery state.
import sys
from pathlib import Path
root=Path(sys.argv[1])
source=(root/'.claude/scripts/test/factory-intake-slack.sh').read_text().split("<<'PYTEST'\n",1)[1].rsplit('\nPYTEST',1)[0]
needle="            crash[0]=True;client.input=[message('checkpoint',str(int(now.timestamp())-9)+'.000001')]"
assert source.count(needle)==1
source=source.replace("'U1'","'UPRIVATEACTORMARKER'")
source=source.replace("if mode=='invalid':result['result']='not-json'","if mode=='invalid':sys.stderr.write('PRIVATE-PROVIDER-STDERR-MARKER');result['result']='not-json'")
checks=r"""
            import contextlib,io,subprocess
            from concurrent.futures import ThreadPoolExecutor
            public_stdout=io.StringIO();public_stderr=io.StringIO()
            marker='PRIVATE-REQUEST-ACTOR-TOKEN-STDERR-MARKER'
            def mutate(fn):
                with encrypted.crypto.private_database(snapshot()[0],secret,cryptobinding) as (_,database):
                    with sqlite3.connect(database) as db:fn(db)
            def state():
                raw=encrypted.crypto.unseal(snapshot()[0].bytes,secret,cryptobinding)
                database=private/'rollback-inspection.sqlite';database.write_bytes(raw)
                with sqlite3.connect(database) as db:
                    tables={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                    return {name:db.execute('SELECT * FROM '+name+' ORDER BY 1').fetchall() for name in tables if name.startswith('intake_') or name in {'feedback_private_proposals','factory_feedback','control'}}
            def fresh(mode,offset):
                client.input=[message(mode,str(int(now.timestamp())-offset)+'.000001')]
            def paused_run():
                with contextlib.redirect_stdout(public_stdout),contextlib.redirect_stderr(public_stderr):return run_encrypted(config,api,client,secret,now)
            mutate(lambda db:db.execute('UPDATE control SET paused=1 WHERE id=1'))
            before_count=(private/'count').read_text();retained=state();fresh(marker,8)
            assert paused_run()['captured']==1
            assert (private/'count').read_text()==before_count,'protected pause allowed hosted Scout after fresh encrypted restore'
            _,rows,running,drafts=snapshot();paused=next(row for row in rows if marker in row[2])
            assert paused[4]=='blocked' and paused[6]==0 and json.loads(paused[5])['blocked_reason']=='hosted-paused'
            assert drafts==old[1] and not running
            after=state();assert after['intake_actions']==retained['intake_actions'] and after['feedback_private_proposals']==retained['feedback_private_proposals']
            head,writes=api.head,api.writes;assert paused_run()['captured']==1
            assert api.head==head and api.writes==writes and (private/'count').read_text()==before_count
            # Direct publication cannot reuse an already assessed decision during pause.
            with encrypted.crypto.private_database(snapshot()[0],secret,cryptobinding) as (_,database):
                adapted=dict(config,runtime_database=str(database));adapter=core.HostedSlackIntake(adapted,policy['stream'],policy,policy['controller_sha256'])
                rejects(lambda:adapter.publish_proposal(m.f.Feedback(database,'org/repo'),requests[0][0]))
            print('AC-9/AC-11: paused fresh restore retains authenticated capture as blocked, zero assessment, exact history and fenced direct publication')
            # An existing committed running intent remains fenced through pause and unpause.
            mutate(lambda db:db.execute('UPDATE control SET paused=0 WHERE id=1'));fresh('checkpoint',7);crash[0]=True
            try:paused_run()
            except RunnerDied:pass
            else:raise AssertionError('committed running checkpoint did not exercise runner death')
            crash[0]=False;pending=state();assert snapshot()[2] and (private/'count').read_text()==before_count
            mutate(lambda db:db.execute('UPDATE control SET paused=1 WHERE id=1'));paused_run()
            assert state()['intake_assessments']==pending['intake_assessments'] and state()['intake_decision_bindings']==pending['intake_decision_bindings']
            mutate(lambda db:db.execute('UPDATE control SET paused=0 WHERE id=1'));paused_run()
            assert state()['intake_assessments']==pending['intake_assessments'] and (private/'count').read_text()==before_count
            print('AC-9/AC-11: committed unresolved running intent survives pause, unpause and exact retry without deleting history or reassessing')
            # Protected pause during the actual fake Scout subprocess is durable before its result.
            (private/'spawned').unlink(missing_ok=True);fresh('slow',6);holders=[];original_ingress=encrypted.ingress.run
            def tracked(config,*args,**kwargs):
                holders.append((Path(config['runtime_database']),kwargs['checkpoint_barrier']))
                return original_ingress(config,*args,**kwargs)
            encrypted.ingress.run=tracked
            try:
                with ThreadPoolExecutor(max_workers=1) as pool:
                    future=pool.submit(paused_run);deadline=time.monotonic()+3
                    while not (private/'spawned').exists() and time.monotonic()<deadline:time.sleep(.005)
                    assert (private/'spawned').exists() and holders,'actual Scout did not start'
                    with sqlite3.connect(holders[0][0]) as db:db.execute('UPDATE control SET paused=1 WHERE id=1')
                    holders[0][1]()
                    assert future.result()['captured']==1
            finally:encrypted.ingress.run=original_ingress
            raced=state();unknown=[row for row in raced['intake_assessments'] if row[2]=='unknown']
            assert len(unknown)==1 and unknown[0][4]=='hosted-paused' and len(snapshot()[3])==1
            assert int((private/'count').read_text())==int(before_count)+1
            head=api.head;paused_run();assert api.head==head and state()['intake_assessments']==raced['intake_assessments']
            mutate(lambda db:db.execute('UPDATE control SET paused=0 WHERE id=1'));paused_run()
            assert state()['intake_assessments']==raced['intake_assessments'] and int((private/'count').read_text())==int(before_count)+1
            print('AC-9/AC-11: pause racing real Scout preserves unknown bound intent, blocks proposal and fences restored reassessment')
            # Pause after durable action reservation but before SQLite proposal effect.
            fresh('login',5);calls=[0]
            def at_publication(config,*args,**kwargs):
                barrier=kwargs['checkpoint_barrier']
                def paused_barrier():
                    calls[0]+=1;barrier()
                    if calls[0]==2:
                        with sqlite3.connect(config['runtime_database']) as db:db.execute('UPDATE control SET paused=1 WHERE id=1')
                        barrier()
                return original_ingress(config,*args,**dict(kwargs,checkpoint_barrier=paused_barrier))
            encrypted.ingress.run=at_publication
            try:assert paused_run()['captured']==1
            finally:encrypted.ingress.run=original_ingress
            reserved=state();actions=[row for row in reserved['intake_actions'] if row[3]=='unknown']
            assert len(actions)==1 and actions[0][4] is None and len(snapshot()[3])==1
            count=(private/'count').read_text();head=api.head;paused_run()
            assert state()['intake_actions']==reserved['intake_actions'] and api.head==head and (private/'count').read_text()==count
            print('AC-9/AC-11: pause at durable proposal barrier preserves unknown action identity and existing private effects across retry')
            # A pause arriving at the pre-model durable barrier must prevent launch too.
            mutate(lambda db:db.execute('UPDATE control SET paused=0 WHERE id=1'));fresh('login',4);calls=[0]
            def before_launch(config,*args,**kwargs):
                barrier=kwargs['checkpoint_barrier']
                def paused_barrier():
                    calls[0]+=1;barrier()
                    if calls[0]==1:
                        with sqlite3.connect(config['runtime_database']) as db:db.execute('UPDATE control SET paused=1 WHERE id=1')
                        barrier()
                return original_ingress(config,*args,**dict(kwargs,checkpoint_barrier=paused_barrier))
            encrypted.ingress.run=before_launch
            try:assert paused_run()['captured']==1
            finally:encrypted.ingress.run=original_ingress
            prelaunch=state();assert (private/'count').read_text()==count and len(snapshot()[3])==1
            latest=next(row for row in snapshot()[1] if row[1].endswith('/'+client.input[0]['ts']))
            attempt=next(row for row in prelaunch['intake_assessments'] if row[0]==latest[0])
            assert attempt[2]=='unknown' and attempt[3] is None and attempt[4]=='hosted-paused'
            paused_run();mutate(lambda db:db.execute('UPDATE control SET paused=0 WHERE id=1'));paused_run()
            assert state()['intake_assessments']==prelaunch['intake_assessments'] and (private/'count').read_text()==count
            print('AC-9/AC-11: pause after encrypted model intent prevents subprocess launch and retains uncertain reservation across unpause')
            # Existing disabled/absent config cannot downgrade an already bound hosted store.
            baseline=api.head;missing={key:value for key,value in config.items() if key!='intake_config'}
            rejects(lambda:run_encrypted(missing,api,client,secret,now));assert api.head==baseline
            disabled=private/'disabled-policy.json';disabled.write_text(json.dumps(dict(policy,enabled=False)));disabled.chmod(0o600)
            rejects(lambda:run_encrypted(dict(config,intake_config=str(disabled)),api,client,secret,now));assert api.head==baseline
            # A real failing subprocess may emit sensitive stderr; its public outcome stays fixed.
            fresh('invalid',3);assert paused_run()['captured']==1
            invalid=next(row for row in snapshot()[1] if row[1].endswith('/'+client.input[0]['ts']))
            assert invalid[4]=='blocked' and invalid[6]==1 and json.loads(invalid[5])['blocked_reason']=='hosted-assessment-failed'
            # Real CLI errors sanitize malformed private configuration; no providers can be initialized.
            bad=private/'malformed.json';bad.write_text('{"private":"'+marker+'",');bad.chmod(0o600)
            cli=subprocess.run([str(Path(sys.executable).resolve()),str(root/'.claude/scripts/factory-hosted-feedback.py'),'--config',str(bad)],text=True,capture_output=True,timeout=10,env={'PATH':'/usr/bin:/bin'})
            assert cli.returncode==2 and cli.stdout=='' and cli.stderr=='Hosted feedback blocked; reconcile protected state and configuration. Private data withheld.\n'
            channels=[public_stdout.getvalue().encode(),public_stderr.getvalue().encode(),cli.stdout.encode(),cli.stderr.encode(),*api.blobs.values(),json.dumps(api.payloads).encode()]
            assert all(secret_text not in channel for channel in channels for secret_text in [marker.encode(),b'UPRIVATEACTORMARKER',b'PRIVATE-PROVIDER-STDERR-MARKER',b'Proposed login',b'fixture-planning',b'new request requires human approval'])
            final=state()
            assert len(final['intake_requests'])>=5 and len(final['intake_assessments'])>=4
            assert any(marker in row[2] for row in final['intake_requests']) and all(row[3]=='org/repo' for row in final['intake_hosted_identity'])
            assert snapshot()[2] and len(snapshot()[3])==1
            assert hosted.GitState(api,config['state_branch'],policy['stream'],config['bootstrap_sha']).bytes==report_before and client.posts==before[2]
            print('AC-9/AC-10/AC-14: additive private provenance retained, missing/disabled bound policy cannot downgrade, real CLI/public ciphertext diagnostics exclude private markers')
            sys.exit(0)
"""
source=source.replace(needle,checks+'\n'+needle)
sys.argv=['rollback-fixture',str(root),'checkpoint']
exec(compile(source,'actual-hosted-rollback','exec'))
ROLLBACK
exit 0
fi
if [[ "${1:-package}" == matrix ]]; then
  # AC-1 through AC-14: actual adapter journeys; fixtures do not certify live runtimes.
  local_python="${FACTORY_INTAKE_LOCAL_PYTHON:-$(command -v python3)}"
  crypto_python="${FACTORY_INTAKE_CRYPTO_PYTHON:-$local_python}"
  for interpreter in "$local_python" "$crypto_python"; do
    [[ "$interpreter" == /* && -x "$interpreter" ]] || { echo 'matrix: absolute executable Python required' >&2; exit 2; }
  done
  printf 'matrix local interpreter: %s\n' "$local_python"
  "$local_python" --version
  printf 'matrix crypto interpreter: %s\n' "$crypto_python"
  "$crypto_python" - <<'CRYPTO'
import sys,cryptography
print('matrix crypto runtime: '+sys.executable+'; cryptography '+cryptography.__version__)
CRYPTO
  for selector in route-matrix phase1 urgent-control; do
    printf 'matrix console selector: %s\n' "$selector"
    PATH="$(dirname "$local_python"):$PATH" bash "$ROOT/.claude/scripts/test/factory-request-intake.sh" "$selector"
  done
  printf 'matrix Slack selector: phase2\n'
  PATH="$(dirname "$crypto_python"):$PATH" bash "$ROOT/.claude/scripts/test/factory-intake-slack.sh" phase2
  printf 'matrix adoption selector: upgrade\n'
  PATH="$(dirname "$local_python"):$PATH" bash "$0" upgrade
  printf 'matrix complete: 3 console selectors, Slack phase2, adoption upgrade; offline fixtures only\n'
  exit 0
fi
case "${1:-package}" in package|upgrade) ;; *) exit 2 ;; esac
python3 - "$ROOT" "${1:-package}" <<'PYTEST'
import hashlib,importlib.util,json,os,shutil,stat,subprocess,sys,tempfile
from pathlib import Path
root=Path(sys.argv[1])
def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
adopt=module('adoption',root/'.claude/scripts/factory-adopt.py')
def git(path,*args):return subprocess.check_output(['git','-C',str(path),*args],text=True,stderr=subprocess.DEVNULL,env={**os.environ,'GIT_CONFIG_GLOBAL':os.devnull,'GIT_CONFIG_NOSYSTEM':'1'}).strip()
def initialize(path):
 path.mkdir();git(path,'init','-b','main');git(path,'config','user.name','Fixture');git(path,'config','user.email','fixture@example.invalid')
def put(root,name,data):
 path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(data)
def snapshot(path):return {str(file.relative_to(path)):file.read_bytes() for file in path.rglob('*') if file.is_file() and '.git' not in file.relative_to(path).parts}
with tempfile.TemporaryDirectory(prefix='neutral intake adoption ') as tmp:
 base=Path(tmp).resolve();source=base/'source';initialize(source)
 # Capture current tracked package bytes, never HEAD-only or unrelated untracked/private data.
 task_files={'factory/request-intake.example.json','docs/FACTORY-REQUEST-INTAKE.md','.claude/scripts/test/factory-intake-adoption.sh'}
 tracked=set(subprocess.check_output(['git','-C',str(root),'ls-files','-z']).decode().split('\0'))-{''}
 selected={name for name in tracked if adopt.allowed(name)}|task_files
 for name in selected:
  origin=root/name;assert origin.is_file() and not origin.is_symlink(),name
  destination=source/name;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(origin,destination);destination.chmod(stat.S_IMODE(origin.stat().st_mode))
 # Synthetic exclusions prove the source package cannot import pilot or product authority.
 excluded=['factory/policy.json','.claude/state/private.json','.claude/memory/topics/private.md','specs/active/999-private.md','tasks/TASKS.md','.claude/settings.local.json','factory/private.sqlite']
 for name in excluded:put(source,name,'SOURCE-ONLY-PRIVATE-SENTINEL')
 git(source,'add','-f','.');git(source,'commit','-m','isolated current package image');source_sha=git(source,'rev-parse','HEAD');assert not git(source,'status','--porcelain')
 for name in task_files|{'.claude/scripts/factory-adopt.py'}:assert (source/name).read_bytes()==(root/name).read_bytes()
 target=base/'target';initialize(target)
 own={'README.md':'my product','.claude/memory/MEMORY.md':'my memory','tasks/TASKS.md':'my approved product tasks','.claude/state/owned.json':'my private state','.claude/settings.local.json':'my private settings'}
 for name,data in own.items():put(target,name,data)
 git(target,'add','.');git(target,'commit','-m','target product state');before=snapshot(target)
 home=base/'home';home.mkdir();audit=base/'audit';audit.mkdir();log=base/'audit.log'
 # The actual adopter subprocess may only issue local read-only Git commands. No installed script runs.
 (audit/'sitecustomize.py').write_text("""import os,sys
from pathlib import Path
def guard(event,args):
 if event=='subprocess.Popen':
  command=args[1]
  with open(os.environ['ADOPTION_AUDIT'],'a') as out:out.write(str(command)+'\\n')
  assert isinstance(command,(list,tuple)) and Path(command[0]).name=='git' and command[1]=='-C' and command[3] in {'rev-parse','status','ls-files'},'unexpected subprocess during adoption'
 if event in {'socket.connect','socket.connect_ex','os.system','os.posix_spawn','os.exec'}:raise AssertionError('external effect during adoption')
sys.addaudithook(guard)
""")
 env={'PATH':os.environ['PATH'],'HOME':str(home),'PYTHONPATH':str(audit),'PYTHONDONTWRITEBYTECODE':'1','ADOPTION_AUDIT':str(log),'GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':os.devnull,'GIT_TERMINAL_PROMPT':'0'}
 state=base/'journal';command=[sys.executable,str(source/'.claude/scripts/factory-adopt.py'),'--from',str(source),'--into',str(target),'--state-root',str(state)]
 process=subprocess.run(command,env=env,text=True,capture_output=True,timeout=60)
 assert process.returncode==0,(process.stdout,process.stderr)
 result=json.loads(process.stdout);assert result['source_sha']==source_sha and result['activation_enabled'] is False and not process.stderr
 expected=task_files|{'.claude/scripts/factory-intake.py','.claude/scripts/factory-intake-scout.py','.claude/scripts/factory-intake-console.py','.claude/hooks/request-intake.sh','.claude/hooks/pre-intake-action.sh','.claude/hooks/post-intake-action.sh'}
 manifest=json.loads((target/adopt.MANIFEST).read_text())
 for name in expected:
  assert (target/name).is_file(),'neutral intake package omitted '+name
  assert (target/name).read_bytes()==(source/name).read_bytes()
  entry=manifest['files'][name];assert entry=={'sha256':hashlib.sha256((source/name).read_bytes()).hexdigest(),'mode':stat.S_IMODE((source/name).stat().st_mode)}
 print('AC-14: actual CLI packages current immutable intake scripts, hooks, neutral example and guide with exact ownership hashes/modes')
 core=module('installed_intake',target/'.claude/scripts/factory-intake.py');neutral=json.loads((target/'factory/request-intake.example.json').read_text());core.validate_contract(neutral)
 assert neutral['enabled'] is False and neutral['trusted_files']=={} and all(neutral[name] is None for name in core.CONTRACT_FIELDS-{'schema_version','enabled','trusted_files','limits'})
 assert neutral['limits']==core.DEFAULT_LIMITS
 feedback=json.loads((target/'factory/feedback.example.json').read_text());assert feedback['enabled'] is feedback['feedback_enabled'] is False and 'intake_config' not in feedback
 core.HostedSlackIntake.validate_assessment_policy({'enabled':False,'dataflow':None,'profile_sha256':None,'trusted_files':{},'limits':core.DEFAULT_LIMITS})
 for name,data in before.items():assert (target/name).read_bytes()==data,'target-owned state changed: '+name
 for name in excluded:
  if name not in own:assert not (target/name).exists(),name
 assert not any(b'SOURCE-ONLY-PRIVATE-SENTINEL' in content for name,content in snapshot(target).items() if not name.startswith('.claude/scripts/test/'))
 settings=json.loads((target/'.claude/settings.json').read_text());hooks=json.dumps(settings['hooks'])
 assert all(name not in hooks for name in ['request-intake.sh','pre-intake-action.sh','post-intake-action.sh'])
 assert not list(home.iterdir()) and log.read_text() and not (target/'.claude/factory-installations.json').exists()
 assert all(not name.endswith(('.sqlite','.db','.key','.pem')) for name in snapshot(target))
 assert state.stat().st_mode&0o777==0o700 and len(list(state.glob('*.json')))==1
 assert all(path.stat().st_mode&0o777==0o600 for path in state.glob('*.json'))
 print('AC-14: disabled schema validates, feedback intake stays absent, adopter state survives, no private source/keys/DB/registry imported, and audited CLI performs only local Git reads')
 if sys.argv[2]=='upgrade':
  # AC-14: actual CLI ownership preflight and revision-bound upgrades are atomic.
  def inventory(path):
   if not path.exists():return None
   return {str(item.relative_to(path)):(stat.S_IMODE(item.stat().st_mode),None if item.is_dir() else item.read_bytes())
           for item in path.rglob('*') if '.git' not in item.relative_to(path).parts}
  def invoke(destination=target,journal=state,upgrade=False):
   args=[sys.executable,str(source/'.claude/scripts/factory-adopt.py'),'--from',str(source),'--into',str(destination),'--state-root',str(journal)]
   if upgrade:args.append('--upgrade')
   return subprocess.run(args,env=env,text=True,capture_output=True,timeout=60)
  def success(process,sha):
   assert process.returncode==0,(process.stdout,process.stderr)
   value=json.loads(process.stdout);assert value['source_sha']==sha and value['activation_enabled'] is False and not process.stderr
   return value
  def blocked(destination,journal,upgrade):
   saved,history=inventory(destination),inventory(journal)
   process=invoke(destination,journal,upgrade)
   assert process.returncode==2 and not process.stdout and 'Harness adoption blocked' in process.stderr
   assert inventory(destination)==saved,'conflict partially changed target bytes/modes/directories or ownership manifest'
   assert inventory(journal)==history,'conflict created or changed an adoption journal'
  protected=base/'operator-policy';protected.mkdir(mode=0o700)
  private_policy=protected/'intake.json';private_policy.write_text(json.dumps(neutral));private_policy.chmod(0o600)
  protected_before=inventory(protected)
  unchanged,history=inventory(target),inventory(state)
  assert success(invoke(),source_sha)['changed_files']==0
  assert inventory(target)==unchanged and inventory(state)==history
  changed=['factory/request-intake.example.json','docs/FACTORY-REQUEST-INTAKE.md','.claude/scripts/factory-intake-scout.py']
  stricter=dict(neutral,limits=dict(neutral['limits'],request_chars=12000))
  (source/changed[0]).write_text(json.dumps(stricter,indent=2)+'\n')
  with (source/changed[1]).open('a') as handle:handle.write('\nIsolated fixture revision B: neutral packaging only.\n')
  with (source/changed[2]).open('a') as handle:handle.write('\n# Isolated fixture revision B.\n')
  old_mode=stat.S_IMODE((source/changed[2]).stat().st_mode);(source/changed[2]).chmod(0o644 if old_mode==0o755 else 0o755)
  git(source,'add','-f','.');git(source,'commit','-m','neutral package revision B');next_sha=git(source,'rev-parse','HEAD')
  assert next_sha!=source_sha and not git(source,'status','--porcelain')
  blocked(target,state,False)
  result=success(invoke(upgrade=True),next_sha);assert result['changed_files']==len(changed)+1
  updated=json.loads((target/adopt.MANIFEST).read_text());assert updated['source_sha']==next_sha
  for name in changed:
   assert (target/name).read_bytes()==(source/name).read_bytes()
   assert stat.S_IMODE((target/name).stat().st_mode)==stat.S_IMODE((source/name).stat().st_mode)
   assert updated['files'][name]=={'sha256':hashlib.sha256((source/name).read_bytes()).hexdigest(),'mode':stat.S_IMODE((source/name).stat().st_mode)}
  assert updated['files'][changed[2]]['mode']!=manifest['files'][changed[2]]['mode']
  core.validate_contract(json.loads((target/changed[0]).read_text()));assert json.loads((target/changed[0]).read_text())==stricter
  stable,history=inventory(target),inventory(state)
  assert success(invoke(upgrade=True),next_sha)['changed_files']==0
  assert inventory(target)==stable and inventory(state)==history and len(list(state.glob('*.json')))==2
  for name,data in own.items():assert (target/name).read_text()==data
  assert inventory(protected)==protected_before
  assert (target/'.claude/settings.json').read_bytes()==(source/'.claude/settings.json').read_bytes()
  assert 'intake_config' not in json.loads((target/'factory/feedback.example.json').read_text())
  assert all(name not in json.dumps(json.loads((target/'.claude/settings.json').read_text())['hooks']) for name in ['request-intake.sh','pre-intake-action.sh','post-intake-action.sh'])
  print('AC-14: actual CLI upgrades clean source A to B with exact script/template/guide hashes and modes; explicit upgrade required, exact replay is idempotent, adopter policy/state remain unchanged')
  for index,name in enumerate(changed[:2]):
   foreign=base/('foreign-'+str(index));initialize(foreign)
   for path,data in own.items():put(foreign,path,data)
   put(foreign,name,'foreign adopter-owned intake asset')
   git(foreign,'add','-f','.');git(foreign,'commit','-m','foreign ownership fixture')
   foreign_state=base/('foreign-journal-'+str(index))
   blocked(foreign,foreign_state,False);blocked(foreign,foreign_state,True)
   assert not (foreign/adopt.MANIFEST).exists() and not foreign_state.exists()
  customized=base/'customized';initialize(customized);put(customized,'README.md','customized adopter')
  git(customized,'add','.');git(customized,'commit','-m','customized product')
  custom_state=base/'customized-journal'
  git(source,'checkout',source_sha);assert not git(source,'status','--porcelain')
  success(invoke(customized,custom_state),source_sha)
  customized_asset=customized/changed[2]
  with customized_asset.open('a') as handle:handle.write('\n# Adopter customization must survive.\n')
  git(source,'checkout',next_sha);assert not git(source,'status','--porcelain')
  blocked(customized,custom_state,True)
  assert json.loads((customized/adopt.MANIFEST).read_text())['source_sha']==source_sha
  assert inventory(protected)==protected_before and not list(home.iterdir())
  for destination in [target,customized]:
   for name in excluded:
    if name not in own:assert not (destination/name).exists(),name
   assert all(not name.endswith(('.sqlite','.db','.key','.pem')) for name in snapshot(destination))
  print('AC-14: preexisting foreign intake template/guide and locally modified managed script reject before target/manifest/journal mutation; audited CLI retains default-off without provider/network/registry effects')

PYTEST

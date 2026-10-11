#!/usr/bin/env bash
set -euo pipefail
if [ "${FACTORY_DOCKER_DRILL:-false}" != true ]; then
  echo 'SKIP: actual Linux Docker isolation drill requires explicit CI enablement; no isolation proof claimed'
  exit 0
fi
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import fcntl,hashlib,importlib.util,json,os,re,shutil,signal,subprocess,sys,tempfile,time,uuid
from pathlib import Path
root=Path(sys.argv[1]);assert sys.platform=='linux' and os.getuid()>0,'real isolation drill requires nonroot Linux'
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
sup=module('supervisor',root/'.claude/scripts/factory-supervisor.py');adapter=module('container',root/'.claude/scripts/factory-container.py')
binary=Path(shutil.which('docker') or '/missing-docker').resolve();busybox=Path(shutil.which('busybox') or '/missing-busybox').resolve();assert binary.is_file() and busybox.is_file()
old_umask=os.umask(0o077)
with tempfile.TemporaryDirectory() as temporary:
    base=Path(temporary).resolve();private=base/'private';private.mkdir(mode=0o700);context=base/'image';context.mkdir();shutil.copyfile(busybox,context/'busybox');(context/'busybox').chmod(0o755);(context/'Dockerfile').write_text('FROM scratch\nCOPY busybox /bin/busybox\n')
    client=base/'client';client.mkdir();prefix=[str(binary),'--config',str(client),'--host','unix:///var/run/docker.sock'];env={'PATH':os.defpath,'HOME':str(client),'LC_ALL':'C'}
    def docker(args):return subprocess.run([*prefix,*args],env=env,capture_output=True,text=True,timeout=30,check=True).stdout
    tag='factory-isolation-fixture:'+uuid.uuid4().hex;docker(['info','--format','{{.ServerVersion}}']);docker(['build','--network','none','--quiet','--tag',tag,str(context)])
    image=json.loads(docker(['image','inspect',tag]))[0]['Id'];assert re.fullmatch(r'sha256:[a-f0-9]{64}',image)
    config={'kind':'docker-offline','binary':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'image':image,'repository':'fixture/isolation','memory_mb':128,'cpus':1,'pids_limit':64}
    database=private/'state.sqlite';store=sup.runtime.Store(database);database.chmod(0o600);attempts=private/'attempts';attempts.mkdir(mode=0o700)
    source=base/'candidate';source.mkdir(mode=0o755);(source/'input.txt').write_text('source')
    secret=private/'coordinator-secret';secret.write_text('PRIVATE HOST CANARY');secret.chmod(0o600)
    command=['/bin/busybox','sh','-ec',f'''test "$(/bin/busybox id -u)" -ne 0
    test ! -e {secret}
    test ! -e {database}
    test ! -S /var/run/docker.sock
    test -z "${{GH_TOKEN:-}}"
    test -z "${{FACTORY_SLACK_BOT_TOKEN:-}}"
    test -z "${{CLAUDE_CODE_OAUTH_TOKEN:-}}"
    if /bin/busybox touch /root-write-canary; then exit 31; fi
    if /bin/busybox wget -T 1 -q -O /tmp/network-result http://1.1.1.1; then exit 32; fi
    if /bin/busybox ps -o comm | /bin/busybox grep -q python; then exit 33; fi
    /bin/busybox echo isolated > /workspace/observed.txt
    ''']
    host=subprocess.Popen([sys.executable,'-c','import time;time.sleep(120)','host-process-canary'])
    try:
        store.enqueue('T-1','a'*64,[])
        assert sup.supervise(database,'T-1',command,source,attempts,timeout=15,lease=10,resources={'execution':config,'services':[]})==0
        assert (source/'observed.txt').read_text().strip()=='isolated' and store.get('T-1')['state']=='verifying'
        effect=store.worker_effects('T-1')[0];assert effect['status']=='clean' and effect['presence']
        # Both workers bind the same internal port in their private namespaces.
        policy=private/'execution.json';policy.write_text(json.dumps(config));launcher=private/'launch.py';launcher.write_text('''import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('sup',Path(sys.argv[1])/'.claude/scripts/factory-supervisor.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
code=m.supervise(sys.argv[2],sys.argv[3],json.loads(sys.argv[7]),sys.argv[4],sys.argv[5],timeout=30,lease=5,resources={'execution':json.loads(Path(sys.argv[6]).read_text()),'services':[]});raise SystemExit(code)
''')
        processes=[]
        for number in (2,3):
            task=f'T-{number}';store.enqueue(task,'a'*64,[]);directory=base/task;directory.mkdir(mode=0o755)
            argv=['/bin/busybox','sh','-ec','/bin/busybox nc -l -p 8123 >/tmp/service & server=$!; /bin/busybox sleep 1; kill -0 "$server"; /bin/busybox echo ready > /workspace/ready; /bin/busybox sleep 2; kill "$server"; if wait "$server"; then :; else test "$?" -eq 143; fi']
            processes.append(subprocess.Popen([sys.executable,str(launcher),str(root),str(database),task,str(directory),str(attempts),str(policy),json.dumps(argv)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True))
        for process in processes:
            output,error=process.communicate(timeout=20);assert process.returncode==0,(output,error)
        assert all((base/f'T-{number}'/'ready').exists() and store.worker_effects(f'T-{number}')[0]['status']=='clean' for number in (2,3))
        store.enqueue('T-4','a'*64,[])
        assert sup.supervise(database,'T-4',['/bin/busybox','sleep','30'],source,attempts,timeout=1,lease=5,resources={'execution':config,'services':[]})!=0
        assert store.get('T-4')['state']=='blocked' and store.worker_effects('T-4')[0]['status']=='clean'
        store.enqueue('T-5','a'*64,[])
        process=subprocess.Popen([sys.executable,str(launcher),str(root),str(database),'T-5',str(source),str(attempts),str(policy),json.dumps(['/bin/busybox','sleep','30'])],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        deadline=time.monotonic()+15
        while not store.worker_effects('T-5') or not store.worker_effects('T-5')[0]['presence']:
            assert time.monotonic()<deadline,'daemon worker did not publish presence';assert process.poll() is None;time.sleep(.05)
        os.kill(process.pid,signal.SIGKILL);process.communicate(timeout=5)
        deadline=time.monotonic()+15
        while store.get('T-5')['state']!='queued':
            assert time.monotonic()<deadline,'guardian did not confirm daemon cleanup/requeue';time.sleep(.05)
        assert store.worker_effects('T-5')[0]['status']=='clean'
        # Requeue precedes guardian exit; verify the actual inherited lock is released.
        lock=database.parent/('worker-'+hashlib.sha256(b'T-5').hexdigest()+'.lock')
        deadline=time.monotonic()+5
        with lock.open('a+b') as holder:
            while True:
                try:fcntl.flock(holder.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB);break
                except BlockingIOError:
                    assert time.monotonic()<deadline,'guardian retained task lock after cleanup';time.sleep(.05)
            fcntl.flock(holder.fileno(),fcntl.LOCK_UN)
        assert sup.supervise(database,'T-5',['/bin/busybox','true'],source,attempts,timeout=10,lease=5,resources={'execution':config,'services':[]})==0
        for task in ('T-1','T-2','T-3','T-4','T-5'):
            for effect in store.worker_effects(task):
                name=json.loads(effect['identity'])['name'];assert not docker(['container','ls','--all','--filter','name=^/'+name+'$','--format','{{.ID}}']).strip()
        print('AC-4: actual Linux Docker blocks host files/credentials/socket/processes, root writes and egress; simultaneous same-port services isolate, timeout/SIGKILL remove daemon workers, fenced retry leaves no containers')
        output=Path(os.environ['FACTORY_DOCKER_RESULT']);output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps({'source_sha':subprocess.check_output(['/usr/bin/git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),'platform':sys.platform,'image_id':image,'docker_sha256':config['sha256'],'independent_attestation':False,'assertions':[{'fullName':'AC-4: actual Linux Docker isolation, concurrent services, timeout, supervisor SIGKILL cleanup and fenced retry passed','status':'passed'}]},indent=2)+'\n')
    finally:
        if host.poll() is None:host.kill()
        host.wait(timeout=5)
        for task in ('T-1','T-2','T-3','T-4','T-5'):
            try:effects=store.worker_effects(task)
            except sup.runtime.Blocked:continue
            for effect in effects:
                cleanup=adapter.Container.for_cleanup(config,store,effect)
                try:cleanup.cleanup()
                finally:cleanup.close()
        docker(['image','rm',tag])
os.umask(old_umask)
PYTEST

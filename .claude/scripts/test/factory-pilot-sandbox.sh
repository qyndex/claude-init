#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import hashlib, importlib.util, json, os, subprocess, sys, tempfile, uuid
from pathlib import Path
root=Path(sys.argv[1])
# Installation deliberately omits the source pilot's proposal package.
if (root/'.claude/install-manifest.json').exists():
    print('SKIP: source pilot feasibility fixture is not adopter readiness proof')
    raise SystemExit(0)
workflow=(root/'.github/workflows/harness-validate.yml').read_text()
assert 'Actual pinned pilot verifier sandbox drill' in workflow, 'actual pinned pilot sandbox CI gate absent'
assert 'FACTORY_PILOT_DRILL: "true"' in workflow and 'factory-pilot-sandbox-${{ github.run_id }}' in workflow
policy_path=root/'docs/activation/2026-10-11/policy.shadow.proposed.json'
policy=json.loads(policy_path.read_text()); approved=policy['specs']['048']
spec=importlib.util.spec_from_file_location('producer', root/'.claude/scripts/factory-producer.py')
producer=importlib.util.module_from_spec(spec);spec.loader.exec_module(producer)
fixture="""Prerequisites
Dry-run adoption uses immutable reviewed source and preserves existing content.
python3 .claude/scripts/factory-adopt.py --from /path/to/reviewed-harness --into /path/to/target --dry-run
Protected readiness
factory-preflight.py --policy /path/to/protected-policy.json
Missing gates block merge authority, reporting and production; each adopter owns secrets.
Delivery and acceptance
engineering verification, merged delivery and product acceptance are distinct.
Define SLO and rollback; see FACTORY-ADOPTER-SETUP.md and FACTORY-ACTIVATION.md.
"""
broken={'AC-1':'Prerequisites','AC-2':'Protected readiness','AC-3':'Delivery and acceptance'}
live=os.environ.get('FACTORY_PILOT_DRILL')=='true'
if live:
    assert sys.platform=='linux' and os.getuid()>0, 'enabled pilot drill requires nonroot Linux'
    subprocess.run(['docker','info','--format','{{.ServerVersion}}'],check=True,timeout=30)
    subprocess.run(['docker','pull',approved['verification_image']],check=True,timeout=300)
observations=[]
with tempfile.TemporaryDirectory() as temporary:
    base=Path(temporary).resolve(); candidate=base/'candidate';candidate.mkdir(mode=0o755)
    docs=candidate/'docs';docs.mkdir(mode=0o755);document=docs/'FACTORY-ADOPTER-QUICKSTART.md'
    secret=base/'host-canary';secret.write_text('nonsensitive fixture marker')
    def run(label, argv, expected):
        name='factory-pilot-drill-'+uuid.uuid4().hex
        command=producer.sandbox_command(approved['verification_image'],candidate,name,argv) if live else argv
        if live:
            assert '--read-only' in command and command[command.index('--network')+1]=='none'
            assert command[command.index('--user')+1]=='65532:65532' and command.count('--mount')==1
        with tempfile.TemporaryFile() as log:
            try:
                process=producer.bounded_acceptance(command,stdout=log,stderr=subprocess.STDOUT,timeout=60) if live else subprocess.run(command,cwd=candidate,stdout=log,stderr=subprocess.STDOUT,timeout=30)
            finally:
                if live: subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
            log.seek(0);output=log.read().decode(errors='replace')
        assert (process.returncode==0)==expected, (label,process.returncode,output)
        observations.append({'case':label,'exit_code':process.returncode,'expected_pass':expected})
    for ac,argv in approved['acceptance_commands'].items():
        document.write_text(fixture);document.chmod(0o644)
        run('positive '+ac,argv,True)
        assert document.read_text()==fixture, 'sandbox changed original fixture'
        document.write_text(fixture.replace(broken[ac],'intentionally omitted'))
        run('defective '+ac,argv,False)
        assert document.read_text()==fixture.replace(broken[ac],'intentionally omitted')
    print('AC-1: exact proposed argv passes positive fixture and rejects individually defective fixtures; original bytes preserved')
    if live:
        document.write_text(fixture)
        probe="""import os, socket
from pathlib import Path
assert os.getuid()==65532
assert not any(os.environ.get(k) for k in ('GH_TOKEN','GITHUB_TOKEN','CLAUDE_CODE_OAUTH_TOKEN','FACTORY_SLACK_BOT_TOKEN','FACTORY_PILOT_HOST_CANARY'))
assert not Path('/var/run/docker.sock').exists()
assert not Path(__HOST_FILE__).exists()
status=Path('/proc/self/status').read_text()
assert 'CapEff:\t0000000000000000' in status and 'NoNewPrivs:\t1' in status
for target in ('/root-write-canary','/candidate/write-canary'):
    try: Path(target).write_text('blocked')
    except OSError: pass
    else: raise AssertionError('write outside temporary copy allowed')
assert {p.name for p in Path('/sys/class/net').iterdir()}=={'lo'}
s=socket.socket();s.settimeout(1)
try: s.connect(('1.1.1.1',443))
except OSError: pass
else: raise AssertionError('egress allowed')
finally: s.close()
Path('temporary-copy-write').write_text('works')
assert Path('temporary-copy-write').read_text()=='works'
print('actual sandbox isolation passed')
""".replace('__HOST_FILE__',repr(str(secret)))
        # Only a fake host marker is injected; no actual secret is read.
        os.environ['FACTORY_PILOT_HOST_CANARY']='host-only-fixture-marker'
        try: run('actual isolation',['python3','-c',probe],True)
        finally: os.environ.pop('FACTORY_PILOT_HOST_CANARY',None)
        assert not (candidate/'temporary-copy-write').exists() and document.read_text()==fixture
        print('AC-2: pinned actual sandbox is nonroot, offline, capability-free, read-only outside its temporary copy and excludes host canaries/socket')
        result={'source_sha':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(), 'image':approved['verification_image'],'proposal_sha256':hashlib.sha256(policy_path.read_bytes()).hexdigest(),'platform':sys.platform,'independent_attestation':False,'pilot_approved':False,'delivery_receipt':False,'observations':observations}
        destination=Path(os.environ['FACTORY_PILOT_RESULT']);destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(json.dumps(result,indent=2)+'\n')
        print('AC-3: actual source/image/proposal-bound nonsensitive proof retained; no authority/model/receipt claim')
    else:
        print('SKIP: actual pinned Linux sandbox requires explicit CI enablement; host command coverage is not isolation proof')
PYTEST

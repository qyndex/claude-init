#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
# AC-6, AC-9: private store code dependencies must be pinned before import
import hashlib,importlib.util,json,sys,tempfile
from pathlib import Path
helper=Path(sys.argv[1])/'.claude/scripts/factory-intake.py';s=importlib.util.spec_from_file_location('m',helper);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory() as d:
 base=Path(d).resolve();account_home=base/'os-account';account_home.mkdir(mode=0o700)
 import pwd
 pwd.getpwuid=lambda uid: type('Account',(),{'pw_dir':str(account_home)})()
 private=base/'private';private.mkdir(mode=0o700);candidate=base/'candidate';candidate.mkdir();authority=base/'authority';authority.mkdir()
 policy=private/'policy.json';profile=private/'profile.json'
 for p in [policy,profile]:p.write_text('{}');p.chmod(0o600)
 config=private/'intake.json';value={'schema_version':1,'enabled':True,'repository':'fixture/intake','candidate_root':str(candidate),'authority_root':str(authority),'database':str(private/'runtime.sqlite'),'profile':str(profile),'policy':str(policy),'trusted_files':{str(p):sha(p) for p in [helper,profile,policy]},'limits':m.DEFAULT_LIMITS}
 config.write_text(json.dumps(value));config.chmod(0o600)
 try:m.load_contract(config)
 except ValueError:pass
 else:raise AssertionError('unpinned private runtime code dependency accepted')
 dependency=helper.with_name('factory-runtime.py');value['trusted_files'][str(dependency)]=sha(dependency);config.write_text(json.dumps(value));assert m.load_contract(config)==value
 value['trusted_files'][str(dependency)]='0'*64;config.write_text(json.dumps(value))
 try:m.Intake(config)
 except ValueError:pass
 else:raise AssertionError('changed runtime dependency accepted')
 assert not (private/'runtime.sqlite').exists(),'state was mutated before dependency validation'
 print('private runtime dependency pins are required and checked before state mutation/import')
PY

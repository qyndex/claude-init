#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
# AC-4, AC-7: protected task selection and unresolved numbered questions
import hashlib,importlib.util,json,os,sys,tempfile
from pathlib import Path
helper=Path(sys.argv[1])/'.claude/scripts/factory-intake.py';s=importlib.util.spec_from_file_location('m',helper);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory() as d:
 base=Path(d).resolve();account_home=base/'os-account';account_home.mkdir(mode=0o700)
 import pwd
 pwd.getpwuid=lambda uid: type('Account',(),{'pw_dir':str(account_home)})()
 private=base/'private';private.mkdir(mode=0o700);candidate=base/'candidate';candidate.mkdir();authority=base/'authority';authority.mkdir()
 for folder in ['specs/active','plans/active','tasks']:(authority/folder).mkdir(parents=True)
 source=authority/'specs/active/001-fixture.md';source.write_text('---\nid: 001\nstatus: approved\n---\n**AC-1**: fixture\n')
 (authority/'plans/active/001-fixture.md').write_text('---\nstatus: approved\nspec: specs/active/001-fixture.md\n---\n')
 (authority/'tasks/TASKS.md').write_text('## Active\n- [ ] T-1 | spec:001 | deps:\n')
 policy=private/'policy.json';profile=private/'profile.json';profile.write_text('{}');profile.chmod(0o600)
 def install(task_ids,questions=''):
  source.write_text('---\nid: 001\nstatus: approved\n---\n**AC-1**: fixture\n\n## Open questions\n'+questions+'\n## References\n')
  policy.write_text(json.dumps({'repository':'fixture/intake','specs':{'001':{'path':'specs/active/001-fixture.md','sha256':sha(source),'ac_ids':['AC-1'],'allowed_paths':['src/*'],'task_ids':task_ids}}}));policy.chmod(0o600)
  database=private/'runtime.sqlite'
  if database.exists():database.unlink()
  config=private/'intake.json';config.write_text(json.dumps({'schema_version':1,'enabled':True,'repository':'fixture/intake','candidate_root':str(candidate),'authority_root':str(authority),'database':str(database),'profile':str(profile),'policy':str(policy),'trusted_files':{str(p):sha(p) for p in [helper,helper.with_name('factory-runtime.py'),profile,policy]},'limits':m.DEFAULT_LIMITS}));config.chmod(0o600)
  store=m.Intake(config);session=store.new_session();receipt=store.submit_console(session,'continue T-1','a'*40);return store.lightweight(receipt['request_id'])
 assert install(['T-2'])['disposition']=='clarify','unapproved task ID was reported resumable'
 assert install([])['disposition']=='clarify','empty approved task set was bypassed'
 assert install(['T-1'],'- [OQ-1] Which behavior is wanted?')['disposition']=='clarify','open numbered question was ignored'
 assert install(['T-1'],'- [OQ] Which behavior is wanted?')['disposition']=='clarify'
 assert install(['T-1'],'- ~~[OQ-1] Which behavior?~~ → Decision: use approved behavior.')['disposition']=='existing_approved'
 assert install(['T-1'])['disposition']=='existing_approved'
 print('task allowlist and open numbered questions fence continuation; resolved questions retain eligibility')
PY

#!/usr/bin/env bash
set -euo pipefail
ROOT="${INSTALLER_SOURCE_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import os,subprocess,sys,tempfile
installer=Path(sys.argv[1])/'scripts/install.sh'
def git(root,*args):return subprocess.check_output(['git','-C',str(root),*args],text=True,stderr=subprocess.DEVNULL).strip()
with tempfile.TemporaryDirectory(prefix="installer fixture ' ") as tmp:
    root=Path(tmp);source=root/'source';source.mkdir();git(source,'init','-b','main');git(source,'config','user.email','fixture@example.invalid');git(source,'config','user.name','Fixture')
    scripts=source/'.claude/scripts';scripts.mkdir(parents=True)
    (scripts/'reconcile-claude-dir.sh').write_text('''#!/usr/bin/env bash
set -euo pipefail
from="";into=""
while [ $# -gt 0 ]; do case "$1" in --from) from="$2";shift 2;;--into) into="$2";shift 2;;*) shift;;esac;done
mkdir -p "$into/.claude/scripts"
cp "$from/.claude/VERSION" "$into/installed-version"
cp "$from/.claude/scripts/setup.sh" "$into/.claude/scripts/setup.sh"
''')
    (scripts/'setup.sh').write_text('#!/usr/bin/env bash\nexit 7\n')
    (source/'.claude/VERSION').write_text('old');git(source,'add','.');git(source,'commit','-m','old');old=git(source,'rev-parse','HEAD');git(source,'tag','v-test')
    (source/'.claude/VERSION').write_text('new');git(source,'add','.');git(source,'commit','-m','new')
    def target(name):
        path=root/name;path.mkdir();git(path,'init','-b','main');git(path,'config','user.email','fixture@example.invalid');git(path,'config','user.name','Fixture');(path/'README.md').write_text('owned');git(path,'add','.');git(path,'commit','-m','project');return path
    def run(path,ref='main',**overrides):
        env=dict(os.environ);env.update({'CLAUDE_INIT_REPO':str(source),'CLAUDE_INIT_REF':ref,'INTO':str(path),'SKIP_SETUP':'1','YES':'0','UPGRADE':'0'});env.update(overrides)
        return subprocess.run(['bash',str(installer)],env=env,capture_output=True,text=True)
    # AC-1: unknown refs cannot silently install default HEAD.
    missing=target('missing');r=run(missing,'does-not-exist');assert r.returncode!=0 and not (missing/'installed-version').exists(), 'unknown ref silently installed default branch'
    for name,ref in [('sha',old),('tag','v-test')]:
        path=target(name);r=run(path,ref);assert r.returncode==0,r.stderr+r.stdout;assert (path/'installed-version').read_text()=='old', 'requested immutable ref ignored'
        assert old in r.stdout, 'resolved source SHA not reported';assert (path/'README.md').read_text()=='owned'
    # AC-2: staged and untracked state count as dirty; YES=0 is not consent.
    for name,staged in [('untracked',False),('staged',True),('unstaged',False)]:
        path=target(name)
        if name=='unstaged':(path/'README.md').write_text('custom')
        else:(path/'user.txt').write_text('custom')
        if staged:git(path,'add','user.txt')
        r=run(path);assert r.returncode!=0 and not (path/'installed-version').exists(), 'dirty target modified without explicit override'
    for option in ['YES','UPGRADE','SKIP_SETUP']:
        path=target('bad-'+option);r=run(path,**{option:'true'});assert r.returncode!=0 and not (path/'installed-version').exists()
    dirty=target('override');(dirty/'user.txt').write_text('keep');r=run(dirty,YES='1');assert r.returncode==0 and (dirty/'user.txt').read_text()=='keep'
    nested=dirty/'subdir';nested.mkdir();r=run(nested,YES='1');assert r.returncode!=0 and not (nested/'installed-version').exists()
    # AC-3: linked Git worktrees are valid target repositories.
    parent=target('parent');linked=root/'linked';git(parent,'worktree','add','-b','fixture-linked',str(linked));r=run(linked);assert r.returncode==0,r.stderr+r.stdout;assert (linked/'installed-version').read_text()=='new'
    # AC-4: setup failure is visible and never reported as successful installation.
    path=target('setup-failure');r=run(path,SKIP_SETUP='0');assert r.returncode!=0 and 'claude-init installed into' not in r.stdout, 'setup error reported successful'
print('factory-installer-source: strict refs/SHA/tag, dirty guards, linked worktrees and visible setup failures passed')
PY

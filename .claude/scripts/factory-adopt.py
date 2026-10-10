#!/usr/bin/env python3
"""Transactional, versioned harness ownership; activation is a separate decision."""
import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

DIRECTORIES=('agents','skills','scripts','routines','statuslines','output-styles','commands','hooks','templates')
MANIFEST='.claude/install-manifest.json'
SEEDS={'tasks/TASKS.md':'# Tasks\n\nAppend-only product authority. Add tasks only from approved specifications and plans.\n\n## Active\n\n## Archive\n', '.claude/memory/MEMORY.md':'# Project memory\n\nRecord verified repository conventions and decisions here.\n', 'specs/active/.gitkeep':'', 'plans/active/.gitkeep':'', 'initiatives/active/.gitkeep':''}


def require(condition,message):
    if not condition:raise ValueError(message)


def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False)


def load(path):
    def pairs(items):
        result={}
        for key,value in items:
            require(key not in result,'duplicate manifest field');result[key]=value
        return result
    return json.loads(path.read_text(),object_pairs_hook=pairs)


def allowed(path):
    return path in {'.claude/CLAUDE.md','.claude/settings.json','.claude/VERSION','.claude/REGISTRY.md','CLAUDE.md','.mcp.json','docs/FACTORY-ADOPTION.md'} or any(path.startswith(f'.claude/{directory}/') for directory in DIRECTORIES) or bool(re.fullmatch(r'\.claude/memory/(?:[A-Za-z0-9_-]+/)*0000-template\.md',path)) or any(path.startswith(prefix) for prefix in ('specs/templates/','plans/templates/','initiatives/templates/'))


def safe(root,path):
    require(isinstance(path,str) and path and not Path(path).is_absolute() and '..' not in Path(path).parts and (allowed(path) or path==MANIFEST or path in SEEDS),'invalid managed path')
    result=root/path;require(result.resolve()==result and not result.is_symlink(),'managed path crosses symlink')
    if result.exists():require(result.is_file(),'managed path is not a regular file')
    return result


def image(path):
    if not path.exists():return None
    require(path.is_file() and not path.is_symlink(),'unsafe file snapshot')
    return {'bytes':base64.b64encode(path.read_bytes()).decode(),'mode':stat.S_IMODE(path.stat().st_mode)}


def fingerprint(value):
    if value is None:return None
    return {'sha256':hashlib.sha256(base64.b64decode(value['bytes'],validate=True)).hexdigest(),'mode':value['mode']}


def write(path,value):
    if value is None:
        if path.exists():path.unlink()
        return
    path.parent.mkdir(parents=True,exist_ok=True)
    descriptor,tmp=tempfile.mkstemp(dir=path.parent,prefix='.adopt-')
    try:
        with os.fdopen(descriptor,'wb') as out:
            out.write(base64.b64decode(value['bytes'],validate=True));out.flush();os.fsync(out.fileno())
        os.chmod(tmp,value['mode']);os.replace(tmp,path)
    finally:
        if Path(tmp).exists():Path(tmp).unlink()


def json_image(value):return {'bytes':base64.b64encode((canonical(value)+'\n').encode()).decode(),'mode':0o644}


def package(source):
    actual=Path(subprocess.check_output(['git','-C',str(source),'rev-parse','--show-toplevel'],text=True).strip()).resolve();require(actual==source,'source must be repository root')
    require(not subprocess.check_output(['git','-C',str(source),'status','--porcelain'],text=True).strip(),'source checkout must be clean')
    revision=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip();require(re.fullmatch(r'[a-f0-9]{40}',revision),'source commit invalid')
    paths=subprocess.check_output(['git','-C',str(source),'ls-files','-z']).decode().split('\0')
    files={path:image(safe(source,path)) for path in paths if path and allowed(path)}
    require(files and '.claude/VERSION' in files,'source package incomplete')
    require(all(value is not None and value['mode'] in {0o644,0o755} for value in files.values()),'source mode unsupported')
    return revision,files


def validate_manifest(document):
    require(set(document)=={'schema_version','source_sha','files'} and type(document['schema_version']) is int and document['schema_version']==1 and isinstance(document['source_sha'],str) and re.fullmatch(r'[a-f0-9]{40}',document['source_sha']) and isinstance(document['files'],dict),'ownership manifest invalid')
    for path,value in document['files'].items():
        require(allowed(path) and isinstance(value,dict) and set(value)=={'sha256','mode'} and isinstance(value['sha256'],str) and re.fullmatch(r'[a-f0-9]{64}',value['sha256']) and type(value['mode']) is int and value['mode'] in {0o644,0o755},'ownership entry invalid')


def private_state(root,target):
    require(root.is_absolute() and root.resolve()==root and root!=target and target not in root.parents,'adoption journal must be canonical outside target')
    root.mkdir(parents=True,exist_ok=True,mode=0o700)
    require(not root.is_symlink() and root.is_dir() and root.stat().st_uid==os.getuid() and stat.S_IMODE(root.stat().st_mode)==0o700,'private adoption journal owner/mode invalid')


def persist(path,document):
    value=json_image(document);value['mode']=0o600;write(path,value)


def validate_journal(document,target):
    require(set(document)=={'schema_version','target','source_sha','status','changes','created_dirs'} and type(document['schema_version']) is int and document['schema_version']==1 and isinstance(document['source_sha'],str) and re.fullmatch(r'[a-f0-9]{40}',document['source_sha']) and document['target']==str(target) and document['status'] in {'pending','complete','reverted'} and isinstance(document['changes'],dict) and isinstance(document['created_dirs'],list),'adoption journal invalid')
    for path,pair in document['changes'].items():
        safe(target,path);require(set(pair)=={'before','after'},'journal change invalid')
        for value in pair.values():
            if value is not None:require(set(value)=={'bytes','mode'} and type(value['mode']) is int and value['mode'] in {0o644,0o755},'journal image invalid');fingerprint(value)
    for directory in document['created_dirs']:
        require(isinstance(directory,str) and not Path(directory).is_absolute() and '..' not in Path(directory).parts and (target/directory).resolve()==target/directory,'journal directory invalid')
        require(any(path.startswith(directory+'/') for path in document['changes']),'journal directory is not managed')


def restore(target,journal,path):
    validate_journal(journal,target)
    require(journal['status']!='reverted','adoption already reverted')
    for name,pair in journal['changes'].items():
        current=image(safe(target,name));expected=[pair['after']] if journal['status']=='complete' else [pair['before'],pair['after']]
        require(current in expected,'later customization blocks safe recovery')
    for name,pair in reversed(list(journal['changes'].items())):write(safe(target,name),pair['before'])
    for name in sorted(journal['created_dirs'],key=lambda item:len(Path(item).parts),reverse=True):
        directory=target/name
        if directory.is_dir() and not any(directory.iterdir()):directory.rmdir()
    journal['status']='reverted';persist(path,journal)


def adopt(source,target,state_root,upgrade=False,dry=False,check_tools=False,fault=None):
    require(target.is_absolute() and target.resolve()==target and source.is_absolute() and source.resolve()==source and source!=target,'adoption roots invalid')
    actual=Path(subprocess.check_output(['git','-C',str(target),'rev-parse','--show-toplevel'],text=True).strip()).resolve();require(actual==target,'target must be repository root')
    if check_tools:require(all(shutil.which(tool) for tool in ('git','python3','jq')),'required local tools unavailable')
    revision,files=package(source);manifest_path=safe(target,MANIFEST);old=load(manifest_path) if manifest_path.exists() else None
    if old is not None:validate_manifest(old)
    owned=old['files'] if old else {}
    for name,expected in owned.items():require(fingerprint(image(safe(target,name)))==expected,'customized owned file blocks upgrade')
    changes={}
    for name,value in files.items():
        current=image(safe(target,name));require(name in owned or current is None or current==value,'foreign file collision blocks adoption')
        require(name not in owned or current==value or upgrade,'new source requires explicit upgrade')
        if current!=value:changes[name]={'before':current,'after':value}
    for name in set(owned)-set(files):
        require(upgrade,'removed source requires explicit upgrade');changes[name]={'before':image(safe(target,name)),'after':None}
    for name,text in SEEDS.items():
        current=image(safe(target,name))
        if current is None:changes[name]={'before':None,'after':{'bytes':base64.b64encode(text.encode()).decode(),'mode':0o644}}
    desired=json_image({'schema_version':1,'source_sha':revision,'files':{name:fingerprint(value) for name,value in files.items()}})
    if image(manifest_path)!=desired:changes[MANIFEST]={'before':image(manifest_path),'after':desired}
    if dry or not changes:return {'source_sha':revision,'changed_files':len(changes),'dry_run':dry,'activation_enabled':False}
    private_state(state_root,target)
    for path in state_root.glob('*.json'):
        existing=load(path)
        if existing.get('target')==str(target):require(existing.get('status')!='pending','unfinished adoption requires explicit recovery')
    created=set()
    for name in changes:
        parent=(target/name).parent
        while parent!=target:
            if not parent.exists():created.add(str(parent.relative_to(target)))
            parent=parent.parent
    journal={'schema_version':1,'target':str(target),'source_sha':revision,'status':'pending','changes':changes,'created_dirs':sorted(created)}
    identity=uuid.uuid4().hex;path=state_root/(identity+'.json');persist(path,journal)
    try:
        for number,(name,pair) in enumerate(changes.items(),1):
            require(image(safe(target,name))==pair['before'],'target changed after preflight')
            write(safe(target,name),pair['after'])
            if fault is not None:fault(number)
        journal['status']='complete';persist(path,journal)
    except BaseException:
        journal['status']='pending';restore(target,journal,path);raise
    return {'source_sha':revision,'changed_files':len(changes),'journal':identity,'activation_enabled':False}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--from',dest='source');parser.add_argument('--into',default=os.getcwd());parser.add_argument('--state-root',default=os.environ.get('CLAUDE_INIT_STATE_DIR',str(Path.home()/'.local/state/claude-init/adoption')));parser.add_argument('--upgrade',action='store_true');parser.add_argument('--dry-run',action='store_true');parser.add_argument('--check-tools',action='store_true');parser.add_argument('--revert');parser.add_argument('--recover');args=parser.parse_args()
    target=Path(args.into).resolve();state_root=Path(args.state_root).absolute();identity=args.revert or args.recover
    lock_path=Path(tempfile.gettempdir())/('claude-init-adopt-'+hashlib.sha256(str(target).encode()).hexdigest()+'.lock')
    descriptor=os.open(lock_path,os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
    with os.fdopen(descriptor,'w') as lock:
        require(os.fstat(lock.fileno()).st_uid==os.getuid() and stat.S_IMODE(os.fstat(lock.fileno()).st_mode)==0o600,'adoption lock owner/mode invalid');fcntl.flock(lock,fcntl.LOCK_EX)
        if identity:
            require(not args.source and not args.dry_run and not args.upgrade and not(args.revert and args.recover) and re.fullmatch(r'[a-f0-9]{32}',identity),'invalid recovery arguments')
            private_state(state_root,target);path=state_root/(identity+'.json');require(path.is_file() and not path.is_symlink() and path.stat().st_uid==os.getuid() and stat.S_IMODE(path.stat().st_mode)==0o600,'recovery journal unavailable or unsafe')
            journal=load(path);require((args.recover and journal['status']=='pending') or (args.revert and journal['status']=='complete'),'recovery mode differs');restore(target,journal,path);print(canonical({'reverted':identity}));return
        require(args.source is not None,'source required')
        print(canonical(adopt(Path(args.source).resolve(),target,state_root,args.upgrade,args.dry_run,args.check_tools)))


if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,TypeError,OSError,subprocess.SubprocessError):
        import sys
        print('Harness adoption blocked; inspect ownership, private journal and target changes.',file=sys.stderr);sys.exit(2)

#!/usr/bin/env python3
"""Operator-approved immutable legacy feedback migration into private state."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import sys

spec=importlib.util.spec_from_file_location('ingress',Path(__file__).with_name('factory-slack-feedback.py'))
ingress=importlib.util.module_from_spec(spec);spec.loader.exec_module(ingress)
f=ingress.f
require=f.require


def migrate(config,manifest):
    require(config.get('enabled') is True and config.get('feedback_migration_enabled') is True,'legacy migration disabled')
    private,database=ingress.private_paths(config)
    operators=config['operators'];require(isinstance(operators,list) and 0<len(operators)<=100 and all(isinstance(item,str) and re.fullmatch(r'[UW][A-Z0-9]+',item) for item in operators) and len(set(operators))==len(operators),'protected operator allowlist invalid')
    require(set(manifest)=={'schema_version','repository','records'} and type(manifest['schema_version']) is int and manifest['schema_version']==1 and manifest['repository']==config['repository'],'legacy manifest schema/repository invalid')
    digest=hashlib.sha256(f.canonical(manifest).encode()).hexdigest()
    approval=config['approved_legacy_imports'][digest]
    require(set(approval)=={'operator','source_ref'} and approval['operator'] in config['operators'] and isinstance(approval['source_ref'],str) and 0<len(approval['source_ref'])<=1000,'full legacy manifest lacks protected operator approval')
    root=Path(config['legacy_root']);require(root.is_absolute() and root.resolve()==root and root.is_dir() and not root.is_symlink() and root!=private,'legacy source root invalid')
    records=manifest['records'];require(isinstance(records,list) and 0<len(records)<=1000,'legacy record count invalid')
    prepared=[];seen=set()
    for record in records:
        require(set(record)=={'path','sha256','kind','promote'},'legacy record fields invalid')
        path=record['path'];require(isinstance(path,str) and re.fullmatch(r'\.claude/memory/feedback/(active|closed)/FB-[A-Za-z0-9_-]+\.md',path),'legacy source path invalid')
        require(path not in seen,'duplicate legacy source');seen.add(path)
        expected=record['sha256'];require(isinstance(expected,str) and re.fullmatch(r'[a-f0-9]{64}',expected),'legacy source hash invalid')
        source=root/path;require(source.resolve()==source and source.is_file() and not source.is_symlink() and source.stat().st_size<=1000000,'legacy source unsafe or too large')
        raw=source.read_bytes();require(len(raw)<=1000000 and hashlib.sha256(raw).hexdigest()==expected,'legacy source differs from approved bytes')
        require(record['kind'] in {'defect','enhancement','requirement','priority','acceptance'} and type(record['promote']) is bool,'legacy classification/promotion invalid')
        document=None;identity=None
        if record['promote']:
            text=raw.decode('utf-8');require(0<len(text)<=20000,'promoted legacy text bound exceeded')
            source_ref=f"legacy:{config['repository']}:{path}:{expected}"
            document={'repository':config['repository'],'source_ref':source_ref,'reporter':approval['operator'],'text':text,'kind':record['kind'],'digest_key':'','pull_requests':[]}
            identity='FB-'+hashlib.sha256(f.canonical([config['repository'],source_ref]).encode()).hexdigest()
        prepared.append((record,raw,document,identity))
    previous_umask=os.umask(0o077)
    try:
        feedback=f.Feedback(database,config['repository'])
        with feedback.store.transaction() as db:
            db.execute('CREATE TABLE IF NOT EXISTS feedback_ingress_identity(id INTEGER PRIMARY KEY,repository TEXT NOT NULL,team TEXT NOT NULL,destination TEXT NOT NULL)')
            namespace=db.execute('SELECT repository,team,destination FROM feedback_ingress_identity WHERE id=1').fetchone()
            expected_namespace=(config['repository'],config['team_id'],config['destination'])
            require(namespace is None or tuple(namespace)==expected_namespace,'legacy runtime namespace differs')
            if namespace is None:db.execute('INSERT INTO feedback_ingress_identity VALUES(1,?,?,?)',expected_namespace)
            db.execute('CREATE TABLE IF NOT EXISTS feedback_legacy_archive(repository TEXT NOT NULL,path TEXT NOT NULL,sha256 TEXT NOT NULL,manifest_sha256 TEXT NOT NULL,raw BLOB NOT NULL,approval TEXT NOT NULL,feedback TEXT,PRIMARY KEY(repository,path,sha256,manifest_sha256))')
            for record,raw,document,identity in prepared:
                key=(config['repository'],record['path'],record['sha256'],digest);old=db.execute('SELECT raw,approval,feedback FROM feedback_legacy_archive WHERE repository=? AND path=? AND sha256=? AND manifest_sha256=?',key).fetchone()
                authority=f.canonical({'manifest_sha256':digest,'approval':approval,'record':record})
                require(old is None or (bytes(old['raw']),old['approval'],old['feedback'])==(raw,authority,identity),'legacy replay conflicts with immutable approval')
                if document is not None:
                    encoded=f.canonical(document);prior=db.execute('SELECT document FROM factory_feedback WHERE id=?',(identity,)).fetchone()
                    require(prior is None or prior[0]==encoded,'legacy feedback source replay conflicts')
                    if prior is None:
                        db.execute('INSERT INTO factory_feedback(id,document,status) VALUES(?,?,?)',(identity,encoded,'open'))
                        feedback.event(db,identity,{'type':'legacy-captured','manifest_sha256':digest,'approval':approval,'document':document,'delivery_proof':'absent'})
                if old is None:db.execute('INSERT INTO feedback_legacy_archive VALUES(?,?,?,?,?,?,?)',(*key,raw,authority,identity))
        return {'archived':len(prepared),'promoted':sum(identity is not None for _,_,_,identity in prepared),'manifest_sha256':digest}
    finally:os.umask(previous_umask)


def protected_file(path,root):
    require(path.is_absolute() and path.parent==root and path.resolve()==path and not path.is_symlink() and path.is_file() and path.stat().st_uid==os.getuid() and stat.S_IMODE(path.stat().st_mode)==0o600,'migration control file must be private-root owned 0600')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);parser.add_argument('--manifest',required=True);args=parser.parse_args()
    config_path=Path(args.config);config=f.digest.coordinator.contract.load(config_path);root,_=ingress.private_paths(config);protected_file(config_path,root)
    manifest_path=Path(args.manifest);protected_file(manifest_path,root)
    print(f.canonical(migrate(config,f.digest.coordinator.contract.load(manifest_path))))


if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,TypeError,OSError,sqlite3.Error,UnicodeError):
        print('Legacy feedback migration blocked; preserve sources and inspect private approval.',file=sys.stderr);sys.exit(2)

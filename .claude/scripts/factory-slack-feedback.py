#!/usr/bin/env python3
"""Authenticated allowlisted Slack feedback; private capture, no spec self-approval."""
import argparse
from datetime import datetime, timezone
from decimal import Decimal
import importlib.util
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location('feedback',Path(__file__).with_name('factory-feedback.py'))
f = importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
spec = importlib.util.spec_from_file_location('report_state',Path(__file__).with_name('factory-git-state.py'))
state = importlib.util.module_from_spec(spec);spec.loader.exec_module(state)
require = f.require
COMMAND = re.compile(r'\Afactory (?P<op>feedback|hotfix) (?P<prs>#[1-9][0-9]*(?:,#[1-9][0-9]*)*) (?P<kind>defect|enhancement|requirement|priority|acceptance): (?P<text>[\s\S]+)\Z')


def private_paths(config):
    root=Path(config['private_root']);db=Path(config['runtime_database'])
    require(root.is_absolute() and root.resolve()==root and root.is_dir() and not root.is_symlink(), 'private feedback root must be canonical existing directory')
    info=root.stat();require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o700,'private feedback root owner/mode differs')
    implementation_roots=config.get('implementation_roots',[])
    require(isinstance(implementation_roots,list) and all(isinstance(item,str) and Path(item).is_absolute() for item in implementation_roots),'implementation roots invalid')
    for candidate in [Path(__file__).resolve().parents[2],*[Path(item).resolve() for item in implementation_roots]]:
        require(root!=candidate and candidate not in root.parents,'feedback state cannot live in implementation checkout')
    require(db.is_absolute() and db.parent==root and db.resolve()==db and not db.is_symlink(),'runtime database must be direct private-root file')
    if db.exists():
        info=db.stat();require(db.is_file() and info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'runtime database owner/mode differs')
    return root,db


def timestamp(value):
    require(isinstance(value,str) and len(value)<=20 and re.fullmatch(r'[0-9]+\.[0-9]{1,6}',value),'Slack source timestamp invalid')
    return Decimal(value)


def messages(client,config,now):
    start=f.digest.instant(config['feedback_start']);require(now.tzinfo is not None and start<=now,'feedback clock/start invalid')
    oldest=Decimal(str(start.timestamp()));latest=Decimal(str(now.timestamp()))
    cursor='';seen=set();sources={};result=[]
    for _ in range(100):
        body={'channel':config['destination'],'limit':100,'oldest':str(oldest),'latest':str(latest),'inclusive':True,'include_all_metadata':True}
        if cursor:body['cursor']=cursor
        page=client.call('conversations.history',body)
        require(isinstance(page.get('messages'),list),'feedback history unavailable')
        for message in page['messages']:
            require(isinstance(message,dict),'feedback history message malformed')
            if message.get('user') not in config['operators'] or message.get('bot_id') or message.get('subtype'):
                continue
            if message.get('thread_ts') and message['thread_ts']!=message.get('ts'):continue
            text=message.get('text')
            if not isinstance(text,str) or not text.startswith('factory '):continue
            require(message.get('type')=='message' and 0<len(text)<=20000,'feedback command type/size invalid')
            parsed=COMMAND.fullmatch(text);require(parsed is not None and parsed['text'].strip(),'malformed explicit feedback command')
            require(parsed['op']!='hotfix' or parsed['kind']=='defect','hotfix must request a defect repair')
            when=timestamp(message.get('ts'));require(oldest<=when<=latest,'feedback message outside requested window')
            source=f"slack:{config['team_id']}/{config['destination']}/{message['ts']}"
            if message.get('edited'):
                edit=message['edited'];require(isinstance(edit,dict) and edit.get('user')==message['user'],'feedback edit author differs')
                edited=timestamp(edit.get('ts'));require(when<=edited<=latest,'feedback edit timestamp invalid')
                source+=':edit:'+edit['ts']
            prs=[int(number[1:]) for number in parsed['prs'].split(',')]
            require(len(prs)<=100 and len(set(prs))==len(prs),'feedback PR references invalid')
            document={'repository':config['repository'],'source_ref':source,'reporter':message['user'],'text':text,
                      'kind':parsed['kind'],'pull_requests':prs}
            observation=(document,parsed['op']=='hotfix')
            if source in sources:
                require(sources[source]==observation,'conflicting duplicate Slack source');continue
            sources[source]=observation;result.append(observation)
            require(len(result)<=1000,'feedback capture batch bound exceeded')
        cursor=page.get('response_metadata',{}).get('next_cursor','')
        if not cursor:
            require(not page.get('has_more'),'feedback history incomplete');return result
        require(cursor not in seen,'feedback history cursor repeats');seen.add(cursor)
    raise ValueError('feedback history exceeds capture bound')


def run(config,api,client,now):
    require(config.get('enabled') is True and config.get('feedback_enabled') is True and api.repo==config['repository']==config['state_repository'],'Slack feedback disabled or foreign')
    root,db=private_paths(config)
    operators=config['operators'];require(isinstance(operators,list) and 0<len(operators)<=100 and len(set(operators))==len(operators) and all(isinstance(operator,str) and re.fullmatch(r'[UW][A-Z0-9]+',operator) for operator in operators),'explicit operator allowlist required')
    state.slack.preflight(client,config['team_id'],config['destination'])
    observations=messages(client,config,now)
    if not observations:return {'captured':0,'identities':[]}
    stream=state.hashlib.sha256(state.canonical([config['repository'],config['destination'],config['branch']]).encode()).hexdigest()
    checkpoint=state.GitState(api,config['state_branch'],stream,config.get('bootstrap_sha'),config.get('policy_approvals'))
    require(checkpoint.bytes is not None,'source report checkpoint missing')
    snapshot=json.loads(checkpoint.bytes,object_pairs_hook=f.digest.coordinator.contract.no_duplicate_keys)
    state.validate(snapshot,config['repository'],stream)
    verified=set()
    for document,_ in observations:
        choices=[]
        for batch in snapshot['tables']['digest_batches']:
            if batch['status']=='confirmed' and set(document['pull_requests'])<={pr['pr'] for pr in json.loads(batch['payload'])['merges']}:
                choices.append(batch)
        require(len(choices)==1,'feedback PRs must identify one confirmed delivered digest')
        batch=choices[0];document['digest_key']=batch['key']
        if batch['key'] not in verified:
            adapter=state.slack.transport(client,config,batch)
            require(adapter.lookup(batch['key']).get('receipt')==json.loads(batch['receipt']),'source digest remote receipt differs')
            verified.add(batch['key'])
    old_umask=os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(dir=root) as tmp:
            report=Path(tmp)/'report.sqlite'
            f.digest.Digest(report,config['repository'],config['destination'],config['start'],config['branch'])
            with sqlite3.connect(report) as projection:
                for table,columns in state.TABLES.items():
                    projection.execute(f'DELETE FROM {table}')
                    for row in snapshot['tables'][table]:
                        projection.execute(f'INSERT INTO {table}({",".join(columns)}) VALUES({",".join("?" for _ in columns)})',[row[column] for column in columns])
            feedback=f.Feedback(db,config['repository'])
            with feedback.store.transaction() as transaction:
                transaction.execute('CREATE TABLE IF NOT EXISTS feedback_ingress_identity (id INTEGER PRIMARY KEY, repository TEXT NOT NULL, team TEXT NOT NULL, destination TEXT NOT NULL)')
                identity=transaction.execute('SELECT repository,team,destination FROM feedback_ingress_identity WHERE id=1').fetchone()
                expected=(config['repository'],config['team_id'],config['destination'])
                require(identity is None or tuple(identity)==expected, 'feedback runtime repository/workspace/destination differs')
                if identity is None:transaction.execute('INSERT INTO feedback_ingress_identity VALUES(1,?,?,?)',expected)
            identities=feedback.intake_batch(report,[document for document,_ in observations])
            with feedback.store.transaction() as transaction:
                for identity,(document,urgent) in zip(identities,observations):
                    if urgent:
                        event={'type':'urgent-requested','source_ref':document['source_ref'],'operator':document['reporter'],'quality_gates_unchanged':True}
                        prior=[json.loads(row[0]) for row in transaction.execute('SELECT event FROM feedback_events WHERE feedback=?',(identity,))]
                        matching=[item for item in prior if item.get('type')=='urgent-requested']
                        require(not matching or matching==[event],'urgent request replay conflicts')
                        if not matching:feedback.event(transaction,identity,event)
            return {'captured':len(identities),'identities':identities}
    finally:os.umask(old_umask)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);args=parser.parse_args()
    config_path=Path(args.config)
    config=f.digest.coordinator.contract.load(config_path)
    root,_=private_paths(config)
    require(config_path.is_absolute() and config_path.parent==root and config_path.resolve()==config_path and not config_path.is_symlink() and config_path.stat().st_uid==os.getuid() and stat.S_IMODE(config_path.stat().st_mode)==0o600, 'feedback config must be protected private-root file')
    api=state.API(config['state_repository'],os.environ.get('FACTORY_REPORTING_STATE_TOKEN') or os.environ.get('GH_TOKEN'))
    result=run(config,api,state.slack.http_client(config),datetime.now(timezone.utc));print(state.canonical(result));return 0


if __name__=='__main__':
    try:sys.exit(main())
    except (ValueError,KeyError,TypeError,OSError,sqlite3.Error,subprocess.SubprocessError):
        print('Slack feedback capture blocked; inspect trusted configuration and source without exposing message text.',file=sys.stderr);sys.exit(2)

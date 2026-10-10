#!/usr/bin/env python3
"""Protected authenticated amendment approval and separate feature acceptance."""
import argparse
from datetime import datetime, timezone
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
COMMAND=re.compile(r'\Afactory (?P<op>approve|accept) (?P<identity>FB-[a-f0-9]{64}) version (?P<version>[1-9][0-9]*)(?: sha256:(?P<hash>[a-f0-9]{64}))?\Z')


def commands(client,config,now):
    require(now.tzinfo is not None,'control clock invalid')
    start=f.digest.instant(config['feedback_start']);require(start<=now,'control start invalid')
    oldest=ingress.Decimal(str(start.timestamp()));latest=ingress.Decimal(str(now.timestamp()))
    cursor='';seen=set();sources={}
    for _ in range(100):
        body={'channel':config['destination'],'limit':100,'oldest':str(oldest),'latest':str(latest),'inclusive':True,'include_all_metadata':True}
        if cursor:body['cursor']=cursor
        page=client.call('conversations.history',body);require(isinstance(page.get('messages'),list),'control history invalid')
        for message in page['messages']:
            require(isinstance(message,dict),'control message invalid')
            if message.get('user') not in config['operators'] or message.get('bot_id') or message.get('subtype'):continue
            if message.get('thread_ts') and message['thread_ts']!=message.get('ts'):continue
            text=message.get('text')
            if not isinstance(text,str) or not text.startswith(('factory approve','factory accept')):continue
            require(message.get('type')=='message' and not message.get('edited') and len(text)<300,'control command type/edit invalid')
            parsed=COMMAND.fullmatch(text);require(parsed is not None,'explicit control command invalid')
            require((parsed['op']=='approve')==bool(parsed['hash']),'approval requires hash; acceptance forbids hash')
            when=ingress.timestamp(message.get('ts'));require(oldest<=when<=latest,'control source outside window')
            source=f"slack:{config['team_id']}/{config['destination']}/{message['ts']}"
            document={'source_ref':source,'operator':message['user'],'operation':parsed['op'],'feedback':parsed['identity'],'version':int(parsed['version']),'sha256':parsed['hash']}
            require(source not in sources or sources[source]==document,'conflicting control source')
            sources[source]=document;require(len(sources)<=1000,'control batch bound exceeded')
        cursor=page.get('response_metadata',{}).get('next_cursor','')
        if not cursor:
            require(not page.get('has_more'),'control history incomplete')
            return [sources[key] for key in sorted(sources,key=lambda key:ingress.timestamp(key.rsplit('/',1)[1]))]
        require(cursor not in seen,'control pagination repeated');seen.add(cursor)
    raise ValueError('control history exceeds bound')


def apply(feedback,document,config):
    require(set(document)=={'source_ref','operator','operation','feedback','version','sha256'},'control document invalid')
    identity=document['feedback'];version=document['version'];encoded=f.canonical(document)
    policy={'repository':config['repository'],'specs':config['approved_specs'],'feedback_amendments':{}}
    require(document['operator'] in config['operators'] and type(version) is int and version>0,'control operator/version invalid')
    proposal=None
    if document['operation']=='approve':
        digest=document['sha256'];require(isinstance(digest,str) and re.fullmatch(r'[a-f0-9]{64}',digest),'approval hash invalid')
        proposal=config['amendment_proposals'][identity][digest]
        require(hashlib.sha256(f.canonical(proposal).encode()).hexdigest()==digest,'proposal differs from operator-approved hash')
        policy['feedback_amendments'][identity]=digest
    else:require(document['operation']=='accept' and document['sha256'] is None,'control operation invalid')
    with feedback.store.transaction() as db:
        db.execute('CREATE TABLE IF NOT EXISTS feedback_operator_commands(source TEXT PRIMARY KEY,document TEXT NOT NULL,status TEXT NOT NULL)')
        prior=db.execute('SELECT document,status FROM feedback_operator_commands WHERE source=?',(document['source_ref'],)).fetchone()
        require(prior is None or prior['document']==encoded,'control source replay conflicts')
        if prior is not None and prior['status']=='confirmed':return 'confirmed'
        row=feedback.row(db,identity)
        if proposal is not None:
            require(row['version'] in {version-1,version},'approval targets stale version')
            if row['version']==version:
                current=db.execute('SELECT document FROM feedback_amendments WHERE feedback=? AND version=?',(identity,version)).fetchone()
                require(current is not None and current[0]==f.canonical(proposal),'approval version belongs to another amendment')
        else:require(row['version']==version,'acceptance targets stale version')
        if prior is None:db.execute('INSERT INTO feedback_operator_commands VALUES(?,?,?)',(document['source_ref'],encoded,'pending'))
    if proposal is not None:
        require(feedback.plan(identity,proposal,policy,expected_version=version)==version,'approved version differs')
    else:feedback.accept(identity,document['operator'],document['source_ref'],expected_version=version)
    with feedback.store.transaction() as db:
        row=db.execute('SELECT document,status FROM feedback_operator_commands WHERE source=?',(document['source_ref'],)).fetchone()
        require(row is not None and row['document']==encoded,'control intent changed')
        if row['status']!='confirmed':
            feedback.event(db,identity,{'type':'operator-command','document':document})
            db.execute("UPDATE feedback_operator_commands SET status='confirmed' WHERE source=?",(document['source_ref'],))
    return 'confirmed'


def run(config,client,now):
    require(config.get('enabled') is True and config.get('feedback_control_enabled') is True,'operator control disabled')
    _,db=ingress.private_paths(config)
    operators=config['operators'];require(isinstance(operators,list) and 0<len(operators)<=100 and all(isinstance(item,str) and re.fullmatch(r'[UW][A-Z0-9]+',item) for item in operators) and len(set(operators))==len(operators),'operator allowlist invalid')
    require(db.is_file(),'existing private feedback runtime required')
    require(isinstance(config['approved_specs'],dict) and isinstance(config['amendment_proposals'],dict),'protected approval configuration invalid')
    ingress.state.slack.preflight(client,config['team_id'],config['destination'])
    documents=commands(client,config,now)
    feedback=f.Feedback(db,config['repository'])
    with feedback.store.transaction() as transaction:
        row=transaction.execute('SELECT repository,team,destination FROM feedback_ingress_identity WHERE id=1').fetchone()
        require(row is not None and tuple(row)==(config['repository'],config['team_id'],config['destination']),'operator runtime namespace differs')
    outcomes=[apply(feedback,document,config) for document in documents]
    return {'commands':len(outcomes),'confirmed':outcomes.count('confirmed')}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);args=parser.parse_args();path=Path(args.config)
    config=f.digest.coordinator.contract.load(path);root,_=ingress.private_paths(config)
    require(path.is_absolute() and path.parent==root and path.resolve()==path and not path.is_symlink() and path.stat().st_uid==os.getuid() and stat.S_IMODE(path.stat().st_mode)==0o600,'control config must be protected private-root file')
    print(f.canonical(run(config,ingress.state.slack.http_client(config),datetime.now(timezone.utc))))


if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,TypeError,OSError,sqlite3.Error):
        print('Operator feedback transition blocked; inspect private authority and receipts.',file=sys.stderr);sys.exit(2)

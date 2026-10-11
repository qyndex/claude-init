#!/usr/bin/env python3
"""Main-only encrypted Slack intake; never exports private database or raw messages."""
import argparse
from datetime import datetime,timezone
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys


def load(name, filename):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(filename))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


crypto=load('encrypted_feedback','factory-encrypted-feedback.py')
ingress=load('slack_feedback','factory-slack-feedback.py')
state=ingress.state
require=crypto.require


def run(config, api, client, secret, now):
    require(config.get('enabled') is True and config.get('feedback_enabled') is True,'hosted feedback disabled')
    require(config['repository']==config['state_repository']==api.repo,'foreign hosted feedback repository')
    binding=crypto.context(config['repository'],config['destination'],config['branch'],config['feedback_key_id'])
    report_stream=state.hashlib.sha256(state.canonical([config['repository'],config['destination'],config['branch']]).encode()).hexdigest()
    report=state.GitState(api,config['state_branch'],report_stream,config.get('bootstrap_sha'),config.get('policy_approvals'))
    require(report.bytes is not None,'confirmed reporting store required before feedback bootstrap')
    snapshot=json.loads(report.bytes,object_pairs_hook=crypto.pairs)
    state.validate(snapshot,config['repository'],report_stream)
    require(any(batch['status']=='confirmed' for batch in snapshot['tables']['digest_batches']),'confirmed digest required before feedback bootstrap')
    checkpoint=state.GitState(api,config['state_branch'],binding['stream'],config.get('feedback_bootstrap_sha'),config.get('policy_approvals'),bootstrap_existing=True)
    with crypto.private_database(checkpoint,secret,binding) as (root,path):
        private={**config,'private_root':str(root),'runtime_database':str(path),'implementation_roots':[str(Path(__file__).resolve().parents[2])]}
        result=ingress.run(private,api,client,now)
    return {'captured':result['captured'],'checkpoint':checkpoint.head}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);args=parser.parse_args()
    path=Path(args.config)
    require(path.is_absolute() and path.resolve()==path and path.is_file() and not path.is_symlink() and path.stat().st_uid==os.getuid() and stat.S_IMODE(path.stat().st_mode)==0o600,'hosted feedback config must be private canonical file')
    require(path.parent.stat().st_uid==os.getuid() and stat.S_IMODE(path.parent.stat().st_mode)==0o700,'hosted feedback config parent must be private')
    require(Path(__file__).resolve().parents[2] not in path.parents,'feedback configuration cannot live in candidate checkout')
    config=json.loads(path.read_text(),object_pairs_hook=crypto.pairs)
    secret=crypto.key(os.environ['FACTORY_FEEDBACK_STATE_KEY'])
    api=state.API(config['state_repository'],os.environ.get('FACTORY_REPORTING_STATE_TOKEN') or os.environ.get('GH_TOKEN'))
    result=run(config,api,state.slack.http_client(config),secret,datetime.now(timezone.utc))
    print(json.dumps(result,sort_keys=True))


if __name__=='__main__':
    try:main()
    except Exception:
        print('Hosted feedback blocked; reconcile protected state and configuration. Private data withheld.',file=sys.stderr)
        sys.exit(2)

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


def private_snapshots(config):
    """Capture protected locators before the ephemeral holder replaces their parent."""
    result={}
    if config.get('intake_config') is None:return result
    for field,maximum in [('intake_config',65536),('assessment_profile',8000000)]:
        if config.get(field) is None:continue
        path=Path(config[field]);parent=path.parent
        require(parent.is_absolute() and parent.resolve()==parent and parent.is_dir() and not parent.is_symlink()
                and parent.stat().st_uid==os.getuid() and stat.S_IMODE(parent.stat().st_mode)==0o700,
                'hosted snapshot parent must be canonical private directory')
        roots=[Path(__file__).resolve().parents[2],*[Path(item).resolve() for item in config.get('implementation_roots',[])]]
        require(all(path!=root and root not in path.parents for root in roots),'hosted snapshot cannot live in candidate checkout')
        result[field]=ingress.captured_file(path,maximum,True)
    return result


def run(config, api, client, secret, now):
    require(config.get('enabled') is True and config.get('feedback_enabled') is True,'hosted feedback disabled')
    require(config['repository']==config['state_repository']==api.repo,'foreign hosted feedback repository')
    binding=crypto.context(config['repository'],config['destination'],config['branch'],config['feedback_key_id'])
    report_stream=state.hashlib.sha256(state.canonical([config['repository'],config['destination'],config['branch']]).encode()).hexdigest()
    report=state.GitState(api,config['state_branch'],report_stream,config.get('bootstrap_sha'),config.get('policy_approvals'),state_view=config.get('state_view'))
    require(report.bytes is not None,'confirmed reporting store required before feedback bootstrap')
    snapshot=json.loads(report.bytes,object_pairs_hook=crypto.pairs)
    state.validate(snapshot,config['repository'],report_stream)
    require(any(batch['status']=='confirmed' for batch in snapshot['tables']['digest_batches']),'confirmed digest required before feedback bootstrap')
    checkpoint=state.GitState(api,config['state_branch'],binding['stream'],config.get('feedback_bootstrap_sha'),config.get('policy_approvals'),bootstrap_existing=True,state_view=config.get('state_view'))
    source_root=Path(__file__).resolve().parents[2];roots=[str(source_root)]
    if config.get('intake_config') is not None:
        declared=config.get('implementation_roots',[])
        require(isinstance(declared,list) and all(isinstance(item,str) and Path(item).is_absolute()
                and Path(item).resolve()==Path(item) and Path(item).is_dir() and not Path(item).is_symlink()
                for item in declared),'hosted candidate roots must be canonical existing directories')
        roots=sorted(set(roots+declared))
    snapshots=private_snapshots(config);barriers=[]
    with crypto.private_database(checkpoint,secret,binding,checkpoint_ready=barriers.append) as (root,path):
        private={**config,'private_root':str(root),'runtime_database':str(path),'implementation_roots':roots}
        for field,raw in snapshots.items():
            target=root/(field+'.json');target.write_bytes(raw);target.chmod(0o600);private[field]=str(target)
        def durable_barrier():
            try:barriers[0]()
            except Exception as error:raise RuntimeError('hosted encrypted intent checkpoint failed') from error
        result=ingress.run(private,api,client,now,checkpoint_barrier=durable_barrier)
    return {'captured':result['captured'],'checkpoint':checkpoint.head}


_failure_stage = 'startup'

def main():
    global _failure_stage
    _failure_stage = 'config'
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);args=parser.parse_args()
    path=Path(args.config)
    require(path.is_absolute() and path.resolve()==path and path.is_file() and not path.is_symlink() and path.stat().st_uid==os.getuid() and stat.S_IMODE(path.stat().st_mode)==0o600,'hosted feedback config must be private canonical file')
    require(path.parent.stat().st_uid==os.getuid() and stat.S_IMODE(path.parent.stat().st_mode)==0o700,'hosted feedback config parent must be private')
    require(Path(__file__).resolve().parents[2] not in path.parents,'feedback configuration cannot live in candidate checkout')
    config=json.loads(path.read_text(),object_pairs_hook=crypto.pairs)
    _failure_stage = 'key-format'
    secret=crypto.key(os.environ['FACTORY_FEEDBACK_STATE_KEY'])
    _failure_stage = 'transport'
    flag=os.environ.get('FACTORY_REPORTING_APP_WRITER_ENABLED','false')
    require(flag in ('true','false'),'reporting writer flag invalid')
    if flag=='true':
        transport=load('feedback_transport','factory-reporting-transport.py')
        api=transport.create_api(os.environ)
        require(api.repo==config['repository']==config['state_repository'],'reporting selected API repository differs')
        _failure_stage = 'protected-context'
        config=transport.attach_reporting_context(config)
    else:
        api=state.API(config['state_repository'],os.environ.get('FACTORY_REPORTING_STATE_TOKEN') or os.environ.get('GH_TOKEN'))
    _failure_stage = 'checkpoint-or-delivery'
    result=run(config,api,state.slack.http_client(config),secret,datetime.now(timezone.utc))
    print(json.dumps(result,sort_keys=True))


if __name__=='__main__':
    try:main()
    except Exception as error:
        print('Hosted feedback blocked; reconcile protected state and configuration. Private data withheld.',file=sys.stderr)
        try:
            diagnostic=load('feedback_safe_diagnostic','factory-reporting-transport.py')
            print(json.dumps(diagnostic.safe_diagnostic(_failure_stage,error),sort_keys=True),file=sys.stderr)
        except Exception:
            print('{"error_class":"Exception","http_status":null,"stage":"diagnostic-unavailable"}',file=sys.stderr)
        sys.exit(2)

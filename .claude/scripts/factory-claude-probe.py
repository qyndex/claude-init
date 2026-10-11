#!/usr/bin/env python3
"""Bounded tool-free native Claude probe; no API fallback or independent verdict."""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

spec=importlib.util.spec_from_file_location('supervisor',Path(__file__).with_name('factory-supervisor.py'))
supervisor=importlib.util.module_from_spec(spec);spec.loader.exec_module(supervisor)
FLAGS={'--safe-mode','--tools','--strict-mcp-config','--mcp-config','--no-session-persistence','--disable-slash-commands','--model','--output-format','--print'}
CAPABILITIES=['foreground','model-selection','structured-output','tool-free','separate-run']


bounded_spec=importlib.util.spec_from_file_location('bounded_process',Path(__file__).with_name('factory-bounded-process.py'))
bounded=importlib.util.module_from_spec(bounded_spec);bounded_spec.loader.exec_module(bounded)

def call(binary, arguments, environment, directory):
    result=bounded.run([str(binary),*arguments],cwd=directory,env=environment,timeout=8)
    if result.returncode!=0:raise ValueError('native probe failed')
    return result.stdout


def observe(binary, model, auth_method, subscription_type, live=False, credential_kind='implementation'):
    result={'schema_version':1,'available':False,'model':model,'capabilities':[],'version':'unavailable','quota':'unknown','reset_at':None,'estimated_api_usd':None,'actual_spend_usd':None}
    try:
        if binary.resolve()!=binary or not binary.is_file() or not os.access(binary,os.X_OK) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:/-]{0,159}',model):return result
        if any(os.environ.get(name) for name in ('ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY')):return result
        environment=supervisor.worker_environment(os.environ)
        if credential_kind=='review':
            environment.pop('CLAUDE_CODE_OAUTH_TOKEN',None)
            dedicated=os.environ.get('FACTORY_REVIEW_CLAUDE_OAUTH_TOKEN')
            if dedicated:environment['CLAUDE_CODE_OAUTH_TOKEN']=dedicated
        with tempfile.TemporaryDirectory(prefix='factory-model-probe-') as directory:
            version=call(binary,['--version'],environment,directory).decode().strip()
            if not 0<len(version)<=200:return result
            result['version']=version
            help_text=call(binary,['--help'],environment,directory).decode()
            if not all(flag in help_text for flag in FLAGS):return result
            result['capabilities']=CAPABILITIES
            auth=json.loads(call(binary,['auth','status','--json'],environment,directory))
            if auth.get('loggedIn') is not True or auth.get('apiProvider')!='firstParty' or auth.get('authMethod')!=auth_method or auth.get('subscriptionType')!=subscription_type:return result
            if not live:return result
            response=json.loads(call(binary,['--safe-mode','--tools','','--strict-mcp-config','--mcp-config','{"mcpServers":{}}','--no-session-persistence','--disable-slash-commands','--model',model,'--output-format','json','--print','Reply OK.'],environment,directory))
            if response.get('type')!='result' or response.get('subtype')!='success' or response.get('is_error') is not False:return result
            usage=response.get('modelUsage')
            if not isinstance(usage,dict) or set(usage)!={model}:return result
            estimate=response.get('total_cost_usd')
            if estimate is not None and (type(estimate) not in {float,int} or not math.isfinite(estimate) or not 0<=estimate<=1000000):return result
            result['available']=True;result['estimated_api_usd']=estimate
    except (OSError,ValueError,TypeError,AttributeError,subprocess.SubprocessError):pass
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--binary',required=True);parser.add_argument('--model',required=True);parser.add_argument('--auth-method',required=True);parser.add_argument('--subscription-type',required=True);parser.add_argument('--credential-kind',choices=['implementation','review'],default='implementation');parser.add_argument('--live',action='store_true');args=parser.parse_args()
    subscription=None if args.subscription_type=='unknown' else args.subscription_type
    print(json.dumps(observe(Path(args.binary),args.model,args.auth_method,subscription,args.live,args.credential_kind),sort_keys=True,allow_nan=False))


if __name__=='__main__':main()

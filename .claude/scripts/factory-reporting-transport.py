#!/usr/bin/env python3
"""Fixed reporting credential roles with one bounded invocation transport budget."""
import base64
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import quote


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


state = module('reporting_state_transport', 'factory-git-state.py')
process = state._batch_process
require = state.require
MAX_RESPONSE = 2097152
MAX_BYTES = 33554432
MAX_CALLS = 2048


def encode(value):
    stack = [value]; nodes = size = 0
    while stack:
        item = stack.pop(); nodes += 1
        if type(item) is dict:
            require(all(type(key) is str for key in item), 'reporting JSON keys invalid')
            require(nodes+len(stack)+2*len(item) <= 32768, 'reporting JSON node bound')
            for key, child in item.items():stack.extend((key, child))
        elif type(item) is list:
            require(nodes+len(stack)+len(item) <= 32768, 'reporting JSON node bound')
            stack.extend(item)
        elif type(item) is str:
            require(len(item) <= MAX_RESPONSE, 'reporting JSON string bound')
            try:size += len(item.encode())
            except UnicodeError as error:raise ValueError('reporting JSON UTF8 invalid') from error
        else:
            require(item is None or type(item) in (bool, int, float), 'reporting JSON type invalid')
            if type(item) is int:require(abs(item)<2**63, 'reporting JSON integer bound')
            if type(item) is float:require(math.isfinite(item), 'reporting JSON number invalid')
        require(nodes<=32768 and size<=MAX_RESPONSE, 'reporting JSON bound')
    raw = state.canonical(value).encode()
    require(len(raw)<=MAX_RESPONSE, 'reporting JSON byte bound')
    return raw


class Budget:
    def __init__(self):self.calls = self.bytes = 0
    def begin(self):
        require(self.calls < MAX_CALLS and self.bytes < MAX_BYTES, 'reporting invocation capacity gap')
        self.calls += 1
    def observe(self, size):
        require(type(size) is int and 0 < size <= MAX_RESPONSE, 'reporting response byte accounting invalid')
        self.bytes += size
        require(self.bytes <= MAX_BYTES, 'reporting invocation capacity gap')


def build_config(env):
    require(type(env) is dict or isinstance(env, os._Environ), 'reporting protected environment required')
    repo = env.get('GITHUB_REPOSITORY')
    require(type(repo) is str and len(repo)<=200 and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repo)
            and all(part not in ('.','..') for part in repo.split('/')), 'reporting repository invalid')
    require(env.get('FACTORY_REPORTING_STATE_REPOSITORY') == repo, 'reporting state repository differs')
    enabled = env.get('FACTORY_REPORTING_APP_WRITER_ENABLED', 'false')
    require(type(enabled) is str and enabled in ('true','false'), 'reporting writer flag invalid')
    app_id = None
    if enabled == 'true':
        identity = env.get('FACTORY_REPORTING_APP_ID')
        require(type(identity) is str and re.fullmatch(r'[1-9][0-9]{0,18}',identity) and int(identity)<2**63,
                'reporting App identity required')
        app_id = int(identity)
    return {'repository':repo, 'writer_mode':'app' if enabled=='true' else 'legacy', 'writer_app_id':app_id}


def create_api(env):
    config = build_config(env)
    source = env.get('GH_TOKEN')
    writer = env.get('FACTORY_REPORTING_APP_TOKEN') if config['writer_mode']=='app' else env.get('FACTORY_REPORTING_STATE_TOKEN') or source
    require(type(source) is str and 0<len(source)<=16384 and type(writer) is str and 0<len(writer)<=16384,
            'reporting selected credentials required; no App fallback')
    return RoutedAPI(config['repository'], source, writer)


class RoutedAPI:
    def __init__(self, repository, source_token, state_token):
        require(type(repository) is str and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository)
                and all(part not in ('.','..') for part in repository.split('/')), 'reporting repository invalid')
        require(all(type(token) is str and 0<len(token)<=16384 for token in (source_token,state_token)), 'reporting credentials required')
        self.repo = repository; self._source = source_token; self._state = state_token; self.budget = Budget()

    def _route(self, path, method, payload, raw):
        require(type(path) is str and len(path)<=4096 and re.fullmatch(r'[A-Za-z0-9._~/?=&%:+-]+',path), 'reporting endpoint invalid')
        pathname, _, query = path.partition('?'); root = 'repos/'+self.repo
        require(pathname==root or pathname.startswith(root+'/'), 'reporting foreign endpoint')
        require('%' not in pathname.replace('%2F','') and '..' not in pathname and '//' not in pathname
                and '%' not in query.replace('%2F','').replace('%3A',''), 'reporting encoded endpoint invalid')
        tail = pathname[len(root):]
        source = tail=='/pulls' or any(tail.startswith('/'+kind+'/') for kind in ('actions','pulls','contents'))
        if source:
            require(method=='GET' and payload is None, 'reporting source API is read only')
            require(not raw or re.fullmatch(r'/actions/artifacts/[1-9][0-9]*/zip',tail), 'reporting raw endpoint invalid')
            return self._source
        require(not raw, 'reporting state raw response forbidden')
        read = tail=='' or tail.startswith(('/git/','/rulesets/','/rules/branches/','/compare/')) or tail=='/commits'
        if method=='GET':
            require(payload is None and read, 'reporting state read endpoint invalid')
        elif method=='POST':
            require(tail in ('/git/blobs','/git/trees','/git/commits') and not query and type(payload) is dict,
                    'reporting state creation endpoint invalid')
        elif method=='PATCH':
            require(tail.startswith('/git/refs/heads/') and not query and type(payload) is dict
                    and set(payload)=={'sha','force'} and state.state_paths.valid_hash(payload['sha'],40)
                    and payload['force'] is False, 'reporting nonforce update required')
        else:raise ValueError('reporting method forbidden')
        return self._state

    def _once(self, path, method, payload, raw):
        token = self._route(path, method, payload, raw)
        encoded = encode(payload) if payload is not None else None
        self.budget.begin()
        env = {key:os.environ[key] for key in ('PATH','HOME') if key in os.environ}
        env.update(GH_TOKEN=token,GH_HOST='github.com',GH_PROMPT_DISABLED='1',GH_NO_UPDATE_NOTIFIER='1',LANG='C',LC_ALL='C')
        command = ['gh','api','--hostname','github.com','--method',method,path]
        with tempfile.TemporaryFile() as source:
            if encoded is not None:source.write(encoded);source.seek(0);command += ['--input','-']
            result = process.run(command,env=env,cwd=Path.cwd(),timeout=60,limit=MAX_RESPONSE,
                                 aggregate_limit=MAX_RESPONSE,stdin=source if encoded is not None else None)
        self.budget.observe(len(result.stdout))
        require(result.returncode==0, 'reporting API failed; reconcile authoritative state before retry')
        if raw:return result.stdout
        try:return json.loads(result.stdout,object_pairs_hook=state.digest.coordinator.contract.no_duplicate_keys)
        except (ValueError,UnicodeError,RecursionError) as error:raise ValueError('reporting response JSON invalid') from error

    def request(self, path, method='GET', payload=None, *, raw=False, paginate=False):
        require(type(raw) is bool and type(paginate) is bool, 'reporting response options invalid')
        if not paginate:return self._once(path,method,payload,raw)
        self._route(path,method,payload,raw)
        require(method=='GET' and payload is None and not raw and re.search(r'(?:[?&])page=',path) is None, 'reporting pagination selector invalid')
        require(re.search(r'(?:[?&])per_page=(?!100(?:&|$))',path) is None, 'reporting pagination page size differs')
        pages=[]; expected=None; observed=0
        for number in range(1,11):
            target=path+('&' if '?' in path else '?')+('' if 'per_page=' in path else 'per_page=100&')+'page='+str(number)
            value=self._once(target,method,None,False);pages.append(value)
            if type(value) is list:items=value
            else:
                require(type(value) is dict, 'reporting pagination response invalid')
                if 'total_count' in value:
                    total=value['total_count']
                    require(type(total) is int and 0<=total<1000 and (expected is None or expected==total), 'reporting pagination count/capacity gap')
                    expected=total
                fields=[key for key in ('artifacts','workflow_runs','jobs','check_runs') if key in value]
                require(len(fields)==1 and type(value[fields[0]]) is list, 'reporting pagination items invalid')
                items=value[fields[0]]
            require(len(items)<=100, 'reporting pagination page bound')
            observed+=len(items)
            if len(items)<100:
                require(expected is None or observed==expected, 'reporting pagination count gap')
                return pages
        raise ValueError('reporting pagination capacity gap; no completeness claim')

    def get(self, path):
        many = '/rules/branches/' in path or '/actions/runs?' in path or path.endswith('/files')
        value = self.request(path,paginate=many)
        if not many:return value
        field='workflow_runs' if '/actions/runs?' in path else None
        return [item for page in value for item in (page[field] if field else page)]

    def source(self, path, sha):
        require(type(path) is str and len(path)<=512 and not path.startswith('/') and '..' not in path
                and state.state_paths.valid_hash(sha,40), 'reporting immutable source selector invalid')
        value=self.request('repos/'+self.repo+'/contents/'+quote(path,safe='/')+'?ref='+sha)
        require(type(value) is dict and value.get('encoding')=='base64' and type(value.get('content')) is str,
                'reporting source unavailable')
        try:return base64.b64decode(''.join(value['content'].split()),validate=True)
        except ValueError as error:raise ValueError('reporting source encoding invalid') from error

    def _batch(self, role, name, repository_id, selectors):
        # Only these two reviewed fixed query capabilities exist; no generic POST.
        self.budget.begin()
        client=state.API(self.repo,self._state if role=='state' else self._source)
        value=getattr(client,name)(repository_id,selectors)
        require(type(value) is dict and type(value.get('calls')) is int and value['calls']==1,
                'reporting batch call accounting invalid')
        self.budget.observe(value.get('raw_bytes'))
        return value

    def read_blobs(self, repository_id, entries):
        return self._batch('state','read_blobs',repository_id,entries)

    def read_pull_requests(self, repository_id, numbers):
        return self._batch('source','read_pull_requests',repository_id,numbers)

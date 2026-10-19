#!/usr/bin/env python3
"""Hosted reporting checkpoints on a data-only Git branch; no candidate execution."""
import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
from urllib.parse import quote
import uuid

spec = importlib.util.spec_from_file_location('slack', Path(__file__).with_name('factory-slack-digest.py'))
slack = importlib.util.module_from_spec(spec); spec.loader.exec_module(slack)
digest = slack.digest
require = digest.require
canonical = digest.canonical
TABLES = {
    'digest_cursors': ('stream', 'cutoff'),
    'digest_origins': ('stream', 'origin'),
    'digest_batches': ('key', 'stream', 'cutoff', 'payload', 'status', 'receipt'),
}
PR_TABLES = {
    'reporting_pr_scans': ('stream','repository','branch','origin','until','phase','next_page'),
    'reporting_pr_pages': ('stream','page','fingerprint','count','payload'),
}
PR_SQL = (
 'CREATE TABLE IF NOT EXISTS reporting_pr_scans(stream TEXT PRIMARY KEY,repository TEXT NOT NULL,branch TEXT NOT NULL,origin TEXT NOT NULL,until TEXT NOT NULL,phase TEXT NOT NULL,next_page INTEGER NOT NULL)',
 'CREATE TABLE IF NOT EXISTS reporting_pr_pages(stream TEXT NOT NULL,page INTEGER NOT NULL,fingerprint TEXT NOT NULL,count INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(stream,page))',
)
MAX_STATE = 8_000_000


paths_spec = importlib.util.spec_from_file_location('state_paths', Path(__file__).with_name('factory-state-paths.py'))
state_paths = importlib.util.module_from_spec(paths_spec); paths_spec.loader.exec_module(state_paths)

def git_hash(blob):
    return hashlib.sha1(b'blob ' + str(len(blob)).encode() + b'\0' + blob).hexdigest()


_batch_spec = importlib.util.spec_from_file_location('state_batch_process', Path(__file__).with_name('factory-bounded-process.py'))
_batch_process = importlib.util.module_from_spec(_batch_spec); _batch_spec.loader.exec_module(_batch_process)

class API:
    def __init__(self, repository, token):
        require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository or ''), 'state repository required')
        require(isinstance(token, str) and bool(token), 'state credential required')
        self.repo = repository; self.token = token

    def request(self, path, method='GET', payload=None):
        require(path == f'repos/{self.repo}' or path.startswith(f'repos/{self.repo}/'), 'foreign state API path')
        env = dict(os.environ); env['GH_TOKEN'] = self.token
        command = ['gh', 'api', '--hostname', 'github.com', '--method', method, path]
        if payload is not None:
            command += ['--input', '-']
        result = subprocess.run(command, input=canonical(payload).encode() if payload is not None else None,
                                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        require(result.returncode == 0, 'state API failed; reconcile authoritative branch before retry')
        require(len(result.stdout) <= MAX_STATE * 2, 'state API response too large')
        return json.loads(result.stdout, object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)


    def read_blobs(self, repository_id, entries):
        """Bounded fixed query for immutable archive JSON leaves; not origin proof."""
        require(type(repository_id) is int and 0 < repository_id < 2**63, 'blob batch repository identity invalid')
        require(type(entries) is list and 0 < len(entries) <= 32, 'blob batch selector bound invalid')
        selected = {}; variables = {}; declarations = []; aliases = []
        owner, name = self.repo.split('/')
        variables.update(owner=owner, name=name)
        for index, item in enumerate(entries):
            require(type(item) is dict and set(item) == {'path', 'sha', 'size'} and type(item['path']) is str and len(item['path']) <= 512 and item['path'].startswith('receipt-archive/') and type(item['sha']) is str and len(item['sha']) == 40 and type(item['size']) is int and 0 < item['size'] <= 1048576, 'blob batch archive selector invalid')
            state_paths.validate_entry(dict(item, type='blob', mode='100644'))
            require(item['sha'] not in selected, 'blob batch selector duplicated')
            selected[item['sha']] = item
            declarations.append('$oid'+str(index)+':GitObjectID!'); variables['oid'+str(index)] = item['sha']
            aliases.append('o'+str(index)+':object(oid:$oid'+str(index)+'){__typename ... on Blob{oid byteSize isBinary isTruncated text}}')
        require(sum(item['size'] for item in entries) <= 1048576, 'blob batch declared bytes exceed bound')
        query = 'query ReceiptBlobs($owner:String!,$name:String!,'+','.join(declarations)+'){repository(owner:$owner,name:$name,followRenames:false){databaseId nameWithOwner '+' '.join(aliases)+'}}'
        payload = canonical({'query': query, 'variables': variables}).encode()
        require(len(payload) <= 16384, 'blob batch request bytes exceed bound')
        env = {key: os.environ[key] for key in ('PATH', 'HOME') if key in os.environ}
        env.update(GH_TOKEN=self.token, GH_HOST='github.com', GH_PROMPT_DISABLED='1', GH_NO_UPDATE_NOTIFIER='1', LANG='C', LC_ALL='C')
        with tempfile.TemporaryFile() as source:
            source.write(payload); source.seek(0)
            result = _batch_process.run(['gh', 'api', '--hostname', 'github.com', '--method', 'POST', 'graphql', '--input', '-'],
                                        env=env, cwd=Path.cwd(), timeout=60, limit=2097152, aggregate_limit=2097152, stdin=source)
        require(result.returncode == 0, 'blob batch API failed; no fallback')
        try:
            value = json.loads(result.stdout, object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
        except (ValueError, UnicodeError, RecursionError) as error:
            raise ValueError('blob batch response JSON invalid') from error
        require(type(value) is dict and set(value) == {'data'} and type(value['data']) is dict and set(value['data']) == {'repository'}, 'blob batch partial/error response')
        repository = value['data']['repository']; expected = {'databaseId', 'nameWithOwner'} | {'o'+str(i) for i in range(len(entries))}
        require(type(repository) is dict and set(repository) == expected and type(repository['databaseId']) is int and repository['databaseId'] == repository_id and repository['nameWithOwner'] == self.repo, 'blob batch repository/aliases differ')
        blobs = {}
        for index, item in enumerate(entries):
            blob = repository['o'+str(index)]
            require(type(blob) is dict and set(blob) == {'__typename', 'oid', 'byteSize', 'isBinary', 'isTruncated', 'text'} and blob['__typename'] == 'Blob' and blob['oid'] == item['sha'] and type(blob['byteSize']) is int and blob['byteSize'] == item['size'] and blob['isBinary'] is False and blob['isTruncated'] is False and type(blob['text']) is str, 'blob batch object identity/shape differs')
            try:
                raw = blob['text'].encode('utf-8')
            except UnicodeError as error:
                raise ValueError('blob batch UTF8 invalid') from error
            require(len(raw) == item['size'] and git_hash(raw) == item['sha'], 'blob batch bytes differ')
            blobs[item['sha']] = {'sha': item['sha'], 'encoding': 'base64', 'size': len(raw), 'content': base64.b64encode(raw).decode('ascii')}
        require(len(canonical(blobs).encode()) <= 2097152, 'blob batch normalized memory exceeds bound')
        return {'blobs': blobs, 'calls': 1, 'raw_bytes': len(result.stdout)}


    def read_pull_requests(self, repository_id, numbers):
        """Fresh bounded merge observations; never an immutable/persistent cache."""
        require(type(repository_id) is int and 0 < repository_id < 2**63, 'PR batch repository identity invalid')
        require(type(numbers) is list and 0 < len(numbers) <= 32 and all(type(n) is int and 0 < n <= 2147483647 for n in numbers) and len(set(numbers)) == len(numbers), 'PR batch selectors invalid')
        owner, name = self.repo.split('/'); variables = {'owner':owner,'name':name}; declarations = []; aliases = []
        for index, number in enumerate(numbers):
            declarations.append('$n'+str(index)+':Int!');variables['n'+str(index)]=number
            aliases.append('p'+str(index)+':pullRequest(number:$n'+str(index)+'){number merged mergedAt mergeCommit{oid} baseRepository{databaseId nameWithOwner}}')
        query='query ReceiptPullRequests($owner:String!,$name:String!,'+','.join(declarations)+'){repository(owner:$owner,name:$name,followRenames:false){databaseId nameWithOwner '+' '.join(aliases)+'}}'
        payload=canonical({'query':query,'variables':variables}).encode();require(len(payload)<=16384,'PR batch request bytes exceed bound')
        env={key:os.environ[key] for key in ('PATH','HOME') if key in os.environ}
        env.update(GH_TOKEN=self.token,GH_HOST='github.com',GH_PROMPT_DISABLED='1',GH_NO_UPDATE_NOTIFIER='1',LANG='C',LC_ALL='C')
        with tempfile.TemporaryFile() as source:
            source.write(payload);source.seek(0)
            result=_batch_process.run(['gh','api','--hostname','github.com','--method','POST','graphql','--input','-'],env=env,cwd=Path.cwd(),timeout=60,limit=2097152,aggregate_limit=2097152,stdin=source)
        require(result.returncode==0,'PR batch API failed; no fallback')
        try:value=json.loads(result.stdout,object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
        except (ValueError,UnicodeError,RecursionError) as error:raise ValueError('PR batch response JSON invalid') from error
        require(type(value) is dict and set(value)=={'data'} and type(value['data']) is dict and set(value['data'])=={'repository'},'PR batch partial/error response')
        repository=value['data']['repository'];expected={'databaseId','nameWithOwner'}|{'p'+str(i) for i in range(len(numbers))}
        require(type(repository) is dict and set(repository)==expected and type(repository['databaseId']) is int and repository['databaseId']==repository_id and repository['nameWithOwner']==self.repo,'PR batch repository/aliases differ')
        observations={}
        for index,number in enumerate(numbers):
            pr=repository['p'+str(index)]
            require(type(pr) is dict and set(pr)=={'number','merged','mergedAt','mergeCommit','baseRepository'} and type(pr['number']) is int and pr['number']==number and pr['merged'] is True,'PR batch merge identity differs')
            commit=pr['mergeCommit'];base=pr['baseRepository'];time=pr['mergedAt']
            require(type(commit) is dict and set(commit)=={'oid'} and state_paths.valid_hash(commit['oid'],40),'PR batch merge commit differs')
            require(type(base) is dict and set(base)=={'databaseId','nameWithOwner'} and type(base['databaseId']) is int and base['databaseId']==repository_id and base['nameWithOwner']==self.repo,'PR batch base repository differs')
            require(time is None or (type(time) is str and len(time)<=40 and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})',time) is not None and (time.endswith('Z') or (int(time[-5:-3])<24 and int(time[-2:])<60))),'PR batch timestamp shape invalid')
            if time is not None:
                try:datetime.fromisoformat(time.replace('Z','+00:00'))
                except (ValueError,OverflowError) as error:raise ValueError('PR batch timestamp invalid') from error
            observations[number]={'number':number,'merged':True,'merged_at':time,'merge_commit_sha':commit['oid'],'base':{'repo':{'id':repository_id,'full_name':self.repo}}}
        require(len(canonical(observations).encode())<=2097152,'PR batch normalized memory exceeds bound')
        return {'pull_requests':observations,'calls':1,'raw_bytes':len(result.stdout)}


POLICY_FIELDS = {'id', 'name', 'target', 'source_type', 'source', 'enforcement',
                 'conditions', 'rules', 'node_id', 'created_at', 'updated_at'}


def policy_projection(policy):
    require(POLICY_FIELDS <= set(policy), 'state policy metadata incomplete')
    projection = {key: policy[key] for key in POLICY_FIELDS}
    for key in ('created_at', 'updated_at'):
        projection[key] = digest.stamp(digest.instant(projection[key]))
    return projection


def attest_policy(api, identity, now=None):
    now = now or datetime.now(timezone.utc)
    policy = api.request(f'repos/{api.repo}/rulesets/{identity}')
    require(policy.get('id') == identity and policy.get('source_type') == 'Repository' and
            policy.get('source') == api.repo and policy.get('target') == 'branch' and
            policy.get('enforcement') == 'active' and policy.get('bypass_actors') == [],
            'operator must observe an active repository policy with an explicit empty bypass list')
    projection = policy_projection(policy)
    updated = digest.instant(projection['updated_at'])
    # Observe after the timestamp has settled; subsequent server-side changes invalidate approval.
    require((now - updated).total_seconds() >= 60, 'state policy must settle for 60 seconds before approval')
    return {'schema_version': 1, 'repository': api.repo, 'ruleset_id': identity,
            'policy_sha256': hashlib.sha256(canonical(projection).encode()).hexdigest(),
            'policy_updated_at': projection['updated_at'], 'observed_at': digest.stamp(now),
            'bypass_actors': []}


def verify_policy(policy, repository, identity, approvals=None, now=None):
    require(policy.get('enforcement') == 'active', 'state protection disabled or bypassable')
    if 'bypass_actors' in policy:
        require(policy['bypass_actors'] == [], 'state protection disabled or bypassable')
        return
    require(isinstance(approvals, dict) and str(identity) in approvals,
            'state bypass actors hidden; protected operator approval required')
    approval = approvals[str(identity)]
    require(isinstance(approval, dict) and set(approval) == {'schema_version', 'repository',
            'ruleset_id', 'policy_sha256', 'policy_updated_at', 'observed_at', 'bypass_actors'} and
            type(approval['schema_version']) is int and approval['schema_version'] == 1 and
            approval['repository'] == repository and type(approval['ruleset_id']) is int and
            approval['ruleset_id'] == identity and approval['bypass_actors'] == [],
            'state policy approval missing or mismatched')
    projection = policy_projection(policy)
    require(projection['id'] == identity and projection['target'] == 'branch' and
            projection['source_type'] == 'Repository' and projection['source'] == repository and
            approval['policy_updated_at'] == projection['updated_at'] and
            approval['policy_sha256'] == hashlib.sha256(canonical(projection).encode()).hexdigest(),
            'state policy changed since operator approval')
    observed = digest.instant(approval['observed_at'])
    updated = digest.instant(projection['updated_at'])
    require((observed - updated).total_seconds() >= 60 and observed <= (now or datetime.now(timezone.utc)),
            'state policy approval clock invalid')


def state_view_config(value):
    """Select an origin protocol, never accept caller checkpoint/coverage claims."""
    if value is None:return None
    require(type(value) is dict and set(value)=={'mode','approval_path'} and value['mode']=='archive'
            and type(value['approval_path']) is str and 0<len(value['approval_path'])<=4096,
            'protected state view configuration invalid')
    path=Path(value['approval_path'])
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink(), 'protected state view path invalid')
    return dict(value)


class _ProtectedStateReader:
    """One invocation, exact immutable cache only; mutable origin always reread."""
    def __init__(self, api):
        self.source=api;self.repo=api.repo;self.calls=self.consumed=0;self.cache={}
    def request(self, path, method='GET', payload=None):
        root='repos/'+self.repo
        require(method=='GET' and payload is None and type(path) is str
                and (path==root or path.startswith(root+'/')), 'protected state view must be read-only')
        immutable=any(path.startswith(root+'/git/'+kind+'/') and state_paths.valid_hash(path.rsplit('/',1)[1],40)
                      for kind in ('commits','trees','blobs'))
        if immutable and path in self.cache:return json.loads(self.cache[path])
        require(self.calls<2048,'protected state view capacity gap');self.calls+=1
        value=self.source.request(path);raw=canonical(value).encode();self.consumed+=len(raw)
        require(len(raw)<=2097152 and self.consumed<=33554432,'protected state view capacity gap')
        if immutable:self.cache[path]=raw
        return value


class GitState:
    def __init__(self, api, branch, stream, bootstrap_sha=None, policy_approvals=None, *, bootstrap_existing=False, state_view=None):
        require(type(bootstrap_existing) is bool, "invalid checkpoint bootstrap mode")
        require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', branch or '') and '..' not in branch and not branch.endswith('/'), 'state branch invalid')
        require(digest.coordinator.contract.digest(stream, 64), 'state stream invalid')
        self.api = api; self.root = f'repos/{api.repo}'; self.branch = branch
        self.state_view = state_view_config(state_view)
        if self.state_view is not None:
            archive_spec=importlib.util.spec_from_file_location('reporting_archive_view',Path(__file__).with_name('factory-receipt-archive.py'))
            self.archive=importlib.util.module_from_spec(archive_spec);archive_spec.loader.exec_module(self.archive)
            self.reader=_ProtectedStateReader(api)
            anchor=self._archive_anchor()
            self.view_binding={key:value for key,value in anchor.items() if key not in ('head','tree')}
            self.private=anchor['private'];self.head=anchor['head'];self.tree=anchor['tree']
            self.path='reports/'+stream+'.json';item_at,_=self.archive.fixed_reader(self.reader,self.root)
            item=item_at(self.tree,self.path);self.bytes=None
            if item is not None:
                require(item['type']=='blob' and 0<item['size']<=MAX_STATE,'checkpoint size invalid')
                blob=self.reader.request(self.root+'/git/blobs/'+item['sha'])
                require(blob['encoding']=='base64' and blob['sha']==item['sha'],'checkpoint encoding/identity differs')
                self.bytes=base64.b64decode(''.join(blob['content'].split()),validate=True)
                require(len(self.bytes)==blob['size']==item['size'] and git_hash(self.bytes)==item['sha'],'checkpoint bytes differ')
            else:
                require(bootstrap_sha==self.head and (bootstrap_existing or item_at(self.tree,'reports') is None),
                        'missing checkpoint requires exact protected bootstrap revision; never reset silently')
            require(self._archive_anchor()==anchor,'protected state view changed during load')
            return
        repo = api.request(self.root)
        require(repo['full_name'] == api.repo and repo['archived'] is False and branch != repo['default_branch'], 'state cannot use default branch or archived repo')
        self.private = repo['private']
        rules = api.request(self.root + '/rules/branches/' + quote(branch, safe=''))
        require({'non_fast_forward', 'deletion'} <= {rule['type'] for rule in rules}, 'state branch rewrite/deletion protection missing')
        ids = {rule['ruleset_id'] for rule in rules if 'ruleset_id' in rule}
        require(bool(ids), 'state protection provenance missing')
        for identity in ids:
            policy = api.request(self.root + '/rulesets/' + str(identity))
            verify_policy(policy, api.repo, identity, policy_approvals)
        ref = api.request(self.root + '/git/ref/heads/' + quote(branch, safe=''))
        require(ref['ref'] == 'refs/heads/' + branch and ref['object']['type'] == 'commit', 'state reference differs')
        self.head = ref['object']['sha']; require(digest.coordinator.contract.digest(self.head, 40), 'state commit invalid')
        commit = api.request(self.root + '/git/commits/' + self.head)
        require(commit['sha'] == self.head, 'state commit differs')
        self.tree = commit['tree']['sha']
        tree = api.request(self.root + '/git/trees/' + self.tree + '?recursive=1')
        require(tree.get('truncated') is False, 'state tree incomplete')
        self.path = 'reports/' + stream + '.json'
        # Data-only branch: no workflows, executables or source files can be imported.
        state_paths.validate_tree(tree['tree'])
        entries = [item for item in tree['tree'] if item['path'] == self.path]
        require(len(entries) <= 1, 'state path ambiguous')
        self.bytes = None
        if entries:
            item = entries[0]
            require(0 < item['size'] <= MAX_STATE, 'checkpoint size invalid')
            blob = api.request(self.root + '/git/blobs/' + item['sha'])
            require(blob['encoding'] == 'base64' and blob['sha'] == item['sha'], 'checkpoint encoding/identity differs')
            self.bytes = base64.b64decode(''.join(blob['content'].split()), validate=True)
            require(len(self.bytes) == blob['size'] == item['size'] and git_hash(self.bytes) == item['sha'], 'checkpoint bytes differ')
        else:
            require(bootstrap_sha == self.head and (bootstrap_existing or not any(item['path'].startswith('reports/') for item in tree['tree'])), 'missing checkpoint requires exact protected bootstrap revision; never reset silently')

    def _archive_anchor(self):
        try:anchor=self.archive.verify_bootstrap(self.reader,self.state_view['approval_path'])
        except OSError as error:raise ValueError('protected state view approval unavailable') from error
        require(anchor['branch']==self.branch,'protected state view branch differs')
        require(not hasattr(self,'view_binding') or self.view_binding=={key:value for key,value in anchor.items() if key not in ('head','tree')},
                'protected state view input changed; reload authoritative snapshot')
        return anchor

    def _unchanged_archive_view(self):
        if self.state_view is not None:
            anchor=self._archive_anchor()
            require(anchor['head']==self.head and anchor['tree']==self.tree,'protected state view changed before checkpoint')

    def checkpoint(self, data):
        require(isinstance(data, bytes) and 0 < len(data) <= MAX_STATE, 'checkpoint too large')
        if data == self.bytes:
            return
        self._unchanged_archive_view()
        blob = self.api.request(self.root + '/git/blobs', 'POST', {'encoding': 'base64', 'content': base64.b64encode(data).decode()})
        require(blob['sha'] == git_hash(data), 'uploaded checkpoint differs')
        tree = self.api.request(self.root + '/git/trees', 'POST', {'base_tree': self.tree, 'tree': [{'path': self.path, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']}]})
        # A unique commit prevents two identical writers producing the same SHA and both passing fast-forward.
        commit = self.api.request(self.root + '/git/commits', 'POST', {'message': 'factory: reporting checkpoint ' + uuid.uuid4().hex, 'tree': tree['sha'], 'parents': [self.head]})
        require(commit['tree']['sha'] == tree['sha'] and [p['sha'] for p in commit['parents']] == [self.head], 'checkpoint ancestry differs')
        require(digest.coordinator.contract.digest(commit['sha'], 40), 'checkpoint commit invalid')
        self._unchanged_archive_view()
        result = self.api.request(self.root + '/git/refs/heads/' + quote(self.branch, safe=''), 'PATCH', {'sha': commit['sha'], 'force': False})
        require(result['ref'] == 'refs/heads/' + self.branch and result['object']['sha'] == commit['sha'], 'checkpoint reference differs')
        self.head = commit['sha']; self.tree = tree['sha']; self.bytes = data


def snapshot(path, repository, stream, destination, branch, alerts=None):
    with sqlite3.connect(path) as db:
        db.row_factory = sqlite3.Row
        present={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        selected=dict(TABLES)
        if set(PR_TABLES)&present:
            require(set(PR_TABLES)<=present,'partial PR checkpoint tables');selected.update(PR_TABLES)
        tables = {table: [dict(row) for row in db.execute(f'SELECT {",".join(columns)} FROM {table} ORDER BY '+('stream,page' if table=='reporting_pr_pages' else columns[0]))] for table, columns in selected.items()}
    document = {'schema_version': 1, 'repository': repository, 'stream': stream, 'destination': destination, 'branch': branch, 'tables': tables}
    if alerts is not None:
        document['alerts'] = alerts
    validate(document, repository, stream)
    return canonical(document).encode()


def validate(document, repository, stream):
    require(set(document) in ({'schema_version', 'repository', 'stream', 'destination', 'branch', 'tables'}, {'schema_version', 'repository', 'stream', 'destination', 'branch', 'tables', 'alerts'}) and type(document['schema_version']) is int and document['schema_version'] == 1 and document['repository'] == repository and document['stream'] == stream, 'foreign checkpoint schema/identity')
    require(stream == hashlib.sha256(canonical([repository, document['destination'], document['branch']]).encode()).hexdigest(), 'checkpoint destination/branch differs')
    require(type(document['tables']) is dict and set(document['tables']) in (set(TABLES),set(TABLES)|set(PR_TABLES)), 'unexpected checkpoint tables')
    if set(PR_TABLES)<=set(document['tables']):validate_pr_checkpoint(document,stream)
    for table, columns in TABLES.items():
        rows = document['tables'][table]
        require(isinstance(rows, list) and all(isinstance(row, dict) and set(row) == set(columns) and row['stream'] == stream for row in rows), 'malformed checkpoint rows')
        require(len({row[columns[0]] for row in rows}) == len(rows), 'duplicate checkpoint rows')
    require(len(document['tables']['digest_cursors']) == len(document['tables']['digest_origins']) == 1, 'checkpoint cursor/origin missing')
    require(isinstance(document['tables']['digest_cursors'][0]['cutoff'], str) and isinstance(document['tables']['digest_origins'][0]['origin'], str), 'checkpoint timestamps invalid')
    cursor = digest.instant(document['tables']['digest_cursors'][0]['cutoff'])
    origin = digest.instant(document['tables']['digest_origins'][0]['origin'])
    require(origin <= cursor, 'checkpoint origin after cursor')
    pending = 0; confirmed = []
    for row in document['tables']['digest_batches']:
        require(all(isinstance(row[key], str) for key in ('key','cutoff','payload','status')), 'batch fields invalid')
        require(row['status'] in {'pending', 'uncertain', 'confirmed'}, 'invalid batch state')
        payload = json.loads(row['payload'], object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
        require(set(payload) == {'schema_version','repository','destination','from','until','timezone','display_from','display_until','merges','product_acceptance'} and payload['schema_version'] == 1, 'unexpected report fields')
        require(payload['destination'] == document['destination'] and origin <= digest.instant(payload['from']) < digest.instant(payload['until']), 'report interval/destination differs')
        for item in payload['merges']:
            require(set(item) == {'pr','title','url','merge_sha','merged_at','late_discovered','delivery_evidence','evidence_status','merge_time_checks'}, 'unexpected merge fields')
            require(type(item['pr']) is int and item['pr'] > 0 and item['url'] == f'https://github.com/{repository}/pull/{item["pr"]}', 'report PR source differs')
            require(all(set(proof) == {'task','spec','revision','producer_run','artifact_digest'} for proof in item['delivery_evidence']), 'unexpected evidence fields')
        require(payload['repository'] == repository and payload['until'] == row['cutoff'], 'checkpoint report differs')
        require(row['key'] == hashlib.sha256(canonical([stream, digest.stamp(digest.instant(payload['from'])), digest.stamp(digest.instant(payload['until']))]).encode()).hexdigest(), 'checkpoint report key differs')
        if row['status'] == 'confirmed':
            receipt = json.loads(row['receipt'])
            require(set(receipt) == {'key', 'payload_sha256', 'destination', 'message_id'} and receipt['key'] == row['key'] and receipt['payload_sha256'] == hashlib.sha256(row['payload'].encode()).hexdigest() and receipt['destination'] == payload['destination'] and isinstance(receipt['message_id'], str) and bool(receipt['message_id']), 'checkpoint receipt differs')
            confirmed.append(digest.instant(row['cutoff']))
            require(digest.instant(row['cutoff']) <= cursor, 'confirmed report beyond cursor')
        else:
            pending += 1
            require(row['receipt'] is None and digest.instant(row['cutoff']) > cursor, 'pending receipt/cutoff differs')
    require(cursor == (max(confirmed) if confirmed else origin), 'cursor lacks confirmed delivery')
    require(pending <= 1, 'multiple pending reports')
    if 'alerts' in document:
        validate_alerts(document['alerts'], stream)


def validate_pr_checkpoint(document,stream):
    tables=document['tables'];rows=tables['reporting_pr_scans'];pages=tables['reporting_pr_pages']
    require(type(rows) is list and len(rows)<=1 and type(pages) is list,'PR checkpoint rows invalid')
    require(bool(rows) or not pages,'PR pages lack scan')
    if not rows:return
    row=rows[0]
    require(type(row) is dict and set(row)==set(PR_TABLES['reporting_pr_scans']) and row['stream']==stream
            and row['repository']==document['repository'] and row['branch']==document['branch']
            and type(row['phase']) is str and row['phase'] in ('baseline','compare','ready')
            and type(row['next_page']) is int and 0<row['next_page']<2**63,'PR checkpoint scan binding invalid')
    origin=digest.instant(row['origin']);until=digest.instant(row['until'])
    require(origin<until and row['origin']==tables['digest_origins'][0]['origin'],'PR checkpoint interval differs')
    helper_spec=importlib.util.spec_from_file_location('checkpoint_pr_discovery',Path(__file__).with_name('factory-reporting-pr-discovery.py'))
    helper=importlib.util.module_from_spec(helper_spec);helper_spec.loader.exec_module(helper)
    seen=set()
    for index,item in enumerate(pages,1):
        require(type(item) is dict and set(item)==set(PR_TABLES['reporting_pr_pages']) and item['stream']==stream
                and type(item['page']) is int and item['page']==index and type(item['count']) is int and 0<=item['count']<=100
                and state_paths.valid_hash(item['fingerprint'],64) and type(item['payload']) is str,'PR checkpoint page invalid')
        candidates=json.loads(item['payload'],object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
        require(type(candidates) is list and len(candidates)<=item['count'] and canonical(candidates)==item['payload'],'PR checkpoint candidates invalid')
        for candidate in candidates:
            clean=helper.normalize(candidate,document['repository'])
            require(canonical(clean)==canonical(candidate) and clean['merged_at'] is not None and clean['base']['ref']==document['branch']
                    and origin<digest.instant(clean['merged_at'])<=until and clean['number'] not in seen,'PR checkpoint candidate binding differs')
            seen.add(clean['number'])
    require(any(helper.compatible_layout(pages,row['phase'],row['next_page'],size) for size in (25,100)),
            'PR checkpoint cursor invalid')


def alert_key(stream, kind, cutoff, run_id, incident, run_attempt=None):
    fields = ['reporting-alert-v1', stream, kind]
    fields += [incident] if kind == 'recovery' else [run_id] if kind == 'drill' else [cutoff, run_id, run_attempt]
    return hashlib.sha256(canonical(fields).encode()).hexdigest()


def validate_alerts(alerts, stream):
    require(isinstance(alerts, list) and len(alerts) <= 10000, 'alert journal bound exceeded')
    seen = {}; pending = 0
    for row in alerts:
        require(isinstance(row, dict) and set(row) == {'key','kind','incident','cutoff','run_id','run_attempt','status','message_id'}, 'unexpected alert fields')
        require(row['kind'] in {'overdue','failure','drill','recovery'} and row['status'] in {'pending','uncertain','confirmed'}, 'invalid alert kind/state')
        require(isinstance(row['cutoff'], str) and digest.stamp(digest.instant(row['cutoff'])) == row['cutoff'], 'alert cutoff invalid')
        require(row['run_id'] is None or (type(row['run_id']) is int and row['run_id'] > 0), 'alert run identity invalid')
        require((type(row['run_attempt']) is int and row['run_attempt'] > 0) if row['kind']=='failure' else row['run_attempt'] is None, 'alert attempt invalid')
        require((row['kind'] in {'failure','drill'}) == (row['run_id'] is not None), 'alert run kind differs')
        require(row['key'] == alert_key(stream, row['kind'], row['cutoff'], row['run_id'], row['incident'], row['run_attempt']) and row['key'] not in seen, 'alert key duplicate or differs')
        if row['kind'] == 'recovery':
            require(row['incident'] in seen and seen[row['incident']]['kind'] != 'recovery' and seen[row['incident']]['status'] == 'confirmed', 'recovery lacks confirmed incident')
        else:
            require(row['incident'] == row['key'], 'alert incident differs')
        if row['status'] == 'confirmed':
            require(isinstance(row['message_id'], str) and re.fullmatch(r'[0-9]+\.[0-9]{1,6}', row['message_id']), 'alert receipt invalid')
        else:
            pending += 1; require(row['message_id'] is None, 'pending alert has receipt')
        seen[row['key']] = row
    require(pending <= 1, 'multiple unfinished alerts')


class HostedDigest(digest.Digest):
    def __init__(self, path, config, state):
        self.state = state; self.failed = False
        # A private local projection is reconstructed from typed JSON, never remote SQL/SQLite binaries.
        digest.Digest(path, config['repository'], config['destination'], config['start'], config['branch'])
        if state.bytes is not None:
            document = json.loads(state.bytes, object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
            stream = hashlib.sha256(canonical([config['repository'], config['destination'], config['branch']]).encode()).hexdigest()
            validate(document, config['repository'], stream)
            with sqlite3.connect(path) as db:
                present={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if config.get('pr_discovery_mode','legacy')=='resumable' or set(PR_TABLES)&present:
                    for sql in PR_SQL:db.execute(sql)
                    for table in PR_TABLES:db.execute(f'DELETE FROM {table}')
                if set(PR_TABLES)<=set(document['tables']):
                    for sql in PR_SQL:db.execute(sql)
                for table, columns in dict(TABLES,**PR_TABLES).items():
                    if table not in document['tables']:continue
                    db.execute(f'DELETE FROM {table}')
                    for row in document['tables'][table]:
                        db.execute(f'INSERT INTO {table}({",".join(columns)}) VALUES({",".join("?" for _ in columns)})', [row[c] for c in columns])
        super().__init__(path, config['repository'], config['destination'], config['start'], config['branch'], receipt_mode=config.get('receipt_mode','legacy'),pr_discovery_mode=config.get('pr_discovery_mode','legacy'))

    @contextmanager
    def transaction(self):
        require(not self.failed, 'failed checkpoint requires a fresh authoritative restore')
        with super().transaction() as db:
            yield db
        # Every state change must become durable BEFORE caller can send or acknowledge delivery.
        try:
            alerts = None if self.state.bytes is None else json.loads(self.state.bytes).get('alerts')
            self.state.checkpoint(snapshot(self.path, self.repository, self.stream, self.destination, self.branch, alerts))
        except BaseException:
            self.failed = True; raise


def run(config, report_api, state_api, slack_client, path, now):
    require(config.get('enabled') is True and report_api.repo == config['repository'], 'hosted reporting disabled/foreign')
    source = report_api.get(f'repos/{report_api.repo}')
    require(source['full_name'] == report_api.repo and source['default_branch'] == config['branch'], 'report repository/default branch differs')
    target = slack.due(now)
    stream = hashlib.sha256(canonical([config['repository'], config['destination'], config['branch']]).encode()).hexdigest()
    pending_snapshot = False
    reporting_cursor = None
    mode = config.get('receipt_mode', 'legacy')
    require(type(mode) is str and mode in ('legacy', 'durable'), 'explicit reporting receipt mode required')
    if mode == 'durable':
        require(not Path(path).is_symlink(), 'reporting database symlink forbidden')
        path = Path(path).resolve()
        durable = config.get('receipt_archive')
        require(type(durable) is dict and set(durable)=={'approval_path','trust_path','store','trust_mode'}
                and config.get('receipt_policy') is not None, 'protected durable reporting configuration required')
        maintenance_spec = importlib.util.spec_from_file_location('report_maintenance', Path(__file__).with_name('factory-reporting-maintenance.py'))
        maintenance = importlib.util.module_from_spec(maintenance_spec); maintenance_spec.loader.exec_module(maintenance)
        require(config.get('state_view')=={'mode':'archive','approval_path':str(Path(durable['approval_path']).resolve())},
                'durable report requires protected archive state view')
        origin = maintenance.archive.advance_origin(state_api, durable['approval_path'], commit_budget=16, tree_pages=4)
        if not origin['frozen_complete']:
            return {'status':'incomplete','phase':'origin','coverage_complete':False,'all_history_complete':False,'task_credit':False}
        reader = _ProtectedStateReader(state_api)
        prior_anchor = maintenance.archive.verify_bootstrap(reader, durable['approval_path'])
        require(config['state_branch']==prior_anchor['branch'] and config['state_repository']==state_api.repo,
                'durable reporting state binding differs')
        _, prior_blob = maintenance.archive.fixed_reader(reader, 'repos/'+state_api.repo)
        prior_raw = prior_blob(prior_anchor['tree'], 'reports/'+stream+'.json')
        if prior_raw is not None:
            prior = json.loads(prior_raw, object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
            validate(prior, state_api.repo, stream)
            pending_snapshot = any(row['status']!='confirmed' for row in prior['tables']['digest_batches'])
            reporting_cursor = prior['tables']['digest_cursors'][0]['cutoff']
        if not pending_snapshot:
            scheduling=maintenance.select_reporting if config.get('pr_discovery_mode','legacy')=='resumable' else maintenance.prepare_reporting
            progress = scheduling(report_api, state_api, config['receipt_policy'], durable['trust_path'],
                        durable['store'], durable['approval_path'], interval_end=target, trust_mode=durable['trust_mode'], reporting_cursor=reporting_cursor)
            if progress['status'] != 'projection-ready':return progress
            target = progress['interval_end']
    stream = hashlib.sha256(canonical([config['repository'], config['destination'], config['branch']]).encode()).hexdigest()
    bootstrap = config.get('bootstrap_sha')
    if mode == 'durable':
        view = {'mode':'archive','approval_path':str(Path(durable['approval_path']).resolve())}
        require(config.get('state_view') == view, 'durable report requires protected archive state view')
        anchor = maintenance.archive.verify_bootstrap(state_api, durable['approval_path'])
        require(config['state_branch']==anchor['branch'] and config['state_repository']==state_api.repo,
                'durable reporting state binding differs')
        item_at, _ = maintenance.archive.fixed_reader(state_api, 'repos/'+state_api.repo)
        report_leaf = 'reports/'+stream+'.json'
        if item_at(anchor['tree'], report_leaf) is None:
            require(item_at(anchor['bootstrap_tree'], report_leaf) is None and
                    state_api.request('repos/'+state_api.repo+'/commits?sha='+anchor['head']+'&path='+quote(report_leaf,safe='')+'&per_page=1') == [],
                    'missing durable reporting checkpoint cannot reset historical state')
            bootstrap = anchor['head']
    state = GitState(state_api, config['state_branch'], stream, bootstrap, config.get('policy_approvals'),
                     state_view=config.get('state_view'), bootstrap_existing=mode=='durable')
    require(not source['private'] or state.private, 'private repository cannot publish public checkpoints')
    store = HostedDigest(path, config, state)
    if not pending_snapshot and digest.instant(store.cursor()) >= digest.instant(target):
        return {'status': 'not-due'}
    if not pending_snapshot and store.pr_discovery_mode=='resumable':
        discovered=store.discover(report_api,target)
        if discovered['status']!='complete':return discovered
        if mode=='durable':
            progress=maintenance.prepare_reporting(report_api,state_api,config['receipt_policy'],durable['trust_path'],
                        durable['store'],durable['approval_path'],interval_end=target,trust_mode=durable['trust_mode'],reporting_cursor=reporting_cursor)
            if progress['status']!='projection-ready':return progress
            require(progress['interval_end']==target,'PR observation interval changed during maintenance')
            # Maintenance changes only its own role. Retain the private current
            # PR observation while refreshing the authenticated report state.
            fresh=GitState(state_api,config['state_branch'],stream,config.get('bootstrap_sha'),
                           config.get('policy_approvals'),state_view=config.get('state_view'))
            require(fresh.bytes==store.state.bytes,'reporting checkpoint changed during maintenance')
            store.state=state=fresh
    if not pending_snapshot and config.get('receipt_policy') is not None:
        receipts_spec = importlib.util.spec_from_file_location('report_receipts', Path(__file__).with_name('factory-receipts.py'))
        receipts = importlib.util.module_from_spec(receipts_spec); receipts_spec.loader.exec_module(receipts)
        projection = receipts.project(report_api, config['receipt_policy'], path, receipt_mode=mode, state_api=state_api,
                         archive_config=config.get('receipt_archive'), selection=None if mode=='legacy' else
                         {'interval_end':target,'history_head':progress['history_head'],'campaign':progress['campaign']})
        if mode=='durable':
            if projection.get('coverage_complete') is not True:
                # A stale source campaign needs fresh maintenance; interrupted
                # acknowledgement alone keeps its selectors for validation retry.
                maintenance.maintain(report_api,state_api,config['receipt_policy'],durable['trust_path'],
                            durable['store'],durable['approval_path'],interval_end=target,trust_mode=durable['trust_mode'])
                return dict(projection,status='incomplete',phase='projection-pending')
            acknowledgement=maintenance.acknowledge_reporting(report_api,state_api,config['receipt_policy'],
                        durable['trust_path'],durable['store'],durable['approval_path'],interval_end=target,
                        trust_mode=durable['trust_mode'],history_head=progress['history_head'],campaign=progress['campaign'])
            if acknowledgement['status']!='projection-acknowledged':return acknowledgement
            # Journal acknowledgement advanced the shared branch. Reload the exact
            # report role before any prepare/send; typed local receipt tables stay.
            state=GitState(state_api,config['state_branch'],stream,config.get('bootstrap_sha'),
                           config.get('policy_approvals'),state_view=config.get('state_view'))
            require(state.bytes==store.state.bytes,'reporting checkpoint changed during projection acknowledgement')
            store.state=state
    batch = store.prepare(report_api, target)
    if batch.get('status')=='incomplete':return batch
    adapter = slack.transport(slack_client, config, batch)
    receipt = store.deliver(batch['key'], adapter)
    require(adapter.lookup(batch['key']).get('receipt') == receipt, 'Delivered receipt not visible in Slack history; preserve confirmed state')
    return {'status': 'delivered', 'receipt': receipt, 'checkpoint_sha': state.head}


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args(); config = digest.coordinator.contract.load(args.config)
    require(os.environ.get('GITHUB_SERVER_URL') == 'https://github.com', 'hosted state supports github.com only')
    require(os.environ.get('GITHUB_REPOSITORY') == config['repository'] and os.environ.get('GITHUB_REF') == 'refs/heads/' + config['branch'], 'hosted reporting requires target default branch')
    os.umask(0o077)
    selected = os.environ.get('FACTORY_REPORTING_APP_WRITER_ENABLED', 'false')
    require(selected in ('true', 'false'), 'reporting writer flag invalid')
    if selected == 'true':
        transport_spec = importlib.util.spec_from_file_location('hosted_reporting_transport', Path(__file__).with_name('factory-reporting-transport.py'))
        transport = importlib.util.module_from_spec(transport_spec); transport_spec.loader.exec_module(transport)
        require(config['state_repository'] == config['repository'], 'selected reporting state repository differs')
        report_api = state_api = transport.create_api(os.environ)
        require(state_api.repo == config['repository'], 'selected reporting repository differs')
        config = transport.attach_reporting_context(config)
    else:
        state_api = API(config['state_repository'], os.environ.get('FACTORY_REPORTING_STATE_TOKEN') or os.environ.get('GH_TOKEN'))
        report_api = digest.coordinator.GitHub(config['repository'])
    with tempfile.TemporaryDirectory(prefix='factory-reporting-') as tmp:
        result = run(config, report_api, state_api, slack.http_client(config), Path(tmp)/'reporting.sqlite', datetime.now(timezone.utc))
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, sqlite3.Error, subprocess.SubprocessError) as error:
        public = {'state bypass actors hidden; protected operator approval required',
                  'state policy approval missing or mismatched', 'state policy changed since operator approval',
                  'state policy approval clock invalid', 'state policy metadata incomplete',
                  'state protection disabled or bypassable', 'Slack receipt bot differs',
                  'Slack receipt metadata differs', 'Slack receipt text differs',
                  'Slack receipt timestamp differs', 'remote delivery remains uncertain',
                  'split Slack receipt incomplete or conflicting',
                  'Slack request failed; reconcile before resend',
                  'Delivered receipt not visible in Slack history; preserve confirmed state'}
        public.update('Slack API returned failure: ' + code for code in (
            'missing_scope', 'not_in_channel', 'channel_not_found', 'invalid_auth',
            'token_revoked', 'token_expired', 'not_authed', 'account_inactive',
            'ratelimited', 'access_denied', 'team_access_not_granted', 'invalid_arguments', 'unknown'))
        detail = str(error) if str(error) in public else 'reconcile authoritative state before retry'
        print('Hosted reporting blocked: ' + detail, file=sys.stderr); sys.exit(1)

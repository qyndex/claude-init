#!/usr/bin/env python3
"""Read-only replay of historical completion; never current readiness authority."""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import tempfile
from urllib.parse import quote
import importlib.util

spec = importlib.util.spec_from_file_location('operational_retained',Path(__file__).with_name('factory-operational-producer.py'))
producer = importlib.util.module_from_spec(spec); spec.loader.exec_module(producer)
proof = producer.proof
require = proof.require


class ReadOnly:
    """No credential selection or writes; preserve existing128/32MiB/2MiB bounds."""
    def __init__(self, api):
        self.source = api; self.repo = api.repo; self.calls = self.bytes = 0
    def request(self, path):
        require(type(path) is str and (path == 'repos/'+self.repo or path.startswith('repos/'+self.repo+'/')), 'replay foreign endpoint')
        require(self.calls < 128 and self.bytes < 33554432, 'replay source budget exhausted'); self.calls += 1
        value = self.source.request(path,'GET',None)
        encoded = producer.transport.encode(value)
        self.bytes += len(encoded)
        require(len(encoded) <= 2097152 and self.bytes <= 33554432, 'replay response bound exceeded')
        return proof.decode(encoded,2097152)


def reference(api, branch):
    proof.branch(branch)
    value = api.request('repos/'+api.repo+'/git/ref/heads/'+quote(branch,safe=''))
    require(type(value) is dict and value.get('ref') == 'refs/heads/'+branch and type(value.get('object')) is dict and value['object'].get('type') == 'commit', 'replay branch reference differs')
    sha = value['object'].get('sha'); proof.hexstr(sha,40); return sha


def repository(api):
    value = api.request('repos/'+api.repo)
    require(type(value) is dict and value.get('full_name') == api.repo and value.get('archived') is False and type(value.get('private')) is bool, 'replay repository unavailable')
    proof.integer(value.get('id')); proof.branch(value.get('default_branch'))
    return {'name':api.repo,'id':value['id'],'private':value['private'],'branch':value['default_branch']}


def protected_branch(api, branch, sha):
    value = api.request('repos/'+api.repo+'/branches/'+quote(branch,safe=''))
    require(type(value) is dict and value.get('name') == branch and value.get('protected') is True and type(value.get('commit')) is dict and value['commit'].get('sha') == sha, 'replay default branch not protected or changed')


def immutable_file(api, path, sha, maximum):
    value = api.request('repos/'+api.repo+'/contents/'+path+'?ref='+sha)
    require(type(value) is dict and value.get('type') == 'file' and value.get('path') == path and value.get('encoding') == 'base64' and type(value.get('size')) is int and 0 < value['size'] <= maximum and type(value.get('content')) is str and len(value['content']) <= maximum*2, 'replay protected file invalid')
    try:raw = base64.b64decode(''.join(value['content'].split()),validate=True)
    except ValueError as exc:raise ValueError('replay protected file encoding invalid') from exc
    require(len(raw) == value['size'] and producer.state.git_hash(raw) == value.get('sha'), 'replay protected file identity differs')
    return raw


def trusted_profile(api, identity):
    proof.text(identity,r'[A-Za-z0-9][A-Za-z0-9_.-]{0,99}')
    repo = repository(api); source = reference(api,repo['branch']); protected_branch(api,repo['branch'],source)
    raw = immutable_file(api,producer.REGISTRY,source,262144)
    # This separate directory contains data only, never a candidate registry/import.
    with tempfile.TemporaryDirectory(prefix='factory-replay-registry-') as temporary:
        root = Path(temporary).resolve(); (root/'factory').mkdir()
        (root/producer.REGISTRY).write_bytes(raw)
        selected = producer.select_registry(root,identity)
    require(selected['repository'] == {key:repo[key] for key in ('name','id','private')} and selected['branch'] == repo['branch'], 'replay protected profile repository differs')
    return selected,repo,source


def guard_profile(api, repo, source):
    require(repository(api) == repo and reference(api,repo['branch']) == source, 'replay protected profile source changed')
    protected_branch(api,repo['branch'],source)


def state_snapshot(api, entry):
    root = 'repos/'+api.repo; branch = entry['retention']['branch']
    head = reference(api,branch); commit = api.request(root+'/git/commits/'+head)
    require(type(commit) is dict and commit.get('sha') == head and type(commit.get('tree')) is dict, 'replay state commit differs')
    tree_sha = commit['tree'].get('sha'); proof.hexstr(tree_sha,40)
    def tree(sha):
        value = api.request(root+'/git/trees/'+sha)
        require(type(value) is dict and value.get('sha') == sha and value.get('truncated') is False and type(value.get('tree')) is list and len(value['tree']) <= 1024, 'replay state tree incomplete')
        seen = set()
        for item in value['tree']:
            require(type(item) is dict and type(item.get('path')) is str and item['path'] not in seen, 'replay duplicate tree path'); seen.add(item['path']); proof.hexstr(item.get('sha'),40)
        return value['tree']
    reports = None
    for item in tree(tree_sha):
        if item['path'] in ('reports','receipt-archive'):
            require(item.get('type') == 'tree' and item.get('mode') == '040000', 'replay root directory invalid')
            if item['path'] == 'reports':reports = item['sha']
            # Receipt archive identity is opaque; it is not completion authority.
        else:
            require(item['path'] == 'README.md' and item.get('type') == 'blob' and item.get('mode') == '100644', 'replay root path invalid')
    require(reports is not None, 'replay reports role missing')
    name = producer.role(api.repo,entry['profile_id'],entry['original']['source_sha'])+'.json'; target = None
    for item in tree(reports):
        proof.text(item['path'],r'[0-9a-f]{64}\.json')
        require(item.get('type') == 'blob' and item.get('mode') == '100644', 'replay report not regular')
        if item['path'] == name:target = item
    require(target is not None and type(target.get('size')) is int and 0 < target['size'] <= 1048576, 'replay completion role absent or oversized')
    raw = producer.read_blob(api,target['sha'],1048576)
    require(len(raw) == target['size'], 'replay completion blob size differs')
    return {'head':head,'tree':tree_sha,'path':'reports/'+name,'sha':target['sha'],'raw':raw}


def replay(api, identity, *, checkout=None, runner=None, now=None):
    """Explicit synthetic runner seam is internal only; CLI always native verifies."""
    reader = ReadOnly(api)
    entry,repo,source = trusted_profile(reader,identity)
    before = state_snapshot(reader,entry)
    materials = producer.retained_materials(before['raw'])
    # Candidate working files grant no trust. Only immutable Git objects at signed
    # source hints may match the independently fetched active runtime profile.
    profiles = producer.retained_profiles(reader,entry,materials,root=checkout)
    record = proof.verify_durable(*materials,*profiles,runner=runner,now=now)
    after = state_snapshot(reader,entry)
    require(after['sha'] == before['sha'] and after['raw'] == before['raw'], 'replay target changed during verification')
    guard_profile(reader,repo,source)
    return {'schema_version':1,'type':'historical-operational-replay','purpose':'historical-operational-acceptance',
            'profile_id':entry['profile_id'],'profile_sha256':profiles[0]['profile_sha256'],'repository':entry['repository'],
            'original_source_sha':record['original']['source_sha'],'original_runs':record['original']['runs'],
            'protected_source_sha':source,'retained_head':after['head'],'retained_path':after['path'],
            'record_sha256':hashlib.sha256(materials[0]).hexdigest(),'completion_sha256':hashlib.sha256(materials[2]).hexdigest(),
            'authority':{'delivery':False,'current_task':False,'merge':False,'production':False,'current_readiness':False}}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--live',action='store_true',required=True)
    parser.add_argument('--repository',default=os.environ.get('GITHUB_REPOSITORY'))
    parser.add_argument('--profile',required=True)
    args = parser.parse_args(argv)
    api = producer.evidence.GitHub(args.repository)
    result = replay(api,args.profile,checkout=Path(__file__).resolve().parents[2])
    result['verification_mode'] = 'native-read-only-historical-completion'
    print(proof.canonical(result).decode()); return 0


if __name__ == '__main__':
    try:raise SystemExit(main())
    except (ValueError,RuntimeError,OSError,KeyError,TypeError):
        raise SystemExit('Historical completion replay unavailable; no current-readiness or merge credit')

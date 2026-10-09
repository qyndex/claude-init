#!/usr/bin/env python3
"""Protected, request-only factory merge authority. Never execute PR code here."""
import argparse
import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote
import zipfile

_contract_spec = importlib.util.spec_from_file_location('contract', Path(__file__).with_name('validate-candidate-evidence.py'))
contract = importlib.util.module_from_spec(_contract_spec)
_contract_spec.loader.exec_module(contract)
require = contract.require


def policy_hash(policy):
    return hashlib.sha256(json.dumps(policy, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def matches(path, patterns):
    # Prefix globs are deliberately simple: a trailing * includes descendants.
    return any(path.startswith(pattern[:-1]) if pattern.endswith('*') else path == pattern for pattern in patterns)


def protection(api, root, branch, required, app_id):
    rules = api.get(f'{root}/rules/branches/{quote(branch, safe="")}')
    require(isinstance(rules, list) and any(rule['type'] == 'pull_request' for rule in rules), 'active target PR protection missing')
    checks = {}
    strict = False
    ids = set()
    for rule in rules:
        if 'ruleset_id' in rule:
            ids.add(rule['ruleset_id'])
        if rule['type'] == 'required_status_checks':
            strict |= rule['parameters'].get('strict_required_status_checks_policy') is True
            for check in rule['parameters']['required_status_checks']:
                checks.setdefault(check['context'], []).append(check.get('integration_id'))
    require(strict, 'strict target check protection missing')
    for name, producer in dict(required, **{'factory-eligibility': app_id}).items():
        require(producer in checks.get(name, []), f'live producer pin missing: {name}')
    require(bool(ids), 'ruleset provenance missing')
    for ruleset_id in ids:
        ruleset = api.get(f'{root}/rulesets/{ruleset_id}')
        require(ruleset['enforcement'] == 'active' and ruleset.get('bypass_actors') == [], 'active protection has bypass actors or drift')


def coordinate(api, policy, number, merge=False):
    require(policy.get('schema_version') == 1 and policy.get('enabled') is True, 'factory policy not activated')
    require(not merge or policy.get('merge_enabled') is True, 'factory merge mode not activated after shadow proof')
    repo = policy['repository']
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo) is not None, 'invalid repository identity')
    require(contract.integer(policy['app_id']), 'factory App ID unavailable')
    root = f'repos/{repo}'
    pr = api.get(f'{root}/pulls/{number}')
    require(pr['state'] == 'open' and not pr['draft'] and not pr['merged'], 'PR must be open and ready')
    require(pr['head']['repo']['full_name'] == repo and pr['base']['repo']['full_name'] == repo, 'cross-repository candidate not approved')
    require(pr['base']['ref'] == policy['base_branch'], 'unexpected target branch')
    head, base = pr['head']['sha'], pr['base']['sha']
    require(contract.digest(head, 40) and contract.digest(base, 40), 'invalid candidate commits')
    spec_match = re.fullmatch(r'factory/spec-([0-9]+)/[A-Za-z0-9._/-]+', pr['head']['ref'])
    require(spec_match is not None, 'candidate branch must name approved specification')
    sid = spec_match[1]
    approved = policy['specs'].get(sid)
    require(isinstance(approved, dict), 'specification is not approved in protected policy')
    files = api.get(f'{root}/pulls/{number}/files')
    require(isinstance(files, list) and bool(files), 'candidate diff unavailable')
    for file in files:
        for path in (file['filename'], file.get('previous_filename')):
            if path is None:
                continue
            require(not matches(path, policy['protected_paths']), f'operator authority decision required: {path}')
            require(matches(path, approved['allowed_paths']), f'path outside approved scope: {path}')
    require(len(files) == pr.get('changed_files', len(files)) and len(files) < 3000, 'incomplete diff pagination')
    protection(api, root, pr['base']['ref'], policy['required_checks'], policy['app_id'])
    observed_checks = api.get(f'{root}/commits/{head}/check-runs?filter=latest')
    receipts = []
    for name, producer in policy['required_checks'].items():
        selected = [check for check in observed_checks if check['name'] == name and check['app']['id'] == producer]
        require(len(selected) == 1, f'missing or ambiguous trusted check: {name}')
        check = selected[0]
        receipts.append({'name': name, 'head_sha': check['head_sha'], 'app_id': check['app']['id'], 'run_id': check['id'], 'status': check['status'], 'conclusion': check['conclusion']})
    runs = api.get(f'{root}/actions/runs?head_sha={head}')
    documents, authorities, selected_runs, attachments = {}, {}, [], {}
    require(set(policy['producers']) == {'verification', 'review'}, 'separate verifier/reviewer producers required')
    require(policy['producers']['verification']['workflow_id'] != policy['producers']['review']['workflow_id'], 'independent workflow identities required')
    for role, producer in policy['producers'].items():
        require(contract.integer(producer['workflow_id']), f'{role}: workflow identity missing')
        relevant = [run for run in runs if run['workflow_id'] == producer['workflow_id']]
        require(bool(relevant), f'{role}: trusted run missing')
        run = max(relevant, key=lambda value: value['id'])
        require(run['head_sha'] == head and run['head_repository']['full_name'] == repo, f'{role}: stale or foreign run')
        require(run['event'] == 'pull_request' and any(item['number'] == number for item in run['pull_requests']), f'{role}: wrong run event/PR')
        require(run['status'] == 'completed' and run['conclusion'] == 'success', f'{role}: run not successful')
        require(bool(producer['trusted_files']), f'{role}: trusted runtime definitions missing')
        for path, digest in producer['trusted_files'].items():
            require(contract.digest(digest, 64), 'invalid trusted definition digest')
            require(matches(path, policy['protected_paths']), 'trusted runtime must be an authority-protected path')
            require(hashlib.sha256(api.source(path, head)).hexdigest() == digest, f'{role}: runtime definition changed')
        document, blobs = api.artifact(run, producer['artifact_name'])
        documents[role] = document
        authorities[role] = f'workflow:{run["workflow_id"]}/run:{run["id"]}'
        selected_runs.append(run)
        attachments.update(blobs)
    verifier, reviewer = documents['verification'], documents['review']
    contract.object_keys(verifier, contract.BINDING | {'generated_at', 'acceptance', 'verification'}, 'verifier artifact')
    contract.object_keys(reviewer, contract.BINDING | {'generated_at', 'review'}, 'review artifact')
    binding = {key: verifier[key] for key in contract.BINDING}
    require(all(reviewer[key] == binding[key] for key in contract.BINDING), 'review/spec/policy candidate mismatch')
    evidence = dict(binding, generated_at=verifier['generated_at'], acceptance=verifier['acceptance'], checks=receipts,
                    verification=verifier['verification'], review=reviewer['review'])
    context = {'schema_version': 1, 'repository': repo, 'pull_request': number, 'head_sha': head, 'base_sha': base,
               'spec_sha256': approved['sha256'], 'policy_sha256': policy_hash(policy), 'ac_ids': approved['ac_ids'],
               'implementer': pr['user']['login'], 'allowed_verifiers': [authorities['verification']],
               'allowed_reviewers': [authorities['review']], 'required_checks': policy['required_checks'],
               'window_start': min(run['created_at'] for run in selected_runs), 'window_end': max(run['updated_at'] for run in selected_runs)}
    contract.validate(context, evidence)
    require(contract.stamp(context['window_start']) <= contract.stamp(reviewer['generated_at']) <= contract.stamp(context['window_end']), 'review outside trusted run window')
    for observation in evidence['acceptance']:
        digest = observation['artifact_sha256']
        require(digest in attachments and hashlib.sha256(attachments[digest]).hexdigest() == digest, 'observation artifact missing or altered')
    fresh = api.get(f'{root}/pulls/{number}')
    require(fresh['state'] == 'open' and not fresh['draft'] and not fresh['merged'] and fresh['head']['sha'] == head and fresh['base']['sha'] == base, 'candidate changed during evaluation')
    protection(api, root, pr['base']['ref'], policy['required_checks'], policy['app_id'])
    result = {'schema_version': 1, 'repository': repo, 'pull_request': number, 'head_sha': head, 'base_sha': base,
              'spec': sid, 'spec_sha256': approved['sha256'], 'policy_sha256': context['policy_sha256'],
              'verifier_run': selected_runs[0]['id'], 'reviewer_run': selected_runs[1]['id'], 'eligible': True, 'merged': False}
    if merge:
        api.post(f'{root}/check-runs', {'name': 'factory-eligibility', 'head_sha': head, 'status': 'completed', 'conclusion': 'success',
                 'output': {'title': 'Factory eligibility passed', 'summary': f'Exact candidate {head}; spec {sid}; policy {context["policy_sha256"]}'}})
        response = api.put(f'{root}/pulls/{number}/merge', {'sha': head, 'merge_method': 'squash'})
        require(response.get('merged') is True and contract.digest(response.get('sha'), 40), 'conditional merge did not complete')
        result.update(merged=True, merge_sha=response['sha'])
    return result


class GitHub:
    def __init__(self, repo):
        self.repo = repo

    def request(self, path, method='GET', payload=None, raw=False, paginate=False):
        command = ['gh', 'api', path, '--method', method, '-H', 'Accept: application/vnd.github+json']
        if paginate:
            command += ['--paginate', '--slurp']
        if payload is not None:
            command += ['--input', '-']
        completed = subprocess.run(command, input=json.dumps(payload).encode() if payload is not None else None,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        require(completed.returncode == 0, f'GitHub API request failed: {path.split("?")[0]}')
        return completed.stdout if raw else json.loads(completed.stdout, object_pairs_hook=contract.no_duplicate_keys)

    def get(self, path):
        field = 'check_runs' if '/check-runs?' in path else 'workflow_runs' if '/actions/runs?' in path else None
        many = bool(field) or path.endswith('/files') or '/rules/branches/' in path
        value = self.request(path, paginate=many)
        return [item for page in value for item in (page[field] if field else page)] if many else value

    def source(self, path, sha):
        value = self.get(f'repos/{self.repo}/contents/{quote(path, safe="/")}?ref={sha}')
        require(value.get('encoding') == 'base64', 'trusted source unavailable')
        return base64.b64decode(value['content'])

    def artifact(self, run, name):
        pages = self.request(f'repos/{self.repo}/actions/runs/{run["id"]}/artifacts', paginate=True)
        artifacts = [item for page in pages for item in page['artifacts'] if item['name'] == name and not item['expired']]
        require(len(artifacts) == 1, 'trusted artifact missing or ambiguous')
        artifact = artifacts[0]
        require(0 < artifact['size_in_bytes'] <= 4_000_000 and isinstance(artifact.get('digest'), str), 'artifact size/digest unavailable')
        blob = self.request(f'repos/{self.repo}/actions/artifacts/{artifact["id"]}/zip', raw=True)
        require(len(blob) <= 4_000_000 and artifact['digest'] == 'sha256:' + hashlib.sha256(blob).hexdigest(), 'artifact archive digest mismatch')
        with zipfile.ZipFile(io.BytesIO(blob)) as archive:
            names = archive.namelist()
            require(len(names) == len(set(names)) and 'evidence.json' in names, 'artifact entries missing/duplicated')
            require(sum(item.file_size for item in archive.infolist()) <= 8_000_000, 'unpacked artifact too large')
            attachments = {}
            for name in names:
                if name == 'evidence.json':
                    continue
                require(re.fullmatch(r'artifacts/[0-9a-f]{64}', name) is not None, 'unexpected artifact entry')
                contents = archive.read(name)
                require(hashlib.sha256(contents).hexdigest() == name.split('/')[1], 'observation digest mismatch')
                attachments[name.split('/')[1]] = contents
            document = json.loads(archive.read('evidence.json'), object_pairs_hook=contract.no_duplicate_keys)
            return document, attachments

    def post(self, path, payload):
        return self.request(path, 'POST', payload)

    def put(self, path, payload):
        return self.request(path, 'PUT', payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--pr', type=int, required=True)
    parser.add_argument('--merge', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(args.pr > 0, 'invalid pull request number')
    policy = contract.load(args.policy)
    api = GitHub(policy['repository'])
    try:
        result = coordinate(api, policy, args.pr, merge=args.merge)
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired, zipfile.BadZipFile):
        # A new failed evaluation must not leave an older success as the latest
        # App check for this head. API failure still fails the coordinator.
        if args.merge:
            current = api.get(f'repos/{policy["repository"]}/pulls/{args.pr}')
            api.post(f'repos/{policy["repository"]}/check-runs', {
                'name': 'factory-eligibility', 'head_sha': current['head']['sha'],
                'status': 'completed', 'conclusion': 'failure',
                'output': {'title': 'Factory eligibility blocked', 'summary': 'Candidate verification or live policy did not satisfy factory authority. See the coordinator run.'}})
        raise
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired, zipfile.BadZipFile) as error:
        print(f'factory blocked: {error}', file=sys.stderr)
        sys.exit(1)

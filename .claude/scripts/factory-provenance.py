#!/usr/bin/env python3
"""Fail-closed protected checkout and GitHub certificate provenance checks."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location('bounded', Path(__file__).with_name('factory-bounded-process.py'))
bounded = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bounded)


def require(value, message):
    if not value:
        raise ValueError(message)


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate provenance field')
        result[key] = value
    return result


def execution_base(policy, role, run, number, *, environ=None, root=None):
    env = os.environ if environ is None else environ
    root = Path(__file__).resolve().parents[2] if root is None else Path(root)
    repo = policy['repository']; branch = 'refs/heads/' + policy['base_branch']
    workflow = f'{repo}/.github/workflows/factory-{role}.yml@{branch}'
    require(env.get('GITHUB_ACTIONS') == 'true' and env.get('GITHUB_EVENT_NAME') == 'pull_request_target', 'protected execution event missing')
    require(env.get('GITHUB_REPOSITORY') == repo and env.get('GITHUB_REF') == branch, 'protected execution repository/ref differs')
    require(env.get('GITHUB_RUN_ID') == str(run['id']) and env.get('GITHUB_RUN_ATTEMPT') == str(run['run_attempt']), 'protected execution run/attempt differs')
    base = env.get('GITHUB_SHA', '')
    require(re.fullmatch('[0-9a-f]{40}', base) is not None and env.get('GITHUB_WORKFLOW_SHA') == base, 'protected execution source unavailable')
    require(env.get('GITHUB_WORKFLOW_REF') == workflow, 'protected execution workflow differs')
    observed = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True, timeout=10)
    require(observed.stdout.strip() == base, 'protected checkout differs from GitHub execution SHA')
    event = Path(env['GITHUB_EVENT_PATH'])
    require(event.is_file() and event.stat().st_size <= 1_000_000, 'event context bound exceeded')
    document = json.loads(event.read_bytes(), object_pairs_hook=no_duplicates)
    require(document['number'] == number and document['repository']['full_name'] == repo, 'protected execution PR differs')
    for path, digest in policy['producers'][role]['trusted_files'].items():
        file = root / path
        require(not Path(path).is_absolute() and '..' not in Path(path).parts and file.is_file() and not file.is_symlink(), 'protected runtime path invalid')
        require(file.stat().st_size <= 8_000_000 and hashlib.sha256(file.read_bytes()).hexdigest() == digest, 'actual protected runtime bytes differ')
    return base


def verify(evidence, bundle, policy, role, run, base, *, runner=None):
    """Trust only gh-verified certificate claims; never predicate provenance strings."""
    require(0 < len(evidence) <= 2_000_000 and 0 < len(bundle) <= 1_000_000, 'signed evidence/bundle bound exceeded')
    require(type(run['id']) is int and run['id'] > 0 and type(run['run_attempt']) is int and run['run_attempt'] > 0, 'signed run identity missing')
    require(re.fullmatch('[0-9a-f]{40}', base) is not None, 'signed base invalid')
    repo = policy['repository']; ref = 'refs/heads/' + policy['base_branch']
    workflow = f'{repo}/.github/workflows/factory-{role}.yml'
    uri = 'https://github.com/' + workflow + '@' + ref
    invocation = f'https://github.com/{repo}/actions/runs/{run["id"]}/attempts/{run["run_attempt"]}'
    with tempfile.TemporaryDirectory(prefix='factory-attestation-') as folder:
        root = Path(folder); subject = root/'evidence.json'; signature = root/'provenance.sigstore.json'
        subject.write_bytes(evidence); signature.write_bytes(bundle)
        command = ['gh', 'attestation', 'verify', str(subject), '--bundle', str(signature), '--repo', repo,
                   '--cert-identity', uri,
                   '--cert-oidc-issuer', 'https://token.actions.githubusercontent.com',
                   '--source-ref', ref, '--source-digest', base, '--signer-digest', base,
                   '--deny-self-hosted-runners', '--format', 'json']
        env = {key: os.environ[key] for key in ('PATH', 'HOME', 'LANG', 'LC_ALL') if key in os.environ}
        result = (bounded.run if runner is None else runner)(command, env=env, cwd=root, timeout=60, limit=2_000_000)
        require(result.returncode == 0, 'GitHub artifact signature verification failed')
        results = json.loads(result.stdout, object_pairs_hook=no_duplicates)
    require(isinstance(results, list) and len(results) == 1, 'signed root missing or ambiguous')
    verified = results[0]['verificationResult']; cert = verified['signature']['certificate']
    expected = {'issuer': 'https://token.actions.githubusercontent.com', 'subjectAlternativeName': uri,
                'buildSignerURI': uri, 'buildSignerDigest': base,
                'sourceRepositoryURI': 'https://github.com/' + repo, 'sourceRepositoryDigest': base,
                'sourceRepositoryRef': ref, 'buildTrigger': 'pull_request_target',
                'runnerEnvironment': 'github-hosted', 'runInvocationURI': invocation}
    require(all(cert.get(key) == value for key, value in expected.items()), 'immutable signing certificate execution binding differs')
    require(isinstance(verified.get('verifiedTimestamps'), list) and bool(verified['verifiedTimestamps']), 'signed timestamp missing')
    statement = verified['statement']
    require(statement.get('predicateType') == 'https://slsa.dev/provenance/v1', 'unexpected signed statement type')
    subjects = statement.get('subject')
    require(isinstance(subjects, list) and len(subjects) == 1 and subjects[0].get('digest') == {'sha256': hashlib.sha256(evidence).hexdigest()}, 'signed evidence digest differs')

#!/usr/bin/env python3
"""Historical queue completion primitives, not current capability or merge authority.

API: canonical(record), validate_record(bytes, trusted_profile, now=...), and
verify(bytes, bundle, trusted_profile, actual_completed_run, runner=..., now=...).
The explicit profile is a primitive's trusted input; its protected registration
and actual native observations belong to the producer/consumer, not this module.
Original notification counts retain the bounded administrative observation scope;
they do not establish independent Slack readback or exhaustive history coverage.
No predicate claim grants authority. No state is stored and no live CLI exists.
"""
import calendar
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import urlsplit


def require(ok, message):
    if not ok:
        raise ValueError(message)


def fields(value, names):
    require(type(value) is dict and set(value) == set(names.split()), 'historical fields differ')


def integer(value):
    require(type(value) is int and 0 < value < 2**63, 'positive integer required')


def text(value, pattern):
    require(type(value) is str and re.fullmatch(pattern, value) is not None, 'historical string invalid')


def hexstr(value, size):
    text(value, '[0-9a-f]{' + str(size) + '}')


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode('utf-8')


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, 'duplicate historical field')
        result[key] = value
    return result


def decode(raw, limit, canonical_required=False):
    require(type(raw) is bytes and 0 < len(raw) <= limit, 'historical byte bound exceeded')
    try:
        value = json.loads(raw, object_pairs_hook=pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
        require(not canonical_required or canonical(value) == raw, 'noncanonical historical JSON')
        return value
    except (UnicodeError, RecursionError, TypeError, json.JSONDecodeError) as exc:
        raise ValueError('historical JSON invalid') from exc


def stamp(value):
    """Return exact UTC nanoseconds and represented precision, including Go RFC3339Nano."""
    require(type(value) is str, 'historical time invalid')
    match = re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,9}))?(Z|[+-]\d\d:\d\d)', value)
    require(match is not None, 'historical time invalid')
    require(match[3] == 'Z' or (int(match[3][1:3]) < 24 and int(match[3][4:6]) < 60), 'historical offset invalid')
    try:
        base = datetime.fromisoformat(match[1] + ('+00:00' if match[3] == 'Z' else match[3]))
        fraction = match[2] or ''
        return calendar.timegm(base.utctimetuple()) * 10**9 + int(fraction.ljust(9, '0') or '0'), 10**(9-len(fraction))
    except ValueError as exc:
        raise ValueError('historical time invalid') from exc


def clock(now):
    value = datetime.now(timezone.utc) if now is None else now
    require(type(value) is datetime and value.tzinfo is not None, 'aware clock required')
    return calendar.timegm(value.utctimetuple()) * 10**9 + value.microsecond * 1000


def repository(value):
    fields(value, 'name id private')
    text(value['name'], r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+')
    require(len(value['name']) <= 201 and all(part not in ('.', '..') for part in value['name'].split('/')), 'repository name invalid')
    integer(value['id'])
    require(type(value['private']) is bool, 'repository privacy invalid')


def branch(value):
    text(value, r'[A-Za-z0-9][A-Za-z0-9_./-]{0,199}')
    require('..' not in value and '//' not in value and not value.endswith(('/', '.', '.lock')), 'branch invalid')


def source(value):
    hexstr(value['source_sha'], 40)
    text(value['workflow_path'], r'\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml')
    integer(value['workflow_id'])
    runtime = value['runtime']
    require(type(runtime) is dict and 0 < len(runtime) <= 128, 'runtime bound invalid')
    for path, digest in runtime.items():
        text(path, r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*')
        require(all(part not in ('.', '..') for part in path.split('/')), 'runtime path invalid')
        hexstr(digest, 64)
    require(value['workflow_path'] in runtime, 'workflow runtime missing')


def profile(value):
    fields(value, 'schema_version profile_id profile_sha256 status repository branch original producer')
    require(type(value['schema_version']) is int and value['schema_version'] == 1, 'profile version invalid')
    text(value['profile_id'], r'[A-Za-z0-9][A-Za-z0-9_.-]{0,99}')
    hexstr(value['profile_sha256'],64)
    require(value['status'] == 'active', 'historical profile inactive')
    repository(value['repository']); branch(value['branch'])
    for key in ('original', 'producer'):
        fields(value[key], 'source_sha workflow_path workflow_id runtime'); source(value[key])


def validate_record(raw, trusted_profile, *, now=None):
    profile(trusted_profile)
    value = decode(raw, 262144, True)
    fields(value, 'schema_version type purpose profile_id profile_sha256 repository original verification')
    require(type(value['schema_version']) is int and value['schema_version'] == 1, 'historical version invalid')
    require(value['type'] == 'historical-queue-completion' and value['purpose'] == 'historical-operational-acceptance', 'historical purpose differs')
    repository(value['repository']); hexstr(value['profile_sha256'],64)
    require(value['profile_sha256'] == trusted_profile['profile_sha256'], 'historical full profile digest differs')
    require(value['repository'] == trusted_profile['repository'] and value['profile_id'] == trusted_profile['profile_id'], 'historical profile binding differs')
    original = value['original']; verification = value['verification']
    fields(original, 'source_sha workflow_path workflow_id runtime runs state')
    fields(verification, 'source_sha workflow_path workflow_id runtime run_id attempt started_at verified_at')
    for item, expected in ((original, trusted_profile['original']), (verification, trusted_profile['producer'])):
        source(item)
        require(all(item[key] == expected[key] for key in expected), 'historical source differs')
    integer(verification['run_id']); integer(verification['attempt'])
    start = stamp(verification['started_at'])[0]; verified = stamp(verification['verified_at'])[0]
    require(start <= verified <= clock(now), 'verification time invalid')
    runs = original['runs']
    require(type(runs) is list and len(runs) == 3, 'historical runs invalid')
    last = -1; ids = set(); jobs = set()
    for run, role, counts in zip(runs, ('drill', 'recovery', 'repeat'), ([1, 0], [1], [0])):
        fields(run, 'role run_id attempt job_id started_at ended_at log_sha256 notifications')
        require(run['role'] == role, 'historical run order differs')
        for key in ('run_id', 'attempt', 'job_id'): integer(run[key])
        require(run['run_id'] not in ids and run['job_id'] not in jobs, 'historical run duplicate')
        ids.add(run['run_id']); jobs.add(run['job_id']); hexstr(run['log_sha256'], 64)
        low = stamp(run['started_at'])[0]; high = stamp(run['ended_at'])[0]
        require(last <= low <= high <= start, 'historical run time invalid'); last = high
        require(type(run['notifications']) is list and all(type(n) is int for n in run['notifications']) and run['notifications'] == counts, 'historical notification observation differs')
    state = original['state']
    fields(state, 'branch head_sha tree_sha journal_path journal_sha256 lineage_sha256 drill_key recovery_key publication_count')
    branch(state['branch']); require(state['branch'] != trusted_profile['branch'], 'state branch differs')
    for key in ('head_sha', 'tree_sha'): hexstr(state[key], 40)
    for key in ('journal_sha256', 'lineage_sha256', 'drill_key', 'recovery_key'): hexstr(state[key], 64)
    text(state['journal_path'], r'reports/[0-9a-f]{64}\.json')
    integer(state['publication_count']); require(state['publication_count'] <= 24, 'publication bound exceeded')
    return value


def require_cli_version(runner, env, cwd):
    """GHSA-8xvp-7hj6-mcj9 is fixed in gh2.93.0; no native older verification."""
    result = runner(['gh', '--version'], env=env, cwd=cwd, timeout=10, limit=4096)
    require(result.returncode == 0 and type(result.stdout) is bytes, 'gh toolchain unavailable')
    match = re.match(rb'^gh version ([0-9]+)\.([0-9]+)\.([0-9]+)(?:[ \n]|$)', result.stdout)
    require(match is not None and tuple(int(part) for part in match.groups()) >= (2, 93, 0),
            'gh >=2.93.0 required before native attestation verification')


def verify(raw, bundle, trusted_profile, actual_completed_run, *, runner=None, now=None):
    value = validate_record(raw, trusted_profile, now=now)
    require(type(bundle) is bytes and 0 < len(bundle) <= 1000000, 'signature bundle bound exceeded')
    run = actual_completed_run; v = value['verification']; repo = value['repository']['name']
    require(type(run) is dict, 'native run missing')
    for key in ('id', 'run_attempt', 'workflow_id'): integer(run.get(key))
    expected_run = {'id': v['run_id'], 'run_attempt': v['attempt'], 'workflow_id': v['workflow_id'], 'path': v['workflow_path'], 'head_sha': v['source_sha'], 'head_branch': trusted_profile['branch'], 'event': 'workflow_dispatch', 'status': 'completed', 'conclusion': 'success'}
    require(all(run.get(key) == expected for key, expected in expected_run.items()), 'native producer binding differs')
    for key in ('repository', 'head_repository'):
        observed = run.get(key)
        require(type(observed) is dict and type(observed.get('id')) is int and observed['id'] == value['repository']['id'] and observed.get('full_name') == repo, 'native repository differs')
    low = stamp(run.get('run_started_at'))[0]; end, resolution = stamp(run.get('updated_at'))
    require(low == stamp(v['started_at'])[0] and low <= stamp(v['verified_at'])[0] < end + resolution and end <= clock(now), 'native execution time differs')
    _signature(raw,bundle,trusted_profile,v,'workflow_dispatch',low,end+resolution,runner=runner,now=now)
    return value


def _signature(raw, bundle, trusted_profile, v, event, low, high, *, runner=None, now=None):
    require(type(bundle) is bytes and 0 < len(bundle) <= 1000000, 'signature bundle bound exceeded')
    repo = trusted_profile['repository']['name']
    ref = 'refs/heads/' + trusted_profile['branch']; uri = 'https://github.com/' + repo + '/' + v['workflow_path'] + '@' + ref
    with tempfile.TemporaryDirectory(prefix='factory-operational-proof-') as folder:
        root = Path(folder); subject = root / 'historical.json'; signature = root / 'bundle.json'
        subject.write_bytes(raw); signature.write_bytes(bundle)
        command = ['gh', 'attestation', 'verify', str(subject), '--bundle', str(signature), '--repo', repo, '--cert-identity', uri, '--cert-oidc-issuer', 'https://token.actions.githubusercontent.com', '--source-ref', ref, '--source-digest', v['source_sha'], '--signer-digest', v['source_sha'], '--deny-self-hosted-runners', '--format', 'json']
        native_runner = runner is None
        if native_runner:
            spec = importlib.util.spec_from_file_location('operational_bounded', Path(__file__).with_name('factory-bounded-process.py'))
            bounded = importlib.util.module_from_spec(spec); spec.loader.exec_module(bounded)
            runner = bounded.run
        env = {key: os.environ[key] for key in ('PATH', 'HOME', 'LANG', 'LC_ALL') if key in os.environ}
        if native_runner:require_cli_version(runner, env, root)
        result = runner(command, cwd=root, env=env, timeout=60, limit=2000000)
        require(result.returncode == 0, 'native signature verification failed')
        results = decode(result.stdout, 2000000)
    try:
        require(type(results) is list and len(results) == 1, 'verified result ambiguous')
        verified = results[0]['verificationResult']; cert = verified['signature']['certificate']
        expected = {'issuer': 'https://token.actions.githubusercontent.com', 'subjectAlternativeName': uri, 'buildSignerURI': uri, 'buildSignerDigest': v['source_sha'], 'sourceRepositoryURI': 'https://github.com/' + repo, 'sourceRepositoryIdentifier': str(trusted_profile['repository']['id']), 'sourceRepositoryDigest': v['source_sha'], 'sourceRepositoryRef': ref, 'buildTrigger': event, 'runnerEnvironment': 'github-hosted', 'runInvocationURI': f'https://github.com/{repo}/actions/runs/{v["run_id"]}/attempts/{v["attempt"]}'}
        require(type(cert) is dict and all(cert.get(key) == expected_value for key, expected_value in expected.items()), 'verified certificate binding differs')
        statement = verified['statement']; subjects = statement.get('subject')
        require(statement.get('_type') == 'https://in-toto.io/Statement/v1' and statement.get('predicateType') == 'https://slsa.dev/provenance/v1', 'signed statement type differs')
        require(type(subjects) is list and len(subjects) == 1 and subjects[0].get('digest') == {'sha256': hashlib.sha256(raw).hexdigest()}, 'signed historical digest differs')
        timestamps = verified['verifiedTimestamps']
        require(type(timestamps) is list and 0 < len(timestamps) <= 32, 'verified timestamp missing')
        for timestamp in timestamps:
            require(type(timestamp) is dict and timestamp.get('type') in ('Tlog', 'TimestampAuthority'), 'verified timestamp type invalid')
            parsed = urlsplit(timestamp.get('uri', ''))
            require(parsed.scheme == 'https' and bool(parsed.hostname) and not parsed.username and not parsed.password and not parsed.fragment, 'verified timestamp URI invalid')
            signed = stamp(timestamp.get('timestamp'))[0]
            require(low <= stamp(v['verified_at'])[0] <= signed and (high is None or signed < high) and signed <= clock(now), 'verified timestamp outside execution')
    except (KeyError, TypeError, AttributeError) as exc:
        raise ValueError('verified result malformed') from exc
    return None


def validate_completion(raw, trusted_profile, *, now=None):
    """Purpose-limited observation of an already completed upstream producer.

    No final status of this observer is asserted or recursively required.
    trusted_profile.upstream/observer are independently approved exact sources.
    """
    fields(trusted_profile, 'schema_version profile_id profile_sha256 status repository branch upstream observer')
    translated = {key:trusted_profile[key] for key in ('schema_version','profile_id','profile_sha256','status','repository','branch')}
    translated.update(original=trusted_profile['upstream'],producer=trusted_profile['observer'])
    profile(translated)
    value = decode(raw,262144,True)
    fields(value,'schema_version type purpose profile_id profile_sha256 repository upstream verification')
    require(type(value['schema_version']) is int and value['schema_version'] == 1 and value['type'] == 'historical-queue-completion-observation' and value['purpose'] == 'historical-operational-acceptance', 'completion purpose/version differs')
    repository(value['repository']); hexstr(value['profile_sha256'],64)
    for key in ('profile_id','profile_sha256','repository'):
        require(value[key] == trusted_profile[key], 'completion profile binding differs')
    upstream = value['upstream']; observer = value['verification']
    fields(upstream,'record_sha256 bundle_sha256 source_sha workflow_path workflow_id run_id attempt started_at completed_at status conclusion job_id artifact_id artifact_sha256')
    for key in ('record_sha256','bundle_sha256','artifact_sha256'):hexstr(upstream[key],64)
    for key in ('run_id','attempt','workflow_id','job_id','artifact_id'):integer(upstream[key])
    require(upstream['status'] == 'completed' and upstream['conclusion'] == 'success', 'upstream completion not successful')
    require(all(upstream[key] == trusted_profile['upstream'][key] for key in ('source_sha','workflow_path','workflow_id')), 'upstream approved source differs')
    fields(observer,'source_sha workflow_path workflow_id runtime run_id attempt started_at verified_at')
    source(observer); integer(observer['run_id']); integer(observer['attempt'])
    require(all(observer[key] == trusted_profile['observer'][key] for key in trusted_profile['observer']), 'completion observer source differs')
    require(stamp(upstream['started_at'])[0] <= stamp(upstream['completed_at'])[0] <= stamp(observer['verified_at'])[0] <= clock(now), 'completion observation clock differs')
    require(stamp(observer['started_at'])[0] <= stamp(observer['verified_at'])[0] and (upstream['run_id'],upstream['attempt']) != (observer['run_id'],observer['attempt']), 'completion observer identity/clock differs')
    return value


def verify_completion(raw, bundle, trusted_profile, *, runner=None, now=None):
    value = validate_completion(raw,trusted_profile,now=now)
    observer = value['verification']
    _signature(raw,bundle,trusted_profile,observer,'workflow_run',stamp(observer['started_at'])[0],None,runner=runner,now=now)
    return value


def verify_durable(raw, bundle, completion_raw, completion_bundle, producer_profile, completion_profile, *, runner=None, now=None):
    """Replay both native certificates without permanently available run APIs."""
    require(type(bundle) is bytes and 0 < len(bundle) <= 1000000, 'signature bundle bound exceeded')
    value = validate_record(raw,producer_profile,now=now)
    completed = verify_completion(completion_raw,completion_bundle,completion_profile,runner=runner,now=now)
    require(all(completed[key] == value[key] for key in ('profile_id','profile_sha256','repository')), 'durable profile differs')
    upstream = completed['upstream']; v = value['verification']
    require(upstream['record_sha256'] == hashlib.sha256(raw).hexdigest() and upstream['bundle_sha256'] == hashlib.sha256(bundle).hexdigest(), 'durable subject/bundle digest differs')
    require(all(upstream[key] == v[key] for key in ('source_sha','workflow_path','workflow_id','run_id','attempt','started_at')), 'durable upstream identity differs')
    end,resolution = stamp(upstream['completed_at'])
    require(stamp(v['verified_at'])[0] < end+resolution, 'durable upstream completion clock differs')
    _signature(raw,bundle,producer_profile,v,'workflow_dispatch',stamp(v['started_at'])[0],end+resolution,runner=runner,now=now)
    return value


if __name__ == '__main__':
    raise SystemExit('Primitive API only; historical producer/live capability not implemented here')

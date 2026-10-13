#!/usr/bin/env python3
"""Protected worker contract validation only; no worker process is enabled here."""
import hashlib
import types
import json
import os
from pathlib import Path
import re
import stat

CAPABILITIES = ['foreground', 'model-selection', 'structured-output', 'config-isolation',
                'hook-failure-block', 'guarded-read-write-edit',
                'unmanaged-instructions-excluded', 'auto-memory-disabled',
                'managed-policy-compatible']
CLOSURE = ('factory-intake-worker.py', 'factory-intake.py', 'factory-runtime.py',
           'factory-routing.py', 'factory-supervisor.py', 'factory-bounded-process.py',
           'factory-worker-guard.py')
GUARD_FIELDS = {'native_executable', 'interpreter', 'version', 'capabilities', 'observation'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def decode(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate worker contract field')
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: require(False, 'nonfinite worker value'))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                      allow_nan=False)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def path_value(value):
    require(isinstance(value, str), 'worker artifact path invalid')
    path = Path(value)
    require(path.is_absolute() and path.resolve() == path and not path.is_symlink(),
            'worker artifact path must be canonical')
    require(not any(part in {'.env', '.git', '.aws', '.ssh', 'credentials', 'secrets'}
                    or part.startswith('.env.') for part in path.parts),
            'worker artifact secret path forbidden')
    return path


def stable_identity(info):
    return tuple(getattr(info, name) for name in
                 ('st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_gid', 'st_nlink',
                  'st_size', 'st_mtime_ns', 'st_ctime_ns'))


def read_artifact(value, *, private=False, executable=False, roots=(), digest_only=False):
    path = path_value(value)
    require(all(path != root and root not in path.parents for root in roots),
            'worker artifact cannot be candidate/authority owned')
    before = path.stat()
    maximum = 512 * 1024 * 1024 if executable else 8000000
    require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
            and before.st_uid in {0, os.getuid()} and not before.st_mode & 0o022
            and before.st_size <= maximum, 'worker artifact ownership/type invalid')
    if private:
        parent = path.parent.stat()
        require(before.st_uid == os.getuid() and stat.S_IMODE(before.st_mode) == 0o600
                and parent.st_uid == os.getuid() and stat.S_IMODE(parent.st_mode) == 0o700,
                'worker private artifact permissions invalid')
    if executable:
        require(os.access(path, os.X_OK), 'worker executable unavailable')
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
                 | getattr(os, 'O_NONBLOCK', 0))
    try:
        opened = os.fstat(fd)
        require(stable_identity(opened) == stable_identity(before), 'worker artifact identity changed')
        hashed = hashlib.sha256()
        chunks = []
        size = 0
        with os.fdopen(fd, 'rb', closefd=False) as source:
            while True:
                chunk = source.read(min(1024 * 1024, maximum + 1 - size))
                if not chunk:
                    break
                size += len(chunk)
                require(size <= maximum, 'worker artifact bound exceeded')
                if digest_only:
                    hashed.update(chunk)
                else:
                    chunks.append(chunk)
        require(stable_identity(os.fstat(fd)) == stable_identity(opened)
                and not path.is_symlink() and stable_identity(path.stat()) == stable_identity(opened),
                'worker artifact changed while reading')
        return hashed.hexdigest() if digest_only else b''.join(chunks)
    finally:
        os.close(fd)


def load_worker_contract(contract_path, task_id):
    """Read owner-controlled configuration and validate exact primary; never probe.

    The caller must obtain the contract binding from the protected installation
    registry. This pure validator does not authenticate a caller-selected path,
    authorize a task claim, or certify actual native hook capabilities.
    """
    raw = read_artifact(str(contract_path), private=True)
    contract = decode(raw)
    require(isinstance(contract, dict) and type(contract.get('enabled')) is bool,
            'worker intake contract invalid')
    if not contract['enabled']:
        fields = {'schema_version', 'enabled', 'repository', 'candidate_root', 'authority_root',
                  'database', 'profile', 'policy', 'trusted_files', 'limits'}
        require(set(contract) == fields and type(contract['schema_version']) is int
                and contract['schema_version'] == 1 and contract['trusted_files'] == {}
                and all(contract[key] is None for key in fields -
                        {'schema_version', 'enabled', 'trusted_files', 'limits'}),
                'disabled worker contract must remain neutral')
        limits = contract['limits']
        ceilings = {'request_chars': 20000, 'context_bytes': 500000, 'output_bytes': 65536, 'assessment_seconds': 60}
        require(isinstance(limits, dict) and set(limits) == set(ceilings), 'worker neutral budgets invalid')
        for key, maximum in ceilings.items():
            require(type(limits[key]) is int and (1024 if key == 'output_bytes' else 1) <= limits[key] <= maximum,
                    'worker neutral budget invalid')
        return None
    roots = tuple(path_value(contract.get(key)) for key in ('candidate_root', 'authority_root'))
    pins = contract.get('trusted_files')
    require(isinstance(pins, dict) and pins, 'worker protected closure missing')
    required = {str(Path(__file__).resolve().with_name(name)) for name in CLOSURE}
    required.update(contract.get(key) for key in ('profile', 'policy'))
    require(required <= set(pins), 'worker recursive closure must be pinned before imports')
    artifacts = {}
    for name, expected in pins.items():
        require(isinstance(expected, str) and re.fullmatch('[a-f0-9]{64}', expected),
                'worker protected pin invalid')
        artifacts[name] = read_artifact(name, roots=roots)
        require(digest(artifacts[name]) == expected, 'worker protected pin changed')
    # No repository-local import occurs before the complete declared closure is checked.
    def imported(name):
        path = Path(__file__).with_name(name)
        module = types.ModuleType('protected_worker_' + name.replace('-', '_'))
        module.__file__ = str(path)
        exec(compile(artifacts[str(path)], str(path), 'exec'), module.__dict__)
        return module
    core = imported('factory-intake.py')
    core.load_contract(contract_path)
    routing = imported('factory-routing.py')
    profile = decode(read_artifact(contract['profile'], private=True, roots=roots))
    policy = decode(read_artifact(contract['policy'], private=True, roots=roots))
    routing.validate(profile)
    require(profile['enabled'] is True and profile['repository'] == contract['repository']
            and policy.get('repository') == contract['repository'], 'worker repository differs')
    control = policy.get('runtime')
    require(isinstance(control, dict) and control.get('routing_profile_sha256') ==
            digest(canonical(profile).encode()), 'worker profile binding differs')
    require(isinstance(task_id, str) and re.fullmatch(r'T-[1-9][0-9]*', task_id)
            and isinstance(control.get('roles_by_task'), dict)
            and control['roles_by_task'].get(task_id) == 'implementation',
            'worker requires protected implementation task role')
    primary = profile['roles']['implementation']['primary']
    runtime = profile['runtimes'][primary]
    require(runtime['kind'] == 'claude-cli' and runtime['billing'] == 'subscription'
            and runtime['location'] == 'local', 'worker primary runtime unsupported')
    guard = control.get('worker_guard')
    require(isinstance(guard, dict) and set(guard) == GUARD_FIELDS,
            'worker guard declaration missing or invalid')
    version = guard['version']
    require(isinstance(version, str) and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version)
            and tuple(map(int, version.split('.'))) >= (2, 1, 295),
            'worker requires observed fail-closed native version')
    require(isinstance(guard['capabilities'], list) and guard['capabilities'] == CAPABILITIES,
            'worker observed capability contract differs')
    observation = guard['observation']
    require(isinstance(observation, dict) and set(observation) == {'path', 'sha256'},
            'worker observation binding invalid')
    native = str(path_value(guard['native_executable']))
    interpreter = str(path_value(guard['interpreter']))
    proof_path = str(path_value(observation['path']))
    worker_pins = {str(Path(__file__).resolve().with_name(name)) for name in CLOSURE}
    worker_pins.add(proof_path)
    runtime_pins = runtime['probe']['trusted_files']
    require(worker_pins <= set(pins) and worker_pins | {native, interpreter} <= set(runtime_pins),
            'worker runtime and controller closure pins missing')
    # Large executables have an indirect protected pin chain: controller pins the
    # complete profile/policy and proof; profile pins the actual executable bytes.
    # JSON/source/proof artifacts remain directly pinned in both stores (8 MB).
    for name, expected in runtime_pins.items():
        if name in {native, interpreter}:
            observed_digest = read_artifact(name, executable=True, digest_only=True, roots=roots)
        else:
            require(name in pins and pins[name] == expected,
                    'worker primary pin lacks protected controller agreement')
            observed_digest = digest(read_artifact(name, roots=roots))
        require(observed_digest == expected, 'worker primary pin changed')
    observed = decode(read_artifact(proof_path, private=True, roots=roots))
    expected = {'schema_version': 1, 'runtime': primary, 'model': runtime['model'],
                'native_sha256': runtime_pins[native], 'interpreter_sha256': runtime_pins[interpreter],
                'version': version, 'capabilities': guard['capabilities']}
    require(isinstance(observed, dict) and type(observed.get('schema_version')) is int and observed == expected
            and observation['sha256'] == pins[proof_path], 'worker observed evidence differs')
    argv = [interpreter, '-I', '-S', str(Path(__file__).resolve()), '--safe-mode',
            '--model', '{model}', '--output-format', 'json', '--print']
    require(runtime['command'] == argv, 'worker wrapper argv must match exact clean contract')
    # Recheck the bootstrap closure after imports and dependent validation.
    require(read_artifact(str(contract_path), private=True) == raw, 'worker contract changed')
    for name, expected_pin in pins.items():
        require(digest(read_artifact(name, roots=roots)) == expected_pin,
                'worker closure changed during validation')
    for name in {native, interpreter}:
        require(read_artifact(name, executable=True, digest_only=True, roots=roots) == runtime_pins[name],
                'worker executable changed during validation')
    return {'runtime': primary, 'model': runtime['model'], 'repository': contract['repository'],
            'profile_sha256': control['routing_profile_sha256'],
            'worker_guard_sha256': digest(canonical(guard).encode()),
            'native_executable': native, 'interpreter': interpreter,
            'capability_evidence': 'protected-observation'}

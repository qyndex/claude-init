#!/usr/bin/env python3
"""Report missing activation prerequisites without exposing credentials."""
import argparse
import json
import re
import os
from pathlib import Path
import sys


def reporting_readiness(config, source_api, state_api, *, interval_end=None,
                        history_head=None, campaign=None, page_size=100,
                        interval_scoped=False):
    """Observe existing protected proof without creating progress or authority."""
    # Reporting-only imports leave the merge emitter's execution closure unchanged.
    import importlib.util
    import sqlite3
    import tempfile
    spec = importlib.util.spec_from_file_location('preflight_reporting', Path(__file__).with_name('factory-reporting-receipts.py'))
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    archive = helper.archive
    checks = {name: {'status': 'not_checked'} for name in (
        'protected_origin', 'retained_interval', 'installed_app',
        'private_capability', 'native_cadence', 'operator_cutover')}
    result = {'scope': 'reporting-readiness', 'checks': checks}
    current = 'protected_origin'
    try:
        selected = config['receipt_archive']; policy = config['receipt_policy']
        archive.require(source_api.repo == state_api.repo == config['repository'] == policy['repository'], 'readiness repository differs')
        archive.require(selected['trust_mode'] == 'profile', 'readiness profile mode required')
        state = helper.ReadOnly(state_api); source = helper.Source(source_api)
        approval = Path(selected['approval_path']); trust = Path(selected['trust_path'])
        approval_bytes = approval.read_bytes(); trust_bytes = trust.read_bytes()
        archive.receipts.load_receipt_trust(trust, state.repo, mode='profile')
        anchor = archive.verify_bootstrap(state, approval)
        archive.require(selected['store']['repository'] == state.repo and
                        (not anchor['private'] or selected['store']['visibility'] == 'private'), 'readiness private store required')
        result['anchor'] = anchor
        checks[current] = {'status': 'passed'}
        selectors = (interval_end, history_head, campaign)
        if any(value is not None for value in selectors):
            current = 'retained_interval'
        archive.require(all(value is None for value in selectors) or all(value is not None for value in selectors), 'readiness interval selectors incomplete')
        if interval_end is not None:
            stream = archive.archive_stream(state.repo)
            with tempfile.TemporaryDirectory(prefix='factory-readiness-') as temporary:
                projection = archive.reconstruct_interval(state, policy, Path(temporary)/'receipts.sqlite', trust,
                    selected['store'], approval, stream, interval_end=interval_end,
                    history_head=history_head, campaign=campaign, interval_scoped=interval_scoped)
                archive.require(projection.get('projection_complete') is True, 'readiness retained projection incomplete')
                observed = helper.discovery.coverage(source, state, policy, trust, selected['store'], approval, stream,
                    interval_end=interval_end, projection_end=interval_end, history_head=history_head,
                    campaign=campaign, page_size=page_size, interval_scoped=interval_scoped)
                archive.require(all(observed.get(key) is True for key in (
                    'coverage_complete', 'source_partition_complete', 'frozen_projection_complete')) and
                    observed.get('verified_until') == interval_end and observed.get('gaps') == [] and
                    observed.get('task_credit') is False and observed.get('all_history_complete') is False and
                    observed.get('repository') == state.repo and observed.get('coverage_from') == anchor['coverage_from'],
                    'readiness retained coverage incomplete')
            checks[current] = {'status': 'passed', 'verified_until': interval_end}
        archive.require(archive.verify_bootstrap(state, approval) == anchor and
                        approval.read_bytes() == approval_bytes and trust.read_bytes() == trust_bytes,
                        'readiness protected origin or trust changed')
    except (ValueError, OSError, KeyError, TypeError, RuntimeError, sqlite3.Error):
        checks[current] = {'status': 'failed', 'reason': 'protected reporting validation failed'}
    return result


def reporting_main(args):
    import importlib.util
    import sqlite3
    spec = importlib.util.spec_from_file_location('preflight_transport', Path(__file__).with_name('factory-reporting-transport.py'))
    transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
    try:
        selected = transport.build_config(os.environ)
        transport.require(selected['writer_mode'] == 'app', 'explicit reporting App selection required')
        config = transport.state.digest.coordinator.contract.load(args.reporting_config)
        config = transport.attach_reporting_context(config)
        api = transport.create_api(os.environ)
        result = reporting_readiness(config, api, api, interval_end=args.interval_end,
            history_head=args.history_head, campaign=args.campaign, interval_scoped=True)
    except (ValueError, OSError, KeyError, TypeError, RuntimeError, sqlite3.Error):
        result = {'scope': 'reporting-readiness', 'checks': {'configuration': {
            'status': 'failed', 'reason': 'selected reporting configuration unavailable or invalid'}}}
    print(json.dumps(result, indent=2))
    return 1 if any(check['status'] == 'failed' for check in result['checks'].values()) else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--policy', type=Path)
    mode.add_argument('--reporting-config', type=Path)
    parser.add_argument('--interval-end')
    parser.add_argument('--history-head')
    parser.add_argument('--campaign')
    args = parser.parse_args()
    if args.reporting_config is not None:
        selectors = (args.interval_end, args.history_head, args.campaign)
        if any(value is not None for value in selectors) and any(value is None for value in selectors):
            parser.error('reporting proof requires all three interval selectors')
        return reporting_main(args)
    if any(value is not None for value in (args.interval_end, args.history_head, args.campaign)):
        parser.error('interval selectors require --reporting-config')
    policy = json.loads(args.policy.read_text())
    missing = []
    if policy.get('enabled') is not True:
        missing.append('operator-approved policy activation')
    app = policy.get('app_id')
    if type(app) is not int or app <= 0 or os.environ.get('FACTORY_APP_ID') != str(app):
        missing.append('matching dedicated GitHub App ID')
    if os.environ.get('FACTORY_KEY_PRESENT') != 'true':
        missing.append('private key in protected factory-authority environment')
    if not policy.get('required_checks'):
        missing.append('required check producer pins')
    if not policy.get('specs'):
        missing.append('approved spec revision, AC set and path scope')
    producers = policy.get('producers', {})
    for role in ('verification', 'review'):
        definition = producers.get(role, {})
        if type(definition.get('workflow_id')) is not int or definition['workflow_id'] <= 0 or not definition.get('trusted_files'):
            missing.append(f'{role} authenticated workflow and runtime hashes')
        expected = 'factory-verification' if role == 'verification' else 'factory-independent-review'
        if definition.get('event') != 'pull_request_target' or definition.get('check_name') != expected:
            missing.append(f'{role} protected event and candidate-check identity')
        paths = {f'.github/workflows/factory-{role}.yml', '.claude/scripts/factory-producer.py',
                 '.claude/scripts/factory-producer-check.py', '.claude/scripts/factory-coordinator.py', '.claude/scripts/factory-provenance.py',
                 '.claude/scripts/validate-candidate-evidence.py', '.claude/scripts/factory-bounded-process.py',
                 '.claude/scripts/factory-policy-observation.py', '.claude/scripts/factory-font-adapter.py'}
        if not paths <= set(definition.get('trusted_files', {})):
            missing.append(f'{role} complete transitive runtime hashes')
    for sid, approved in policy.get('specs', {}).items():
        profile = approved.get('sandbox_profile', 'strict-interpreted-v1')
        if not isinstance(profile, str) or profile not in ('strict-interpreted-v1', 'native-build-v1'):
            missing.append(f'spec {sid} supported sandbox profile')
        acs = approved.get('ac_ids', [])
        if not approved.get('path') or not acs or not approved.get('allowed_paths') or set(approved.get('acceptance_commands', {})) != set(acs):
            missing.append(f'spec {sid} bytes, scope and per-AC acceptance commands')
        if re.fullmatch(r'[A-Za-z0-9./:_-]+@sha256:[0-9a-f]{64}', approved.get('verification_image', '')) is None:
            missing.append(f'spec {sid} digest-pinned verification runtime')
    print(json.dumps({'ready': not missing, 'missing': missing}, indent=2))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())

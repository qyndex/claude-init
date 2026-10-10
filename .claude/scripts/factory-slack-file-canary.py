#!/usr/bin/env python3
"""One initial file canary allocation; subsequent runs only reconcile its exact receipt."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('state', Path(__file__).with_name('factory-git-state.py'))
state = importlib.util.module_from_spec(spec); spec.loader.exec_module(state)
slack = state.slack
require = state.require


def run(config, api, client, run_id, attempt):
    require(config.get('enabled') is True and config.get('attachments_enabled') is True, 'file canary requires explicit attachment enablement')
    require(api.repo == config['repository'], 'foreign canary repository')
    require(type(run_id) is int and run_id > 0 and type(attempt) is int and attempt > 0, 'run identity required')
    slack.preflight(client, config['team_id'], config['destination'])
    client.verify_attachment_scopes()
    payload = state.canonical({'repository': config['repository'], 'destination': config['destination'],
                              'display_from': 'ATTACHMENT ACTIVATION CANARY',
                              'display_until': 'Verification only; daily reporting state is unchanged', 'merges': []})
    key = state.hashlib.sha256(state.canonical(['file-canary-v1', config['repository'], config['team_id'], config['destination']]).encode()).hexdigest()
    transport = slack.attachment_module().Attachment(client, config['team_id'], config['destination'], key, payload)
    receipt = transport.lookup(key)['receipt']
    if receipt is not None:
        return {'status': 'verified-existing', 'receipt': receipt}
    # Workflow run history is an allocation fence, not evidence that an earlier upload failed.
    # Any previous run or retry without a remote receipt requires operator reconciliation.
    require(attempt == 1, 'uncertain canary attempt; reconcile without allocating another file')
    runs = api.request(f'repos/{api.repo}/actions/workflows/factory-slack-file-canary.yml/runs?per_page=100')
    require(type(runs.get('total_count')) is int and runs['total_count'] == 1 and
            isinstance(runs.get('workflow_runs'), list) and len(runs['workflow_runs']) == 1 and
            runs['workflow_runs'][0].get('id') == run_id and
            runs['workflow_runs'][0].get('head_branch') == config['branch'] and
            runs['workflow_runs'][0].get('event') == 'workflow_dispatch',
            'previous or ambiguous canary run; reconcile without allocating another file')
    receipt = transport.send(key, payload, config['destination'])
    require(transport.lookup(key)['receipt'] == receipt, 'file canary readback differs')
    return {'status': 'verified-new', 'receipt': receipt}


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--config', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        config = json.loads(Path(args.config).read_text(), object_pairs_hook=slack.digest.coordinator.contract.no_duplicate_keys)
        result = run(config, state.API(config['repository'], os.environ.get('GH_TOKEN')), slack.http_client(config),
                     int(os.environ.get('GITHUB_RUN_ID', '0')), int(os.environ.get('GITHUB_RUN_ATTEMPT', '0')))
        Path(args.output).write_text(state.canonical(result)); print(state.canonical(result))
        return 0
    except (ValueError, KeyError, TypeError, OSError) as error:
        # Exception text is never logged: it may contain a URL or private response.
        reasons = {
            'previous or ambiguous canary run; reconcile without allocating another file': 'allocation-fence',
            'Slack attachment API failed; inspect scopes and authoritative history': 'file-api',
            'Slack attachment URL rejected': 'file-url',
            'Slack file download identity differs': 'download-identity',
            'Slack upload URL/bytes rejected': 'upload-url',
            'Slack attachment transfer uncertain; reconcile before retry': 'file-transfer',
            'Slack attachment share sender/time differs': 'share-sender',
            'Slack attachment identity/size/privacy differs': 'file-metadata',
            'Slack attachment destination differs': 'share-destination',
            'Slack attachment content differs': 'file-bytes',
            'Slack attachment share not visible; preserve uncertainty': 'share-not-visible',
            'Slack attachment share ambiguous': 'ambiguous-share',
            'Slack workspace/bot differs': 'bot-identity',
            'Slack file permissions unavailable; add files:read and files:write and reinstall the app': 'file-scopes',
        }
        reason = reasons.get(str(error), 'blocked')
        print('File canary blocked (' + reason + '); preserve run history and reconcile before retry.', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())

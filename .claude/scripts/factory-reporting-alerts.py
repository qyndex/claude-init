#!/usr/bin/env python3
"""GitHub-only reporting alerts with durable intents and exact Slack reconciliation."""
import argparse
import copy
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys

spec = importlib.util.spec_from_file_location('watchdog', Path(__file__).with_name('factory-reporting-watchdog.py'))
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
state = w.state
require = state.require


def text(config, row):
    repo = config['repository']; kind = row['kind']
    if kind == 'overdue':
        message = 'Morning digest overdue after configured grace: ' + row['cutoff']
    elif kind == 'failure':
        message = 'Reporting workflow failed: https://github.com/' + repo + '/actions/runs/' + str(row['run_id'])
    elif kind == 'drill':
        message = 'Reporting alert verification drill; this is not an actual reporting outage.'
    else:
        message = 'Reporting recovery: the current digest and its exact Slack receipt are verified. Incident ' + row['incident'][:12]
    return 'Factory reporting — ' + repo + '\n' + message


class Alert:
    def __init__(self, client, config, row):
        self.client = client; self.config = config; self.row = row
        identity = client.call('auth.test', {})
        require(identity.get('team_id') == config['team_id'] and identity.get('bot_id'), 'alert workspace/bot differs')
        self.bot = identity['bot_id']; self.text = text(config, row)
        self.metadata = {'event_type': 'factory_reporting_alert_v1', 'event_payload': {
            'key': row['key'], 'text_sha256': state.hashlib.sha256(self.text.encode()).hexdigest()}}

    def lookup(self):
        cursor = ''; seen = set(); matches = []
        for _ in range(100):
            body = {'channel': self.config['destination'], 'limit': 100, 'include_all_metadata': True}
            if cursor: body['cursor'] = cursor
            page = self.client.call('conversations.history', body)
            require(isinstance(page.get('messages'), list), 'alert history unavailable')
            for message in page['messages']:
                metadata = message.get('metadata')
                payload = metadata.get('event_payload') if isinstance(metadata, dict) else None
                if isinstance(metadata, dict) and metadata.get('event_type') == 'factory_reporting_alert_v1' and isinstance(payload, dict) and payload.get('key') == self.row['key']:
                    require(message.get('bot_id') == self.bot and metadata == self.metadata and
                            state.slack.receipt_text_matches(self.text, message.get('text')) and
                            re.fullmatch(r'[0-9]+\.[0-9]{1,6}', message.get('ts', '')), 'alert remote receipt differs')
                    matches.append(message['ts'])
            cursor = page.get('response_metadata', {}).get('next_cursor', '')
            if not cursor:
                require(not page.get('has_more') and len(matches) <= 1, 'alert history incomplete or ambiguous')
                return matches[0] if matches else None
            require(cursor not in seen, 'alert history cursor repeats'); seen.add(cursor)
        raise ValueError('alert history bound exceeded')

    def send(self):
        result = self.client.call('chat.postMessage', {'channel': self.config['destination'], 'text': self.text,
                                 'metadata': self.metadata, 'unfurl_links': False, 'unfurl_media': False})
        require(result.get('channel') == self.config['destination'], 'alert response channel differs')
        receipt = self.lookup(); require(receipt is not None, 'alert send uncertain; reconcile before retry')
        return receipt


def failure(config, api, run_id):
    require(type(run_id) is int and run_id > 0 and api.repo == config['repository'], 'failed run source invalid')
    run = api.request(f'repos/{api.repo}/actions/runs/{run_id}')
    workflow = api.request(f'repos/{api.repo}/actions/workflows/factory-hosted-digest.yml')
    require(run.get('id') == run_id and run.get('workflow_id') == workflow.get('id') and
            workflow.get('path') == '.github/workflows/factory-hosted-digest.yml' and
            run.get('repository', {}).get('full_name') == api.repo and run.get('head_repository', {}).get('full_name') == api.repo and
            run.get('head_branch') == config['branch'] and run.get('event') in {'schedule','workflow_dispatch'} and
            run.get('status') == 'completed' and run.get('conclusion') in {'failure','timed_out'}, 'untrusted or nonfailed reporting run')
    require(type(run.get('run_attempt')) is int and run['run_attempt'] > 0, 'failed run attempt invalid')
    return state.digest.stamp(state.digest.instant(run['created_at'])), run['run_attempt']


def run(config, api, client, now, *, failed_run=None, drill_run=None):
    require(config.get('enabled') is True and config.get('monitor_enabled') is True and api.repo == config['repository'] == config['state_repository'], 'reporting alerts disabled or foreign')
    require(now.tzinfo is not None and re.fullmatch(r'T[A-Z0-9]+', config.get('team_id','')) and re.fullmatch(r'[CG][A-Z0-9]+', config.get('destination','')), 'alert clock/destination invalid')
    require(failed_run is None or drill_run is None, 'conflicting alert invocation')
    cutoff, attempt = failure(config, api, failed_run) if failed_run is not None else (None, None)
    if cutoff is not None: require(state.digest.instant(cutoff) <= now, 'failed run is in the future')
    if drill_run is not None: require(type(drill_run) is int and drill_run > 0, 'drill identity invalid')
    health = w.inspect(config, api, client, now)
    stream = state.hashlib.sha256(state.canonical([config['repository'],config['destination'],config['branch']]).encode()).hexdigest()
    checkpoint = state.GitState(api,config['state_branch'],stream,config.get('bootstrap_sha'),config.get('policy_approvals'))
    require(checkpoint.head == health['checkpoint_sha'], 'health checkpoint changed; recheck before alert')
    document = json.loads(checkpoint.bytes, object_pairs_hook=state.digest.coordinator.contract.no_duplicate_keys)
    state.validate(document,config['repository'],stream)
    journal = document.setdefault('alerts', [])
    def persist():
        state.validate(document, config['repository'], stream); checkpoint.checkpoint(state.canonical(document).encode())
    # Every restart must reconcile unfinished sends before considering any new notification.
    for row in journal:
        if row['status'] != 'confirmed':
            receipt = Alert(client,config,row).lookup()
            if receipt is None:
                row['status']='uncertain'; persist(); raise ValueError('alert send uncertain; no automatic resend')
            row['status']='confirmed'; row['message_id']=receipt; persist()
    def emit(kind, cut, run_id=None, incident=None, run_attempt=None):
        key=state.alert_key(stream,kind,cut,run_id,incident,run_attempt)
        if any(row['key']==key for row in journal): return False
        closed={row['incident'] for row in journal if row['kind']=='recovery'}
        if kind in {'overdue','failure'} and any(row['kind']==kind and row['key'] not in closed for row in journal): return False
        row={'key':key,'kind':kind,'incident':incident or key,'cutoff':cut,'run_id':run_id,'run_attempt':run_attempt,'status':'pending','message_id':None}
        journal.append(row); persist()
        try: receipt=Alert(client,config,row).send()
        except Exception:
            row['status']='uncertain'; persist(); raise
        row['status']='confirmed';row['message_id']=receipt;persist();return True
    sent=0
    if failed_run is not None:
        sent+=emit('failure',cutoff,failed_run,run_attempt=attempt)
    elif drill_run is not None:
        sent+=emit('drill',state.digest.stamp(now),drill_run)
    elif health['status']=='missed':
        sent+=emit('overdue',health['expected_cutoff'])
    elif health['status']=='current' and health['latest_receipt_verified'] is True:
        recovered={row['incident'] for row in journal if row['kind']=='recovery'}
        for row in list(journal):
            if row['kind']!='recovery' and row['key'] not in recovered:
                require(Alert(client,config,row).lookup()==row['message_id'], 'incident receipt no longer verifiable')
                sent+=emit('recovery',health['expected_cutoff'],incident=row['key'])
    return {'schema_version':1,'health':health['status'],'notifications':sent,'checkpoint_sha':checkpoint.head}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);parser.add_argument('--failed-run',type=int);parser.add_argument('--drill-run',type=int)
    args=parser.parse_args();config=state.digest.coordinator.contract.load(Path(args.config))
    api=state.API(config['repository'],os.environ.get('FACTORY_REPORTING_STATE_TOKEN') or os.environ.get('GH_TOKEN'))
    result=run(config,api,state.slack.http_client(config),datetime.now(timezone.utc),failed_run=args.failed_run,drill_run=args.drill_run)
    print(state.canonical(result));return 0


if __name__=='__main__':
    try:sys.exit(main())
    except (ValueError,KeyError,TypeError,OSError,sqlite3.Error,subprocess.SubprocessError):
        print('Reporting alert blocked; preserve state and inspect GitHub run before retry.',file=sys.stderr);sys.exit(2)

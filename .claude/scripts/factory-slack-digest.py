#!/usr/bin/env python3
"""Protected local morning runner and conservative Slack delivery adapter."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import sqlite3
import urllib.error
import urllib.parse
import urllib.request

spec = importlib.util.spec_from_file_location('digest', Path(__file__).with_name('factory-digest.py'))
digest = importlib.util.module_from_spec(spec); spec.loader.exec_module(digest)
require = digest.require


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class SlackHTTP:
    def __init__(self):
        self.token = os.environ.get('FACTORY_SLACK_BOT_TOKEN')
        require(self.token and self.token.startswith('xoxb-'), 'Slack bot credential unavailable')
        self.opener = urllib.request.build_opener(NoRedirect())

    def call(self, method, body):
        require(method in {'auth.test', 'chat.postMessage', 'conversations.history'}, 'unsupported Slack method')
        url = 'https://slack.com/api/' + method
        encoded = json.dumps(body).encode()
        if method == 'conversations.history':
            url += '?' + urllib.parse.urlencode(body); encoded = None
        request = urllib.request.Request(url, data=encoded, headers={
            'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/json; charset=utf-8'})
        try:
            with self.opener.open(request, timeout=15) as response:
                data = response.read(2_000_001)
            require(len(data) <= 2_000_000, 'Slack response too large')
            result = json.loads(data, object_pairs_hook=digest.coordinator.contract.no_duplicate_keys)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            raise ValueError('Slack request failed; reconcile before resend') from None
        require(isinstance(result, dict) and result.get('ok') is True, 'Slack API returned failure')
        return result


def safe(value):
    return ' '.join(str(value).split()).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def render(payload):
    data = json.loads(payload)
    lines = [f"Factory delivery — {safe(data['repository'])}",
             f"{data['display_from']} to {data['display_until']} (Australia/Sydney)",
             f"Merged PRs: {len(data['merges'])}; product acceptance remains separate."]
    for pr in data['merges']:
        proof = pr['delivery_evidence']
        attribution = ', '.join(f"{safe(p['task'])}/spec {safe(p['spec'])}" for p in proof) if proof else 'authenticated evidence MISSING'
        lines.append(f"#{pr['pr']} {safe(pr['title'])[:160]} — {attribution}")
        lines.append(f"https://github.com/{data['repository']}/pull/{pr['pr']} — merge {pr['merge_sha'][:12]}")
        for item in proof:
            lines.append(f"Evidence: https://github.com/{data['repository']}/actions/runs/{item['producer_run']}")
    if not data['merges']:
        lines.append('No merges in this delivered interval.')
    lines.append('Missing historical check records are not treated as a pass.')
    text = '\n'.join(lines)
    require(len(text) <= 35000, 'digest exceeds single-message limit; use a verified attachment adapter')
    return text


class Slack:
    def __init__(self, client, team, channel, key, payload):
        require(re.fullmatch(r'T[A-Z0-9]+', team or '') and re.fullmatch(r'[CG][A-Z0-9]+', channel or ''), 'Slack team/channel IDs required')
        self.client = client; self.channel = channel; self.key = key
        self.hash = hashlib.sha256(payload.encode()).hexdigest(); self.text = render(payload)
        identity = client.call('auth.test', {})
        require(identity.get('team_id') == team and identity.get('bot_id'), 'Slack workspace/bot differs')
        self.bot = identity['bot_id']
        self.metadata = {'event_type': 'factory_digest_v1', 'event_payload': {'key': key, 'payload_sha256': self.hash}}

    def proof(self, message):
        require(message.get('bot_id') == self.bot and message.get('metadata') == self.metadata and
                message.get('text') == self.text and re.fullmatch(r'[0-9]+\.[0-9]+', message.get('ts', '')), 'Slack message differs from report')
        return {'key': self.key, 'payload_sha256': self.hash, 'destination': self.channel, 'message_id': message['ts']}

    def send(self, key, payload, destination):
        require(key == self.key and destination == self.channel and hashlib.sha256(payload.encode()).hexdigest() == self.hash, 'Slack destination/payload differs')
        result = self.client.call('chat.postMessage', {'channel': self.channel, 'text': self.text, 'metadata': self.metadata,
                                                     'mrkdwn': False, 'parse': 'none', 'unfurl_links': False, 'unfurl_media': False})
        require(result.get('channel') == self.channel, 'Slack response channel differs')
        return self.proof(result['message'])

    def lookup(self, key):
        require(key == self.key, 'wrong Slack digest key')
        cursor = ''; seen = set(); matches = []
        for _ in range(100):
            body = {'channel': self.channel, 'limit': 100, 'include_all_metadata': True}
            if cursor:
                body['cursor'] = cursor
            page = self.client.call('conversations.history', body)
            require(isinstance(page.get('messages'), list), 'Slack history missing')
            for message in page['messages']:
                metadata = message.get('metadata', {})
                if message.get('bot_id') == self.bot and metadata.get('event_type') == 'factory_digest_v1' and metadata.get('event_payload', {}).get('key') == key:
                    matches.append(self.proof(message))
            cursor = page.get('response_metadata', {}).get('next_cursor', '')
            if not cursor:
                require(not page.get('has_more'), 'Slack history pagination incomplete')
                require(len(matches) <= 1, 'duplicate Slack digest messages')
                # History absence is never authoritative, even after all pages.
                return {'receipt': matches[0] if matches else None, 'authoritative_absence': False}
            require(cursor not in seen, 'Slack history cursor repeated')
            seen.add(cursor)
        raise ValueError('Slack history exceeds reconciliation limit')


def due(now):
    require(now.tzinfo is not None, 'runner clock needs timezone')
    local = now.astimezone(digest.SYDNEY)
    day = local.date() if local.hour >= 8 else local.date() - timedelta(days=1)
    return digest.cutoff(day.isoformat())


def validate_config(config):
    require(config.get('enabled') is True, 'digest runner disabled')
    for field in ('repository', 'destination', 'team_id', 'start', 'database'):
        require(isinstance(config.get(field), str) and bool(config[field]), 'digest runner configuration missing')
    require(Path(config['database']).is_absolute(), 'digest database must be absolute')
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', config['repository']), 'invalid digest repository')


def configured(config):
    validate_config(config)
    return digest.Digest(config['database'], config['repository'], config['destination'], config['start'], config.get('branch', 'main'))


def watchdog(config, now):
    validate_config(config)
    grace_minutes = config.get('watchdog_grace_minutes', 60)
    require(type(grace_minutes) is int and 0 <= grace_minutes <= 1440, 'invalid watchdog grace')
    stream = hashlib.sha256(digest.canonical([config['repository'], config['destination'], config.get('branch', 'main')]).encode()).hexdigest()
    expected = digest.instant(due(now))
    path = Path(config['database'])
    with sqlite3.connect(path.as_uri() + '?mode=ro', uri=True) as db:
        db.row_factory = sqlite3.Row
        row = db.execute('SELECT cutoff FROM digest_cursors WHERE stream=?', (stream,)).fetchone()
        require(row is not None, 'digest stream not initialized')
        delivered = row[0]
        pending = [dict(row) for row in db.execute("SELECT key,status,cutoff FROM digest_batches WHERE stream=? AND status!='confirmed'", (stream,))]
    missed = digest.instant(delivered) < expected and now.astimezone(timezone.utc) >= expected + timedelta(minutes=grace_minutes)
    return {'missed_delivery': missed, 'expected_cutoff': digest.stamp(expected), 'delivered_cutoff': delivered, 'pending': pending}


def run(config, api, client, now):
    store = configured(config)
    target = due(now)
    if digest.instant(store.cursor()) >= digest.instant(target):
        return {'status': 'not-due'}
    batch = store.prepare(api, target)
    transport = Slack(client, config['team_id'], config['destination'], batch['key'], batch['payload'])
    receipt = store.deliver(batch['key'], transport)
    return {'status': 'delivered', 'receipt': receipt, 'catch_up_pending': digest.instant(store.cursor()) < digest.instant(target)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--status-only', action='store_true')
    args = parser.parse_args()
    config = digest.coordinator.contract.load(args.config)
    now = datetime.now(timezone.utc)
    if args.status_only:
        result = watchdog(config, now)
        print(json.dumps(result)); return int(result['missed_delivery'])
    print(json.dumps(run(config, digest.coordinator.GitHub(config['repository']), SlackHTTP(), now)))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError, sqlite3.Error):
        print('Digest runner blocked; inspect trusted configuration and delivery state.', file=sys.stderr)
        sys.exit(1)

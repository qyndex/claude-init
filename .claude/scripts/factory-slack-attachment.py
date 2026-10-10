#!/usr/bin/env python3
"""Exact oversized digest file receipt; uncertain uploads are never blindly repeated."""
import hashlib
import importlib.util
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request

spec = importlib.util.spec_from_file_location('attachment_slack', Path(__file__).with_name('factory-slack-digest.py'))
slack = importlib.util.module_from_spec(spec); spec.loader.exec_module(slack)
require = slack.require
MAX_FILE = 1_000_000


class HTTP(slack.SlackHTTP):
    def call(self, method, body):
        if method not in {'files.getUploadURLExternal', 'files.completeUploadExternal', 'files.info'}:
            return super().call(method, body)
        # Share the base HTTP envelope/error handling, never substitute another host.
        return self.file_call(method, body)

    def file_call(self, method, body):
        import json
        url = 'https://slack.com/api/' + method
        data = json.dumps(body).encode()
        if method == 'files.info':
            url += '?' + urllib.parse.urlencode(body); data = None
        request = urllib.request.Request(url, data=data, headers={'Authorization': 'Bearer ' + self.token,
                                        'Content-Type': 'application/json; charset=utf-8'})
        try:
            with self.opener.open(request, timeout=15) as response:
                raw = response.read(2_000_001)
            require(len(raw) <= 2_000_000, 'Slack file response too large')
            result = json.loads(raw, object_pairs_hook=slack.digest.coordinator.contract.no_duplicate_keys)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            raise ValueError('Slack attachment request uncertain; reconcile before retry') from None
        require(isinstance(result, dict) and result.get('ok') is True, 'Slack attachment API failed; inspect scopes and authoritative history')
        return result

    def transfer(self, url, data=None, *, team=None, identity=None):
        parsed = urllib.parse.urlsplit(url)
        require(parsed.scheme == 'https' and parsed.netloc == 'files.slack.com' and not parsed.fragment and
                not any(part in {'.', '..'} for part in urllib.parse.unquote(parsed.path).split('/')),
                'Slack attachment URL rejected')
        if data is None:
            require(parsed.path.startswith(f'/files-pri/{team}-{identity}/'), 'Slack file download identity differs')
            headers = {'Authorization': 'Bearer ' + self.token}
        else:
            require(parsed.path.startswith('/upload/') and isinstance(data, bytes) and 0 < len(data) <= MAX_FILE,
                    'Slack upload URL/bytes rejected')
            headers = {'Content-Type': 'application/octet-stream'}  # Signed URL; no bot credential sent.
        request = urllib.request.Request(url, data=data, headers=headers)
        try:
            with self.opener.open(request, timeout=30) as response:
                require(response.status == 200, 'Slack attachment transfer failed')
                result = response.read(MAX_FILE + 1)
            require(len(result) <= MAX_FILE, 'Slack attachment transfer too large')
            return result
        except (urllib.error.URLError, TimeoutError):
            raise ValueError('Slack attachment transfer uncertain; reconcile before retry') from None


class Attachment(slack.Slack):
    def __init__(self, client, team, channel, key, payload):
        require(re.fullmatch(r'T[A-Z0-9]+', team or '') and re.fullmatch(r'[CG][A-Z0-9]+', channel or ''), 'Slack team/channel IDs required')
        require(slack.digest.coordinator.contract.digest(key, 64), 'Slack attachment key invalid')
        self.client = client; self.team = team; self.channel = channel; self.key = key
        self.hash = hashlib.sha256(payload.encode()).hexdigest()
        self.text = slack.render(payload, limit=MAX_FILE); self.bytes = self.text.encode()
        require(0 < len(self.bytes) <= MAX_FILE, 'Slack attachment exceeds byte limit')
        self.filename = f'factory-digest-{key}-{self.hash}.txt'
        identity = client.call('auth.test', {})
        require(identity.get('team_id') == team and identity.get('bot_id') and
                re.fullmatch(r'U[A-Z0-9]+', identity.get('user_id', '')), 'Slack workspace/bot differs')
        self.bot = identity['bot_id']; self.user = identity['user_id']

    def file_proof(self, message, identity):
        require(message.get('user') == self.user and re.fullmatch(r'[0-9]+\.[0-9]{1,6}', message.get('ts', '')),
                'Slack attachment share sender/time differs')
        file = self.client.call('files.info', {'file': identity})['file']
        require(file.get('id') == identity and re.fullmatch(r'F[A-Z0-9]+', identity) and
                file.get('name') == self.filename and file.get('user') == self.user and
                file.get('mode') == 'hosted' and file.get('is_external') is False and
                type(file.get('size')) is int and file['size'] == len(self.bytes) and
                file.get('public_url_shared') is False, 'Slack attachment identity/size/privacy differs')
        shares = [(channel, share) for kind in ('public', 'private')
                  for channel, values in file.get('shares', {}).get(kind, {}).items() for share in values]
        require(len(shares) == 1 and shares[0][0] == self.channel and
                shares[0][1].get('ts') == message['ts'] and shares[0][1].get('team_id') == self.team,
                'Slack attachment destination differs')
        content = self.client.transfer(file['url_private_download'], team=self.team, identity=identity)
        require(content == self.bytes, 'Slack attachment content differs')
        return self.receipt(slack.digest.canonical({'schema_version': 1, 'slack_file_id': identity,
                           'slack_share_ts': message['ts'], 'text_sha256': hashlib.sha256(content).hexdigest()}))

    def lookup(self, key):
        require(key == self.key, 'wrong Slack digest key')
        cursor = ''; seen = set(); matches = []
        for _ in range(100):
            body = {'channel': self.channel, 'limit': 100}
            if cursor: body['cursor'] = cursor
            page = self.client.call('conversations.history', body)
            require(isinstance(page.get('messages'), list), 'Slack history missing')
            for message in page['messages']:
                files = message.get('files', [])
                candidates = [file for file in files if file.get('name') == self.filename]
                if candidates:
                    require(len(files) == len(candidates) == 1, 'Slack attachment share ambiguous')
                    matches.append((message, candidates[0]['id']))
            cursor = page.get('response_metadata', {}).get('next_cursor', '')
            if not cursor:
                require(not page.get('has_more') and len(matches) <= 1, 'Slack attachment history incomplete or ambiguous')
                return {'receipt': self.file_proof(*matches[0]) if matches else None, 'authoritative_absence': False}
            require(cursor not in seen, 'Slack history cursor repeated'); seen.add(cursor)
        raise ValueError('Slack history exceeds reconciliation limit')

    def send(self, key, payload, destination):
        require(key == self.key and destination == self.channel and hashlib.sha256(payload.encode()).hexdigest() == self.hash,
                'Slack destination/payload differs')
        allocated = self.client.call('files.getUploadURLExternal', {'filename': self.filename, 'length': len(self.bytes)})
        identity = allocated['file_id']; require(re.fullmatch(r'F[A-Z0-9]+', identity), 'Slack attachment file ID invalid')
        self.client.transfer(allocated['upload_url'], self.bytes)
        self.client.call('files.completeUploadExternal', {'files': [{'id': identity, 'title': self.filename}],
                         'channel_id': self.channel, 'initial_comment': 'Factory delivery: complete report attached. Product acceptance remains separate.'})
        # A successful completion response alone is never delivery proof.
        receipt = self.lookup(key)['receipt']
        require(receipt is not None, 'Slack attachment share not visible; preserve uncertainty')
        return receipt

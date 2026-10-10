#!/usr/bin/env python3
"""Transactional runtime projections; the task ledger remains product authority."""
from contextlib import contextmanager
import json
import re
import sqlite3
import time


class Blocked(ValueError):
    """A lease, dependency or recovery boundary prohibits this mutation."""


TRANSITIONS = {
    'claimed': {'implementing', 'blocked'},
    'implementing': {'verifying', 'blocked'},
    'verifying': {'repairing', 'merge-ready', 'blocked'},
    'repairing': {'verifying', 'blocked'},
    'merge-ready': {'merging', 'blocked'},
    'merging': {'merged', 'blocked'},
}
TERMINAL = {'merged', 'cancelled', 'blocked'}


class Store:
    def __init__(self, path):
        self.path = str(path)
        with self.transaction() as db:
            schema = '''
                CREATE TABLE IF NOT EXISTS control (id INTEGER PRIMARY KEY, paused INTEGER NOT NULL);
                INSERT OR IGNORE INTO control VALUES (1,0);
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY, revision TEXT NOT NULL, deps TEXT NOT NULL,
                    state TEXT NOT NULL, owner TEXT, fence INTEGER NOT NULL DEFAULT 0,
                    expires REAL, attempt INTEGER NOT NULL DEFAULT 0, repairs INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS outbox (
                    key TEXT PRIMARY KEY, task TEXT NOT NULL REFERENCES tasks(id),
                    payload TEXT NOT NULL, status TEXT NOT NULL, sender TEXT,
                    expires REAL, result TEXT);
            '''
            for statement in schema.split(';'):
                if statement.strip():
                    db.execute(statement)

    @contextmanager
    def transaction(self):
        db = sqlite3.connect(self.path, timeout=30, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('BEGIN IMMEDIATE')
        try:
            yield db
            if db.in_transaction:
                db.execute('COMMIT')
        except BaseException:
            if db.in_transaction:
                db.execute('ROLLBACK')
            raise
        finally:
            db.close()

    @staticmethod
    def instant(now):
        value = time.time() if now is None else now
        if not isinstance(value, (int, float)) or not 0 <= value < float('inf'):
            raise ValueError('invalid clock')
        return value

    @staticmethod
    def duration(seconds):
        if type(seconds) not in (int, float) or not 0 < seconds <= 3600:
            raise ValueError('lease must be between zero and 3600 seconds')

    @staticmethod
    def row(db, task):
        row = db.execute('SELECT * FROM tasks WHERE id=?', (task,)).fetchone()
        if row is None:
            raise Blocked('unknown task')
        return row

    def owned(self, db, task, owner, token, now):
        row = self.row(db, task)
        if (row['state'] in TERMINAL or row['owner'] != owner or row['fence'] != token
                or row['expires'] is None or row['expires'] <= now):
            raise Blocked('stale or terminal worker')
        return row

    def enqueue(self, task, revision, deps):
        if (not isinstance(task, str) or re.fullmatch(r'T-[1-9][0-9]*', task) is None
                or not isinstance(revision, str) or re.fullmatch(r'[0-9a-f]{64}', revision) is None
                or not isinstance(deps, list) or any(not isinstance(d, str) for d in deps)
                or len(set(deps)) != len(deps) or task in deps):
            raise ValueError('invalid task authority projection')
        encoded = json.dumps(sorted(deps))
        with self.transaction() as db:
            for dep in deps:
                self.row(db, dep)
            existing = db.execute('SELECT * FROM tasks WHERE id=?', (task,)).fetchone()
            if existing:
                if existing['revision'] != revision or existing['deps'] != encoded:
                    raise Blocked('task identity already registered with different authority')
                return
            db.execute('INSERT INTO tasks(id,revision,deps,state) VALUES(?,?,?,?)',
                       (task, revision, encoded, 'queued'))

    def claim(self, task, owner, seconds, now=None):
        now = self.instant(now); self.duration(seconds)
        if not isinstance(owner, str) or not owner.strip():
            raise ValueError('owner required')
        with self.transaction() as db:
            row = self.row(db, task)
            if db.execute('SELECT paused FROM control WHERE id=1').fetchone()[0]:
                raise Blocked('factory paused')
            if row['state'] in TERMINAL or (row['expires'] is not None and row['expires'] > now):
                raise Blocked('task is terminal or already owned')
            if row['attempt'] >= 3:
                raise Blocked('initial attempt plus two recovery attempts exhausted')
            if any(self.row(db, dep)['state'] != 'merged' for dep in json.loads(row['deps'])):
                raise Blocked('dependency not merged')
            token = row['fence'] + 1
            db.execute('UPDATE tasks SET state=?,owner=?,fence=?,expires=?,attempt=attempt+1 WHERE id=?',
                       ('claimed', owner, token, now + seconds, task))
            return token

    def recover_worker(self, task, owner, token, requeue=False):
        """Trusted guardian calls only after attempting actual worker cleanup."""
        if type(requeue) is not bool:
            raise ValueError('boolean recovery outcome required')
        with self.transaction() as db:
            row = self.row(db, task)
            if row['owner'] != owner or row['fence'] != token or row['state'] in TERMINAL:
                return False
            db.execute("UPDATE outbox SET status='uncertain' WHERE task=? AND status='dispatching'", (task,))
            db.execute('UPDATE tasks SET state=?,owner=NULL,expires=NULL,fence=fence+1 WHERE id=?',
                       ('queued' if requeue else 'blocked', task))
            return True

    def heartbeat(self, task, owner, token, seconds, now=None):
        now = self.instant(now); self.duration(seconds)
        with self.transaction() as db:
            self.owned(db, task, owner, token, now)
            db.execute('UPDATE tasks SET expires=? WHERE id=?', (now + seconds, task))

    def transition(self, task, owner, token, state, action=None, now=None):
        now = self.instant(now)
        with self.transaction() as db:
            row = self.owned(db, task, owner, token, now)
            if state == 'repairing' and row['repairs'] >= 2:
                raise Blocked('two repair attempts exhausted')
            if state not in TRANSITIONS.get(row['state'], set()):
                raise Blocked('illegal transition')
            if action is not None:
                key, payload = action
                if not isinstance(key, str) or not key.strip() or not isinstance(payload, dict):
                    raise ValueError('invalid external action')
                encoded = json.dumps(payload, sort_keys=True, allow_nan=False)
                existing = db.execute('SELECT * FROM outbox WHERE key=?', (key,)).fetchone()
                if existing and (existing['task'] != task or existing['payload'] != encoded):
                    raise Blocked('idempotency key reused for different action')
                db.execute('INSERT OR IGNORE INTO outbox(key,task,payload,status) VALUES(?,?,?,?)',
                           (key, task, encoded, 'pending'))
            db.execute('UPDATE tasks SET state=?,repairs=repairs+? WHERE id=?',
                       (state, int(state == 'repairing'), task))

    def pause(self, paused):
        if type(paused) is not bool:
            raise ValueError('boolean pause required')
        with self.transaction() as db:
            db.execute('UPDATE control SET paused=? WHERE id=1', (int(paused),))

    def cancel(self, task):
        with self.transaction() as db:
            row = self.row(db, task)
            if row['state'] == 'merged':
                raise Blocked('cannot cancel merged work')
            db.execute('UPDATE tasks SET state=?,fence=fence+1,expires=NULL WHERE id=?', ('cancelled', task))
            db.execute("UPDATE outbox SET status='cancelled' WHERE task=? AND status='pending'", (task,))

    def get(self, task):
        with self.transaction() as db:
            result = dict(self.row(db, task)); result['deps'] = json.loads(result['deps'])
            return result

    def actions(self):
        with self.transaction() as db:
            rows = [dict(row) for row in db.execute('SELECT * FROM outbox ORDER BY rowid')]
            for row in rows:
                row['payload'] = json.loads(row['payload'])
                row['result'] = json.loads(row['result']) if row['result'] is not None else None
            return rows

    def dispatch(self, key, sender, seconds, now=None):
        now = self.instant(now); self.duration(seconds)
        if not isinstance(sender, str) or not sender.strip():
            raise ValueError('sender required')
        with self.transaction() as db:
            row = db.execute('SELECT * FROM outbox WHERE key=?', (key,)).fetchone()
            if row is None or row['status'] != 'pending':
                raise Blocked('action is not pending; reconcile uncertain effects')
            if db.execute('SELECT paused FROM control WHERE id=1').fetchone()[0]:
                raise Blocked('factory paused')
            if self.row(db, row['task'])['state'] in {'cancelled', 'blocked'}:
                raise Blocked('task cancelled or blocked')
            db.execute('UPDATE outbox SET status=?,sender=?,expires=? WHERE key=?',
                       ('dispatching', sender, now + seconds, key))
            return dict(db.execute('SELECT * FROM outbox WHERE key=?', (key,)).fetchone())

    def recover_actions(self, now=None):
        with self.transaction() as db:
            db.execute("UPDATE outbox SET status='uncertain' WHERE status='dispatching' AND expires<=?",
                       (self.instant(now),))

    def confirm(self, key, sender, result, now=None):
        if not isinstance(result, dict) or not result:
            raise ValueError('remote receipt required')
        encoded = json.dumps(result, sort_keys=True, allow_nan=False)
        with self.transaction() as db:
            row = db.execute('SELECT * FROM outbox WHERE key=?', (key,)).fetchone()
            if (row is None or row['status'] != 'dispatching' or row['sender'] != sender
                    or row['expires'] <= self.instant(now)):
                raise Blocked('dispatcher lease expired; reconcile remote effect')
            db.execute("UPDATE outbox SET status='confirmed',result=?,expires=NULL WHERE key=?", (encoded, key))

    def reconcile(self, key, result, remote_absent=False):
        if type(remote_absent) is not bool or (remote_absent and result is not None):
            raise ValueError('contradictory reconciliation')
        if not remote_absent and (not isinstance(result, dict) or not result):
            raise ValueError('remote receipt required')
        encoded = json.dumps(result, sort_keys=True, allow_nan=False) if result is not None else None
        with self.transaction() as db:
            row = db.execute('SELECT * FROM outbox WHERE key=?', (key,)).fetchone()
            if row is None:
                raise Blocked('unknown action')
            if row['status'] == 'confirmed' and row['result'] == encoded and not remote_absent:
                return
            if row['status'] != 'uncertain':
                raise Blocked('only uncertain effects can be reconciled')
            db.execute('UPDATE outbox SET status=?,result=?,sender=NULL,expires=NULL WHERE key=?',
                       ('pending' if remote_absent else 'confirmed', encoded, key))

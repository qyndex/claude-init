#!/usr/bin/env python3
"""Import approved ledger projections; worker success is never merge evidence."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location('runtime', Path(__file__).with_name('factory-runtime.py'))
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


def resource_contract(config, namespace):
    services = config.get('services', [])
    if not isinstance(services, list):
        raise ValueError('service list required')
    names = set()
    for service in services:
        if (not isinstance(service, dict) or set(service) != {'name', 'kind'}
                or re.fullmatch(r'[a-z][a-z0-9_-]{0,31}', service['name']) is None
                or service['name'] in names or service['kind'] not in {'tcp', 'directory'}):
            raise ValueError('unsupported isolation declaration; use inherited TCP socket or private directory')
        names.add(service['name'])
    return {'namespace': namespace, 'services': services}


def parse_ledgers(root):
    tasks = {}
    paths = [root / 'tasks/TASKS.md', *sorted((root / 'tasks/archive').glob('TASKS-*.md'))]
    for path in paths:
        for line in path.read_text().splitlines():
            match = re.match(r'^- \[([ ~x!bs])\] (T-[1-9][0-9]*)\s*\|\s*(.*)$', line)
            if match is None:
                if re.match(r'^- \[.\] T-', line):
                    raise ValueError('malformed task marker')
                continue
            marker, task, rest = match.groups()
            if task in tasks:
                raise ValueError('duplicate ledger task ID')
            fields = {}
            for item in rest.split('|'):
                key, separator, value = item.strip().partition(':')
                if not separator or key in fields:
                    raise ValueError('malformed task fields')
                fields[key] = value.strip()
            deps = [dep.strip() for dep in fields.get('deps', '').split(',') if dep.strip()]
            if len(set(deps)) != len(deps) or any(re.fullmatch(r'T-[1-9][0-9]*', d) is None for d in deps):
                raise ValueError('invalid dependencies')
            tasks[task] = {'spec': fields.get('spec'), 'deps': sorted(deps), 'marker': marker}
    return tasks


def import_task(root, db_path, task, policy_path):
    root = Path(root).resolve()
    lock = root / '.claude/state/locks/memory-plane.oslock'
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open('a') as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        policy = json.loads(Path(policy_path).read_text())
        records = parse_ledgers(root)
        selected = {}
        visiting = set()

        def visit(tid):
            if tid in visiting:
                raise ValueError('cyclic task dependencies')
            if tid in selected:
                return
            if tid not in records:
                raise ValueError('unknown dependency')
            row = records[tid]
            approved = policy.get('specs', {}).get(row['spec'])
            if not isinstance(approved, dict):
                raise ValueError('unapproved task specification')
            source = (root / approved['path']).resolve()
            if not source.is_relative_to(root) or not source.is_file():
                raise ValueError('spec source outside authority repository')
            content = source.read_bytes()
            digest = hashlib.sha256(content).hexdigest()
            if digest != approved.get('sha256') or re.search(rb'^status:\s*approved\s*$', content, re.M) is None:
                raise ValueError('approved spec bytes/status differ')
            acs = re.findall(r'\*\*(AC-\d+)\*\*', content.decode())
            scope = approved.get('allowed_paths')
            if not isinstance(scope, list) or not scope or any(not isinstance(p, str) or not p for p in scope):
                raise ValueError('invalid approved path scope')
            if not acs or len(set(acs)) != len(acs) or set(acs) != set(approved.get('ac_ids', [])) or not approved.get('allowed_paths'):
                raise ValueError('incomplete approved scope/ACs')
            visiting.add(tid)
            for dep in row['deps']:
                visit(dep)
            visiting.remove(tid)
            authority = {'spec': row['spec'], 'revision': digest, 'deps': row['deps'],
                         'ac_ids': sorted(acs), 'allowed_paths': approved['allowed_paths']}
            selected[tid] = authority

        visit(task)
        store = runtime.Store(db_path)
        with store.transaction() as db:
            columns = {row['name'] for row in db.execute('PRAGMA table_info(tasks)')}
            if 'authority' not in columns:
                db.execute('ALTER TABLE tasks ADD COLUMN authority TEXT')
            for tid, authority in selected.items():
                deps = json.dumps(authority['deps'])
                encoded = json.dumps(authority, sort_keys=True)
                existing = db.execute('SELECT * FROM tasks WHERE id=?', (tid,)).fetchone()
                if existing:
                    if (existing['revision'] != authority['revision'] or existing['deps'] != deps
                            or existing['authority'] != encoded):
                        raise ValueError('immutable task authority changed or unapproved legacy registration')
                else:
                    db.execute('INSERT INTO tasks(id,revision,deps,state,authority) VALUES(?,?,?,?,?)',
                               (tid, authority['revision'], deps, 'queued', encoded))
        return selected


def confirm_merge(db_path, task, revision, receipt):
    """Trusted receipt-adapter API; never called from a ledger marker or worker output."""
    if (set(receipt) != {'repository', 'pr', 'merge_sha'}
            or re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', receipt['repository']) is None
            or type(receipt['pr']) is not int or receipt['pr'] <= 0
            or re.fullmatch(r'[0-9a-f]{40}', receipt['merge_sha']) is None):
        raise ValueError('invalid merge receipt')
    store = runtime.Store(db_path)
    encoded = json.dumps(receipt, sort_keys=True)
    with store.transaction() as db:
        db.execute('CREATE TABLE IF NOT EXISTS delivery_receipts(task TEXT PRIMARY KEY, revision TEXT NOT NULL, receipt TEXT NOT NULL)')
        row = store.row(db, task)
        if row['revision'] != revision or row['owner'] is not None or row['state'] not in {'queued', 'merged'}:
            raise ValueError('receipt does not match an unclaimed dependency projection')
        existing = db.execute('SELECT * FROM delivery_receipts WHERE task=?', (task,)).fetchone()
        if existing and (existing['revision'] != revision or existing['receipt'] != encoded):
            raise ValueError('conflicting immutable delivery receipt')
        db.execute('INSERT OR IGNORE INTO delivery_receipts VALUES(?,?,?)', (task, revision, encoded))
        db.execute("UPDATE tasks SET state='merged' WHERE id=?", (task,))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--authority-root', required=True)
    parser.add_argument('--policy', required=True)
    parser.add_argument('--db', required=True)
    parser.add_argument('--task', required=True)
    parser.add_argument('--cwd')
    parser.add_argument('--attempts')
    parser.add_argument('--timeout', type=float, default=1800)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    config = json.loads(Path(args.policy).read_text())
    resources = resource_contract(config.get('runtime', {}), 'assigned-at-claim')
    imported = import_task(args.authority_root, args.db, args.task, args.policy)
    if not command:
        print(json.dumps({'imported': list(imported), 'delivery_inferred': False}))
        return 0
    if not args.cwd or not args.attempts:
        parser.error('worker cwd and attempts directory required')
    module = importlib.util.spec_from_file_location('supervisor', Path(__file__).with_name('factory-supervisor.py'))
    supervisor = importlib.util.module_from_spec(module); module.loader.exec_module(supervisor)
    return supervisor.supervise(args.db, args.task, command, args.cwd, args.attempts,
                                timeout=args.timeout, resources=resources)


if __name__ == '__main__':
    sys.exit(main())

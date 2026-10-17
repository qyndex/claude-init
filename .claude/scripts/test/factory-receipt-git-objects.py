"""Fixture-only persistent reader of actual Git objects; no fabricated object facts."""
import subprocess
from collections import OrderedDict


class GitObjects:
    def __init__(self, root):
        self.root = root
        self.writer = None
        self.commits = {}
        self.reachable = {}
        self.positions = {}
        self.histories = OrderedDict()
        self.process = subprocess.Popen(['git', '-C', str(root), 'cat-file', '--batch'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL)

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.close()

    def close(self):
        if self.process.stdin is not None and not self.process.stdin.closed:
            self.process.stdin.close()
        self.process.wait(timeout=5)
        self.process.stdout.close()
        self.reset_writer()

    def reset_writer(self):
        if self.writer is not None:
            self.writer.stdin.close()
            self.writer.wait(timeout=5)
            self.writer.stdout.close()
            self.writer = None

    def read(self, expression):
        assert isinstance(expression, str) and '\n' not in expression and '\r' not in expression
        self.process.stdin.write(expression.encode()+b'\n'); self.process.stdin.flush()
        header = self.process.stdout.readline().decode().strip().split()
        if len(header) != 3:
            raise ValueError('fixture Git object unavailable')
        oid, kind, size = header
        raw = self.process.stdout.read(int(size))
        assert len(raw) == int(size) and self.process.stdout.read(1) == b'\n'
        return oid, kind, raw

    def commit(self, identity):
        if identity in self.commits:
            return self.commits[identity]
        oid, kind, raw = self.read(identity)
        assert oid == identity and kind == 'commit'
        headers = raw.split(b'\n\n', 1)[0].splitlines()
        trees = [line[5:].decode() for line in headers if line.startswith(b'tree ')]
        assert len(trees) == 1
        result = {'sha':oid, 'tree':{'sha':trees[0]},
                  'parents':[{'sha':line[7:].decode()} for line in headers if line.startswith(b'parent ')]}
        if len(self.commits) < 16384:
            self.commits[identity] = result
        return result

    def ancestry(self, identity):
        pending = [(identity, False)]
        while pending:
            current, expanded = pending.pop()
            if current in self.reachable:
                continue
            parents = [parent['sha'] for parent in self.commit(current)['parents']]
            if not expanded:
                pending.append((current, True))
                pending.extend((parent, False) for parent in parents if parent not in self.reachable)
                continue
            assert len(self.positions) < 16384, 'fixture ancestry bound exceeded'
            self.positions[current] = len(self.positions)
            mask = 1 << self.positions[current]
            for parent in parents:
                mask |= self.reachable[parent]
            self.reachable[current] = mask
        return self.reachable[identity]

    def compare(self, base, head):
        reachable = self.ancestry(head)
        previous = self.ancestry(base)
        if not reachable & (1 << self.positions[base]):
            return None  # Leave divergent-DAG semantics to the original Git adapter.
        count = (reachable & ~previous).bit_count()
        return {'base_commit':{'sha':base}, 'merge_base_commit':{'sha':base},
                'status':'identical' if base == head else 'ahead', 'behind_by':0,
                'ahead_by':count, 'total_commits':count}

    def path_oid(self, tree, path):
        for name in path.split('/'):
            unused, kind, raw = self.read(tree)
            assert kind == 'tree'
            selected = None
            while raw:
                metadata, raw = raw.split(b'\0', 1)
                oid, raw = raw[:20].hex(), raw[20:]
                mode, entry = metadata.split(b' ', 1)
                if entry.decode() == name:
                    selected = (mode.decode().zfill(6), oid)
                    break
            if selected is None:
                return None
            tree = selected[1]
        return selected

    def path_history(self, identity, path):
        """Exact linear Git path history; merge simplification stays with Git."""
        pending = []
        cursor = identity
        while (cursor, path) not in self.histories:
            commit = self.commit(cursor)
            if len(commit['parents']) > 1:
                return None
            pending.append(cursor)
            if not commit['parents']:
                rows = ()
                break
            cursor = commit['parents'][0]['sha']
        else:
            rows = self.histories[(cursor, path)]
        for current in reversed(pending):
            commit = self.commit(current)
            after = self.path_oid(commit['tree']['sha'], path)
            before = None if not commit['parents'] else self.path_oid(self.commit(commit['parents'][0]['sha'])['tree']['sha'], path)
            if before != after:
                rows = (current,)+rows
            self.histories[(current, path)] = rows
            while len(self.histories) > 256:
                self.histories.popitem(last=False)
        return rows

    def tree(self, identity, *, sizes=True):
        oid, kind, raw = self.read(identity)
        assert oid == identity and kind == 'tree'
        result = []
        while raw:
            metadata, raw = raw.split(b'\0', 1)
            mode, name = metadata.split(b' ', 1)
            child, raw = raw[:20].hex(), raw[20:]
            mode = mode.decode().zfill(6)
            kind = 'tree' if mode == '040000' else 'commit' if mode == '160000' else 'blob'
            row = {'path':name.decode(), 'mode':mode, 'type':kind, 'sha':child}
            if sizes and kind == 'blob':
                actual, actual_kind, data = self.read(child)
                assert actual == child and actual_kind == kind
                row['size'] = len(data)
            result.append(row)
        return result

    def write_entries(self, entries):
        if self.writer is None:
            self.writer = subprocess.Popen(['git', '-C', str(self.root), 'mktree', '--batch', '-z'],
                                           stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                           stderr=subprocess.DEVNULL)
        raw = b''.join((row['mode']+' '+row['type']+' '+row['sha']+'\t'+row['path']).encode()+b'\0' for row in entries)
        self.writer.stdin.write(raw+b'\0'); self.writer.stdin.flush()
        identity = self.writer.stdout.readline().decode().strip()
        assert len(identity) == 40 and all(char in '0123456789abcdef' for char in identity), 'native tree write failed'
        return identity

    def write_tree(self, base, changes):
        def update(identity, parts, change):
            entries = {} if identity is None else {row['path']:row for row in self.tree(identity, sizes=False)}
            name = parts[0]
            if len(parts) == 1:
                if change['sha'] is None:
                    entries.pop(name, None)
                else:
                    mode = change['mode'].zfill(6)
                    entries[name] = {'path':name, 'mode':mode, 'type':'tree' if mode == '040000' else 'commit' if mode == '160000' else 'blob', 'sha':change['sha']}
            else:
                previous = entries.get(name)
                assert previous is None or previous['type'] == 'tree', 'fixture parent is not a tree'
                child, empty = update(None if previous is None else previous['sha'], parts[1:], change)
                if empty:
                    entries.pop(name, None)
                else:
                    entries[name] = {'path':name, 'mode':'040000', 'type':'tree', 'sha':child}
            return self.write_entries(entries.values()), not entries
        for change in changes:
            parts = change['path'].split('/')
            assert parts and all(part not in ('', '.', '..') and '\0' not in part for part in parts)
            base, unused = update(base, parts, change)
        return base

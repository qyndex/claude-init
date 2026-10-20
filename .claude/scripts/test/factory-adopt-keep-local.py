#!/usr/bin/env python3
"""Bounded reviewed keep-local ownership: real Git, files, locks and recovery."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / '.claude/scripts/factory-adopt.py'
spec = importlib.util.spec_from_file_location('adoption', MODULE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
CONFIG = ('CLAUDE.md', '.mcp.json', '.claude/settings.json')


def git(root, *args):
    env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null')
    return subprocess.check_output(['git', '-C', str(root), '-c', 'core.hooksPath=/dev/null',
                                    '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                                    *args], env=env, stderr=subprocess.DEVNULL).decode().strip()


def put(root, name, text, mode=0o644):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)


def snapshot(root):
    result = {}
    for path in root.rglob('*'):
        if '.git' in path.relative_to(root).parts:
            continue
        if path.is_symlink():
            result[str(path.relative_to(root))] = ('symlink', os.readlink(path))
        elif path.is_file():
            result[str(path.relative_to(root))] = (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
    return result


class Fixture:
    def __init__(self, folder, shape='brownfield'):
        self.source = folder / 'source'
        self.target = folder / 'target'
        self.state = folder / 'private-state'
        self.source.mkdir()
        self.target.mkdir()
        git(self.source, 'init', '-b', 'main')
        git(self.target, 'init', '-b', 'main')
        for path, text in {
            '.claude/VERSION': '1\n',
            '.claude/CLAUDE.md': 'Strict managed process instructions.\n',
            '.claude/settings.json': '{"permissions":{"defaultMode":"default"}}\n',
            '.mcp.json': '{"mcpServers":{"upstream":{"command":"fixture-never-executed"}}}\n',
            'CLAUDE.md': 'Generic framework guidance.\n',
            '.claude/agents/core/reviewer.md': 'Framework reviewer.\n',
        }.items():
            put(self.source, path, text)
        put(self.source, '.claude/scripts/worker.sh', '#!/bin/sh\necho version-one\n', 0o755)
        git(self.source, 'add', '.')
        git(self.source, 'commit', '-m', 'source version one')
        put(self.target, 'product.txt', 'adopter product stays\n')
        git(self.target, 'add', '.')
        git(self.target, 'commit', '-m', 'adopter baseline')
        m.adopt(self.source, self.target, self.state)
        put(self.target, '.claude/memory/MEMORY.md', 'Fixture-owned project memory.\n')
        put(self.target, '.claude/agents/project/local.md', 'Fixture-owned project agent.\n')
        put(self.target, '.claude/settings.local.json', '{"fixture_local":true}\n')
        put(self.target, '.github/workflows/project.yml', 'name: fixture-project\n')
        self.kept = CONFIG if shape == 'brownfield' else CONFIG[:2]
        put(self.target, 'CLAUDE.md', 'Intentional project instructions, preserved.\n')
        put(self.target, '.mcp.json', '{"mcpServers":{}}\n')
        if shape == 'brownfield':
            put(self.target, '.claude/settings.json', '{"permissions":{"defaultMode":"plan"}}\n', 0o600)
        git(self.target, 'add', '.')
        git(self.target, 'commit', '-m', 'reviewed intentional adopter configuration')
        self.original_manifest = m.load(self.target / m.MANIFEST)
        self.original_kept = {path: m.image(self.target / path) for path in self.kept}
        self.original_user = {path: m.image(self.target / path) for path in (
            'product.txt', '.claude/memory/MEMORY.md', '.claude/agents/project/local.md',
            '.claude/settings.local.json', '.github/workflows/project.yml')}
        put(self.source, '.claude/VERSION', '2\n')
        put(self.source, '.claude/scripts/worker.sh', '#!/bin/sh\necho version-two\n', 0o755)
        git(self.source, 'add', '.')
        git(self.source, 'commit', '-m', 'source version two')
        self.plan = folder / 'resolution.json'
        self.document = self.make_plan(self.kept)
        self.write_plan()

    def identity(self):
        common = git(self.target, 'rev-parse', '--git-common-dir')
        common = Path(common) if Path(common).is_absolute() else self.target / common
        return {'git_common_dir': str(common.resolve()), 'head_sha': git(self.target, 'rev-parse', 'HEAD')}

    def make_plan(self, paths):
        manifest = m.load(self.target / m.MANIFEST)
        entries = {}
        for path in paths:
            owned = manifest['files'].get(path)
            if owned is None:
                owned = manifest.get('local_overrides', {}).get(path, {}).get('original_owned')
            entries[path] = {'action': 'keep-local', 'owned': owned,
                             'current': m.fingerprint(m.image(self.target / path)),
                             'upstream': m.fingerprint(m.image(self.source / path))}
        return {'schema_version': 1, 'source_sha': git(self.source, 'rev-parse', 'HEAD'),
                'target': str(self.target), 'repository': self.identity(),
                'manifest': m.fingerprint(m.image(self.target / m.MANIFEST)), 'entries': entries}

    def write_plan(self):
        self.plan.write_text(json.dumps(self.document, sort_keys=True) + '\n')
        self.plan.chmod(0o600)
        self.approval = hashlib.sha256(self.plan.read_bytes()).hexdigest()

    def apply(self, **kw):
        return m.adopt(self.source, self.target, self.state, upgrade=True,
                       resolution_plan=self.plan, plan_sha256=self.approval, **kw)

    def preserved(self, case):
        for path, image in self.original_kept.items():
            case.assertEqual(m.image(self.target / path), image, path)
        for path, image in self.original_user.items():
            case.assertEqual(m.image(self.target / path), image, path)


class KeepLocal(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='keep-local-')
        self.folder = Path(self.tmp.name).resolve()

    def tearDown(self):
        self.tmp.cleanup()

    def fixture(self, shape='brownfield'):
        return Fixture(self.folder, shape)

    def assert_blocked(self, f, function=None):
        before, state = snapshot(f.target), snapshot(f.state)
        with self.assertRaises(ValueError):
            (function or f.apply)()
        self.assertEqual(snapshot(f.target), before)
        self.assertEqual(snapshot(f.state), state)

    def test_existing_no_plan_customization_block_is_unchanged(self):
        f = self.fixture()
        self.assert_blocked(f, lambda: m.adopt(f.source, f.target, f.state, upgrade=True))

    def test_brownfield_three_paths_preserve_bytes_modes_and_user_content(self):
        f = self.fixture()
        result = f.apply()
        self.assertEqual(result['kept_local_files'], 3)
        f.preserved(self)
        manifest = m.load(f.target / m.MANIFEST)
        self.assertEqual(manifest['schema_version'], 2)
        self.assertEqual(set(manifest['local_overrides']), set(f.kept))
        for path in f.kept:
            self.assertNotIn(path, manifest['files'])
            self.assertEqual(manifest['local_overrides'][path]['original_owned'],
                             f.original_manifest['files'][path])
        self.assertIn('.claude/CLAUDE.md', manifest['files'])
        self.assertIn('version-two', (f.target / '.claude/scripts/worker.sh').read_text())
        self.assertEqual(stat.S_IMODE(f.state.stat().st_mode), 0o700)
        journal_path = f.state / (result['journal'] + '.json')
        self.assertEqual(stat.S_IMODE(journal_path.stat().st_mode), 0o600)
        journal = m.load(journal_path)
        self.assertEqual(journal['schema_version'], 2)
        self.assertTrue(set(f.kept).isdisjoint(journal['changes']))
        self.assertEqual(set(journal['preserved_local']), set(f.kept))

    def test_greenfield_two_paths_do_not_release_settings(self):
        f = self.fixture('greenfield')
        f.apply()
        f.preserved(self)
        manifest = m.load(f.target / m.MANIFEST)
        self.assertIn('.claude/settings.json', manifest['files'])
        self.assertNotIn('.claude/settings.json', manifest['local_overrides'])

    def test_dry_run_has_no_target_or_journal_effect(self):
        f = self.fixture()
        before, state = snapshot(f.target), snapshot(f.state)
        result = f.apply(dry=True)
        self.assertTrue(result['dry_run'])
        self.assertGreater(result['changed_files'], 0)
        self.assertEqual(snapshot(f.target), before)
        self.assertEqual(snapshot(f.state), state)

    def test_no_plan_repeat_is_idempotent_and_preserves_later_local_edits(self):
        f = self.fixture()
        f.apply()
        count = len(list(f.state.glob('*.json')))
        result = m.adopt(f.source, f.target, f.state, upgrade=True)
        self.assertEqual(result['changed_files'], 0)
        self.assertEqual(len(list(f.state.glob('*.json'))), count)
        put(f.target, '.mcp.json', '{"mcpServers":{},"fixture_owner_edit":true}\n', 0o600)
        local = m.image(f.target / '.mcp.json')
        result = m.adopt(f.source, f.target, f.state, upgrade=True)
        self.assertEqual(result['changed_files'], 0)
        self.assertEqual(m.image(f.target / '.mcp.json'), local)

    def test_repository_head_drift_after_journal_blocks_before_effects(self):
        f = self.fixture()
        before = snapshot(f.target)
        original = m.persist
        changed = []
        def persist(path, document):
            original(path, document)
            if document['status'] == 'pending' and not changed:
                git(f.target, 'commit', '--allow-empty', '-m', 'foreign HEAD advance')
                changed.append(True)
        m.persist = persist
        try:
            with self.assertRaises(ValueError):
                f.apply()
        finally:
            m.persist = original
        self.assertEqual(snapshot(f.target), before)

    def test_repository_head_drift_before_completion_rolls_back(self):
        f = self.fixture()
        before = snapshot(f.target)
        final_write = f.apply(dry=True)['changed_files']
        def fault(number):
            if number == final_write:
                git(f.target, 'commit', '--allow-empty', '-m', 'foreign HEAD advance')
        with self.assertRaises(ValueError):
            f.apply(fault=fault)
        self.assertEqual(snapshot(f.target), before)

    def test_first_transfer_cannot_approve_missing_upstream(self):
        f = self.fixture()
        (f.source / 'CLAUDE.md').unlink()
        git(f.source, 'add', '-A')
        git(f.source, 'commit', '-m', 'remove source before transfer')
        f.document = f.make_plan(['CLAUDE.md'])
        f.write_plan()
        self.assert_blocked(f)

    def test_reviewed_upstream_removal_and_reappearance_need_exact_renewal(self):
        f = self.fixture()
        f.apply()
        (f.source / 'CLAUDE.md').unlink()
        git(f.source, 'add', '-A')
        git(f.source, 'commit', '-m', 'remove upstream project guidance')
        self.assert_blocked(f, lambda: m.adopt(f.source, f.target, f.state, upgrade=True))
        f.document = f.make_plan(['CLAUDE.md'])
        f.write_plan()
        f.apply()
        f.preserved(self)
        self.assertIsNone(m.load(f.target / m.MANIFEST)['local_overrides']['CLAUDE.md']['reviewed_upstream'])
        self.assertEqual(m.adopt(f.source, f.target, f.state, upgrade=True)['changed_files'], 0)
        put(f.source, 'CLAUDE.md', 'new upstream guidance after removal\n')
        git(f.source, 'add', '.')
        git(f.source, 'commit', '-m', 'restore upstream project guidance')
        self.assert_blocked(f, lambda: m.adopt(f.source, f.target, f.state, upgrade=True))
        f.document = f.make_plan(['CLAUDE.md'])
        f.write_plan()
        f.apply()
        f.preserved(self)

    def test_consumed_resolution_plan_is_stale(self):
        f = self.fixture()
        f.apply()
        self.assert_blocked(f)

    def test_wrong_approval_hash_rejects_before_effects(self):
        f = self.fixture()
        f.approval = '0' * 64
        self.assert_blocked(f)

    def test_approval_hash_without_plan_rejects(self):
        f = self.fixture()
        self.assert_blocked(f, lambda: m.adopt(f.source, f.target, f.state, upgrade=True,
                                              plan_sha256=f.approval))

    def test_plan_requires_explicit_upgrade(self):
        f = self.fixture()
        self.assert_blocked(f, lambda: m.adopt(f.source, f.target, f.state,
                                              resolution_plan=f.plan, plan_sha256=f.approval))

    def test_stale_binding_fields_reject(self):
        f = self.fixture()
        for mutate in (
            lambda d: d.update(source_sha='0' * 40),
            lambda d: d.update(target=str(self.folder / 'other')),
            lambda d: d['repository'].update(head_sha='0' * 40),
            lambda d: d['repository'].update(git_common_dir=str(self.folder)),
            lambda d: d['manifest'].update(sha256='0' * 64),
            lambda d: d['manifest'].update(mode=0o755),
            lambda d: d['entries']['.mcp.json']['owned'].update(sha256='0' * 64),
            lambda d: d['entries']['.mcp.json']['current'].update(sha256='0' * 64),
            lambda d: d['entries']['.mcp.json']['upstream'].update(sha256='0' * 64),
            lambda d: d['entries']['.mcp.json']['current'].update(mode=True),
        ):
            with self.subTest(mutate=mutate):
                original = f.document
                f.document = copy.deepcopy(original)
                mutate(f.document)
                f.write_plan()
                self.assert_blocked(f)
                f.document = original
        f.write_plan()

    def test_local_bytes_or_mode_drift_rejects(self):
        f = self.fixture()
        put(f.target, '.mcp.json', 'changed after approval\n')
        self.assert_blocked(f)
        m.write(f.target / '.mcp.json', f.original_kept['.mcp.json'])
        (f.target / '.mcp.json').chmod(0o755)
        self.assert_blocked(f)

    def test_manifest_bytes_drift_rejects(self):
        f = self.fixture()
        p = f.target / m.MANIFEST
        p.write_bytes(p.read_bytes() + b'\n')
        self.assert_blocked(f)

    def test_source_revision_drift_rejects(self):
        f = self.fixture()
        put(f.source, '.claude/VERSION', '3\n')
        git(f.source, 'add', '.')
        git(f.source, 'commit', '-m', 'source changed after plan')
        self.assert_blocked(f)

    def test_no_general_process_or_instruction_release(self):
        f = self.fixture()
        for path in ('.claude/CLAUDE.md', '.claude/scripts/worker.sh',
                     '.claude/agents/core/reviewer.md', '../outside'):
            with self.subTest(path=path):
                f.document = f.make_plan([path])
                f.write_plan()
                self.assert_blocked(f)

    def test_resolution_action_extra_and_duplicate_fields_reject(self):
        f = self.fixture()
        original = copy.deepcopy(f.document)
        for mutate in (lambda d: d['entries']['.mcp.json'].update(action='force'),
                       lambda d: d.update(force=True), lambda d: d.update(entries={}),
                       lambda d: d['entries']['.mcp.json'].update(execute='never')):
            f.document = copy.deepcopy(original)
            mutate(f.document)
            f.write_plan()
            self.assert_blocked(f)
        f.document = original
        f.write_plan()
        f.plan.write_text(f.plan.read_text().replace('"schema_version": 1',
                         '"schema_version": 1, "schema_version": 1', 1))
        f.approval = hashlib.sha256(f.plan.read_bytes()).hexdigest()
        self.assert_blocked(f)

    def test_target_symlink_and_plan_symlink_reject(self):
        f = self.fixture()
        outside = self.folder / 'external-config'
        outside.write_text('external fixture must stay untouched\n')
        p = f.target / '.mcp.json'
        p.unlink()
        p.symlink_to(outside)
        self.assert_blocked(f)
        self.assertEqual(outside.read_text(), 'external fixture must stay untouched\n')
        p.unlink()
        m.write(p, f.original_kept['.mcp.json'])
        real = self.folder / 'real-plan.json'
        f.plan.rename(real)
        f.plan.symlink_to(real)
        self.assert_blocked(f)

    def test_resolution_does_not_waive_unselected_owned_code_change(self):
        f = self.fixture()
        put(f.target, '.claude/scripts/worker.sh', 'adopter changed owned code\n', 0o755)
        self.assert_blocked(f)

    def test_future_upstream_configuration_requires_review_and_renewal(self):
        f = self.fixture()
        f.apply()
        put(f.source, 'CLAUDE.md', 'New upstream configuration guidance.\n')
        git(f.source, 'add', '.')
        git(f.source, 'commit', '-m', 'upstream config changed')
        self.assert_blocked(f, lambda: m.adopt(f.source, f.target, f.state, upgrade=True))
        f.document = f.make_plan(['CLAUDE.md'])
        f.write_plan()
        f.apply()
        f.preserved(self)
        result = m.adopt(f.source, f.target, f.state, upgrade=True)
        self.assertEqual(result['changed_files'], 0)

    def test_fault_rollback_restores_exact_before_images_and_config(self):
        f = self.fixture()
        before = snapshot(f.target)
        def crash(number):
            if number == 1:
                raise RuntimeError('fixture injected write failure')
        with self.assertRaises(RuntimeError):
            f.apply(fault=crash)
        self.assertEqual(snapshot(f.target), before)
        f.preserved(self)
        self.assertEqual(m.load(sorted(f.state.glob('*.json'), key=lambda p: p.stat().st_mtime)[-1])['status'],
                         'reverted')

    def test_foreign_config_change_fences_recovery_without_overwrite(self):
        f = self.fixture()
        def foreign(number):
            put(f.target, '.mcp.json', 'later fixture owner edit\n')
            raise RuntimeError('fixture crash after owner edit')
        with self.assertRaises(ValueError):
            f.apply(fault=foreign)
        self.assertEqual((f.target / '.mcp.json').read_text(), 'later fixture owner edit\n')
        journals = [p for p in f.state.glob('*.json') if m.load(p)['status'] == 'pending']
        self.assertEqual(len(journals), 1)
        journal = m.load(journals[0])
        before = snapshot(f.target)
        with self.assertRaises(ValueError):
            m.restore(f.target, journal, journals[0])
        self.assertEqual(snapshot(f.target), before)
        m.write(f.target / '.mcp.json', f.original_kept['.mcp.json'])
        m.restore(f.target, journal, journals[0])
        f.preserved(self)

    def test_completed_revert_preserves_config_and_restores_v1_ownership(self):
        f = self.fixture()
        before = snapshot(f.target)
        result = f.apply()
        path = f.state / (result['journal'] + '.json')
        m.restore(f.target, m.load(path), path)
        self.assertEqual(snapshot(f.target), before)
        self.assertEqual(m.load(f.target / m.MANIFEST)['schema_version'], 1)

    def test_v2_schema_rejects_unsafe_overlap_unknown_and_code_release(self):
        f = self.fixture()
        f.apply()
        manifest = m.load(f.target / m.MANIFEST)
        for mutate in (
            lambda d: d['files'].update({'CLAUDE.md': d['local_overrides']['CLAUDE.md']['original_owned']}),
            lambda d: d['local_overrides'].update({'../outside': d['local_overrides']['CLAUDE.md']}),
            lambda d: d['local_overrides'].update({'.claude/CLAUDE.md': d['local_overrides']['CLAUDE.md']}),
            lambda d: d['local_overrides']['CLAUDE.md'].update(execute='never'),
        ):
            with self.subTest(mutate=mutate):
                bad = copy.deepcopy(manifest)
                mutate(bad)
                with self.assertRaises(ValueError):
                    m.validate_manifest(bad)
        # Strict v1 readers cannot silently interpret the new ownership contract.
        self.assertNotEqual(set(manifest), {'schema_version', 'source_sha', 'files'})
        self.assertEqual(manifest['schema_version'], 2)

    def test_cli_serializes_competing_exact_plan_and_repeat_updates(self):
        f = self.fixture()
        args = [sys.executable, str(MODULE), '--from', str(f.source), '--into', str(f.target),
                '--state-root', str(f.state), '--upgrade', '--resolution-plan', str(f.plan),
                '--approve-plan-sha256', f.approval]
        children = [subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    for _ in range(2)]
        outputs = [child.communicate(timeout=30) for child in children]
        self.assertEqual(sorted(child.returncode for child in children), [0, 2], outputs)
        f.preserved(self)
        repeats = [subprocess.Popen(args[:-4], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                   for _ in range(2)]
        outputs = [child.communicate(timeout=30) for child in repeats]
        self.assertEqual([child.returncode for child in repeats], [0, 0], outputs)
        self.assertTrue(all(json.loads(out)['changed_files'] == 0 for out, error in outputs))


if __name__ == '__main__':
    result = unittest.main(verbosity=2, exit=False).result
    if result.wasSuccessful():
        print('AC-5: exact reviewed three-path keep-local ownership and upstream review guards PASS')
        print('AC-6: real adopter-shaped preservation, private recovery and CLI serialization PASS')
    sys.exit(0 if result.wasSuccessful() else 1)

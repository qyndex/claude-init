#!/usr/bin/env bash
# Spec003 AC-20 / T-130: exercise the current ledger, isolated from real evidence.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import pathlib
import os
import shutil
import shlex
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='tdd-ledger-classification-') as directory:
    target = pathlib.Path(directory)
    scripts = target / '.claude/scripts'
    scripts.mkdir(parents=True)
    for name in ('tdd-ledger.sh', 'check-tdd-ledger.sh'):
        shutil.copyfile(root / '.claude/scripts' / name, scripts / name)
    (target / 'tasks').mkdir()
    # Actual native assertion programs, not pre-recorded runner output.
    native_failures = []
    def native_case(task, name, command, reason, required):
        native = subprocess.run(['bash', str(scripts / 'tdd-ledger.sh'), 'red', task, command], cwd=target, text=True, capture_output=True)
        log = list((target / 'verify').glob(f'*/{task}/red.log'))[0]
        raw = log.read_text()
        assert required in raw, (name, 'native assertion did not execute', repr(raw))
        log.with_name('green.log').write_text('ledger_format: 2\ntimestamp: 2099-01-01T00:00:00+00:00\ncommand: '+command+'\nexit_code: 0\n---\nPASS\n')
        (target / 'tasks/TASKS.md').write_text(f'- [x] {task} | spec:003\n  accept: {command}\n')
        checked = subprocess.run(['bash', str(scripts / 'check-tdd-ledger.sh')], cwd=target, text=True, capture_output=True)
        expected = 0 if reason == 'assertion-failure' else 1
        if native.returncode != expected or f'red_reason: {reason}\n' not in raw or checked.returncode != expected:
            observed = [line for line in raw.splitlines() if line.startswith('red_reason:')]
            native_failures.append((name, native.returncode, observed, checked.returncode))
        else:
            print(f'PASS actual native {name}: {reason}, gate enforced')
    unittest = target / 'assertion_diff.py'
    unittest.write_text("import unittest\nclass Case(unittest.TestCase):\n def test_value(self):self.assertMultiLineEqual('Startup Error\\nx','ready\\nx')\nunittest.main()\n")
    native_case('T-960', 'unittest assertion diff', shlex.quote(sys.executable)+' '+shlex.quote(str(unittest)), 'assertion-failure', 'FAILED (failures=1)')
    node = shutil.which('node')
    if node:
        helper = target / 'vitest.config.js'
        helper.write_text("exports.helper=()=>require('node:assert').strictEqual('actual','expected');\n")
        test = target / 'assertion.test.cjs'
        test.write_text("require('./vitest.config.js').helper();\n")
        native_case('T-961', 'Node config-helper test assertion', shlex.quote(node)+' '+shlex.quote(str(test)), 'assertion-failure', 'AssertionError')
        config_assert = target / 'playwright.config.cjs'
        config_assert.write_text("require('node:assert').strictEqual('actual','expected');\n")
        native_case('T-962', 'Node config-load AssertionError', shlex.quote(node)+' '+shlex.quote(str(config_assert)), 'tooling-error', 'AssertionError')
    else:
        print('SKIP optional native Node helper/config assertions: node unavailable')
    assert not native_failures, native_failures
    cases = [
        # Diagnostic transcripts; Error: expect + config frames stays conservative.
        ('config-erase-cursor-prefix', '\x1b[2K\x1b[1Gfailed to load config from /tmp/vitest.config.ts\nError: config exploded', 1, 'tooling-error'),
        ('startup-cursor-prefix', '\x1b[1A\x1b[2K⎯⎯⎯ Startup Error ⎯⎯⎯\nError: config exploded', 1, 'tooling-error'),
        ('config-private-csi-prefix', '\x1b[?25lfailed to load config from /tmp/vitest.config.ts\nError: config exploded', 1, 'tooling-error'),
        ('config-intermediate-csi-prefix', '\x1b[1 qfailed to load config from /tmp/vitest.config.ts\nError: config exploded', 1, 'tooling-error'),
        ('assertion-csi-prefix', '\x1b[2K\x1b[1GAssertionError: expected "failed to load config from" to equal "ready"', 1, 'assertion-failure'),
        ('expect-config-frame-unsupported', 'Error: expect(received).toBe(expected)\n    at helper (/tmp/playwright.config.ts:3:7)\n    at /tmp/tests/example.test.ts:5:2', 1, 'tooling-error'),
        ('vitest-colored', '\x1b[31mfailed to load config from /tmp/vitest.config.ts\x1b[0m\nError: config exploded', 1, 'tooling-error'),
        ('startup-colored', '\x1b[31m⎯⎯⎯ Startup Error ⎯⎯⎯\x1b[0m\nError: config exploded', 1, 'tooling-error'),
        ('stack-colored', '\x1b[31m    at Object.<anonymous> (/tmp/playwright.config.ts:3:7)\x1b[0m', 1, 'tooling-error'),
        ('assertion-colored', '\x1b[31mAssertionError: expected \"failed to load config from\" to equal \"loaded\"\x1b[0m', 1, 'assertion-failure'),
        ('vitest-load', 'failed to load config from /tmp/vitest.config.ts\nError: config exploded', 1, 'tooling-error'),
        ('vite-load', 'failed to load config from /tmp/vite.config.mts\nError: config exploded', 1, 'tooling-error'),
        ('playwright-stack', 'Error: config exploded\n    at Object.<anonymous> (/tmp/playwright.config.ts:3:7)', 1, 'tooling-error'),
        ('playwright-esm', 'Error: config exploded\n    at file:///tmp/playwright.config.mjs:3:7', 1, 'tooling-error'),
        ('vitest-startup', '⎯⎯⎯ Startup Error ⎯⎯⎯\nError: config exploded', 1, 'tooling-error'),
        ('missing-command', 'fixture: command not found', 127, 'tooling-error'),
        ('no-tests', 'No tests found', 1, 'tooling-error'),
        ('assertion', 'AssertionError: expected 1 to equal 2\n  at app.test.ts:5:2', 1, 'assertion-failure'),
        ('config-in-assertion', 'AssertionError: expected "playwright.config.ts" to equal "vitest.config.ts"', 1, 'assertion-failure'),
        ('load-in-assertion', 'AssertionError: expected "failed to load config from" to equal "loaded"', 1, 'assertion-failure'),
        ('startup-in-assertion', 'AssertionError: expected "Startup Error" to equal "ready"', 1, 'assertion-failure'),
        ('jest-diff-startup', 'AssertionError: expected different text\n- \"Startup Error\",\n+ ready', 1, 'assertion-failure'),
        ('vitest-config-helper-test', 'FAIL tests/example.test.ts > assertion\nAssertionError: expected actual to equal expected\n    at helper (/tmp/vitest.config.ts:2:3)\n    at /tmp/tests/example.test.ts:5:2', 1, 'assertion-failure'),
        ('config-assertion-no-test-frame', 'AssertionError: config precondition failed\n    at /tmp/vitest.config.ts:2:3', 1, 'tooling-error'),
        ('startup-precedes-test-frame', '⎯⎯⎯ Startup Error ⎯⎯⎯\nAssertionError: config precondition failed\n    at /tmp/vitest.config.ts:2:3\n    at /tmp/tests/example.test.ts:5:2', 1, 'tooling-error'),
        ('load-precedes-test-frame', 'failed to load config from /tmp/vitest.config.ts\nAssertionError: config precondition failed\n    at /tmp/vitest.config.ts:2:3\n    at /tmp/tests/example.test.ts:5:2', 1, 'tooling-error'),
    ]
    for index, (name, output, code, reason) in enumerate(cases, start=900):
        task = f'T-{index}'
        # Controlled transcripts test classification; no runner install/network needed.
        fixture = target / f'{name}.sh'
        fixture.write_text("#!/usr/bin/env bash\ncat <<'TRANSCRIPT'\n" + output + "\nTRANSCRIPT\nexit " + str(code) + '\n')
        command = 'bash ' + shlex.quote(str(fixture))
        result = subprocess.run(['bash', str(scripts / 'tdd-ledger.sh'), 'red', task, command], cwd=target, text=True, capture_output=True)
        logs = list((target / 'verify').glob(f'*/{task}/red.log'))
        assert len(logs) == 1, (name, result.stdout, result.stderr)
        text = logs[0].read_text()
        assert output in text, (name, 'original diagnostics must be preserved', text)
        assert f'red_reason: {reason}\n' in text, (name, reason, text)
        assert result.returncode == (0 if reason == 'assertion-failure' else 1), (name, result)
        # Verify the independent gate also refuses rejected RED evidence.
        green = logs[0].with_name('green.log')
        green.write_text('ledger_format: 2\ntimestamp: 2099-01-01T00:00:00+00:00\ncommand: ' + command + '\nexit_code: 0\n---\nPASS\n')
        (target / 'tasks/TASKS.md').write_text(f'- [x] {task} | spec:003\n  accept: {command}\n')
        checked = subprocess.run(['bash', str(scripts / 'check-tdd-ledger.sh')], cwd=target, text=True, capture_output=True)
        assert checked.returncode == (0 if reason == 'assertion-failure' else 1), (name, checked.stdout, checked.stderr)
        print(f'PASS {name}: {reason}, gate enforced')
    broken_env = os.environ.copy()
    broken_env['BASH_FUNC_sed%%'] = '() { return 73; }'
    command = "printf '%s\\n' 'failed to load config from /tmp/vitest.config.ts'; exit 1"
    broken = subprocess.run(['bash', str(scripts / 'tdd-ledger.sh'), 'red', 'T-970', command], cwd=target, env=broken_env, text=True, capture_output=True)
    broken_log = list((target / 'verify').glob('*/T-970/red.log'))[0]
    broken_text = broken_log.read_text()
    assert broken.returncode == 1 and 'red_reason: tooling-error\n' in broken_text, repr(broken_text)
    assert 'failed to load config from /tmp/vitest.config.ts' in broken_text, repr(broken_text)
    broken_log.with_name('green.log').write_text('ledger_format: 2\ntimestamp: 2099-01-01T00:00:00+00:00\ncommand: ' + command + '\nexit_code: 0\n---\nPASS\n')
    (target / 'tasks/TASKS.md').write_text('- [x] T-970 | spec:003\n  accept: ' + command + '\n')
    checked = subprocess.run(['bash', str(scripts / 'check-tdd-ledger.sh')], cwd=target, text=True, capture_output=True)
    assert checked.returncode == 1, (checked.stdout, checked.stderr)
    print('PASS failed diagnostic normalization rejected as tooling, raw output preserved, gate enforced')
    node = shutil.which('node')
    if node:
        config = target / 'playwright.config.cjs'
        config.write_text("throw new Error('native config failure');\n")
        command = shlex.quote(node) + ' ' + shlex.quote(str(config))
        native = subprocess.run(['bash', str(scripts / 'tdd-ledger.sh'), 'red', 'T-980', command], cwd=target, text=True, capture_output=True)
        native_log = list((target / 'verify').glob('*/T-980/red.log'))[0].read_text()
        assert native.returncode == 1 and 'red_reason: tooling-error\n' in native_log, native_log
        assert 'native config failure' in native_log, native_log
        print('PASS native Node config-module throw classified as tooling (no installed framework claim)')
    else:
        print('SKIP optional native Node config-module throw: node unavailable; transcript cases still mandatory')
    passed = subprocess.run(['bash', str(scripts / 'tdd-ledger.sh'), 'red', 'T-999', 'true'], cwd=target, capture_output=True)
    assert passed.returncode == 1
    assert not list((target / 'verify').glob('*/T-999/red.log')), 'passing command must not produce RED evidence'
    print('PASS passing command cannot create RED evidence')
PY

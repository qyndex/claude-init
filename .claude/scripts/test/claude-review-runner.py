#!/usr/bin/env python3
"""Exercise input transfer, isolation and fail-closed ordinary review evidence."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import subprocess
import textwrap
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('runner', Path(__file__).resolve().parents[1] / 'run-claude-review.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
binding = {'repository': 'example/project', 'pr': 12, 'head': 'a'*40, 'role': 'code'}
result = {'type': 'result', 'subtype': 'success', 'is_error': False, 'num_turns': 3, 'permission_denials': [], 'modelUsage': {r.proof.MODEL: {'inputTokens': 100, 'outputTokens': 50}}, 'structured_output': {**binding, 'summary': 'No actionable findings.', 'findings': [], 'suppressed': 0}}


class Runner(unittest.TestCase):
    def test_workflow_missing_runtime_preserves_blocked_artifact(self):
        repo = Path(__file__).resolve().parents[3]
        for name, role in [('claude-review.yml','code'),('claude-security.yml','security')]:
            text = (repo/'.github/workflows'/name).read_text()
            self.assertLess(text.index('id: prepare_review'), text.index('name: Set up pinned Node'))
            block = text.split('      - name: Run and retain bounded tool-free review', 1)[1].split('      - name:', 1)[0].split('        run: |\n', 1)[1]
            with tempfile.TemporaryDirectory() as folder:
                outcome = subprocess.run(['bash','-e','-c',textwrap.dedent(block)], env={**os.environ,'RUNNER_TEMP':folder}, capture_output=True)
                self.assertEqual(outcome.returncode, 1)
                report = json.loads((Path(folder)/('retained-'+role+'-review/review.json')).read_text())
                self.assertEqual(report, {'schema_version':1,'role':role,'status':'blocked','reason':'runtime-unavailable'})

    def test_cli_writes_fresh_blocked_report_without_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)/'report'
            command = [sys.executable,'-I',str(Path(r.__file__)),'--role','security','--output',str(output)]
            env = {k:v for k,v in os.environ.items() if k not in ('CLAUDE_CODE_OAUTH_TOKEN','REVIEW_PREPARE_OUTCOME')}
            first = subprocess.run(command, env=env, capture_output=True)
            self.assertEqual(first.returncode, 1)
            report = (output/'review.json').read_bytes()
            self.assertEqual(json.loads(report)['status'], 'blocked')
            second = subprocess.run(command, env=env, capture_output=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual((output/'review.json').read_bytes(), report)

    def test_transport_isolation_and_failure_contract(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            event = root/'event.json'
            node = Path(sys.executable).resolve()
            exe = root/'cli-wrapper.cjs'
            exe.write_text('# fixture')
            package = root/'package.json'
            package.write_text(json.dumps({'name': '@anthropic-ai/claude-code', 'version': r.proof.CLI_VERSION}))
            event.write_text(json.dumps({'repository': {'full_name': binding['repository']}, 'pull_request': {'number': 12, 'head': {'sha': 'a'*40}, 'base': {'sha': 'b'*40}}}))
            context = ('BINDING '+json.dumps({**{k: binding[k] for k in ('repository','pr','head')}, 'base': 'b'*40, 'total_lines': 2})+'\n'+'x'*300000+'TAIL-CANARY').encode()
            (root/'claude-review-input.txt').write_bytes(context)
            env = {**os.environ, 'REVIEW_PREPARE_OUTCOME': 'success', 'REVIEW_INSTALL_OUTCOME': 'success', 'CLAUDE_CODE_OAUTH_TOKEN': 'fixture-token', 'GITHUB_EVENT_PATH': str(event), 'RUNNER_TEMP': str(root), 'REVIEW_NODE': str(node), 'REVIEW_EXECUTABLE': str(exe), 'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '2', 'GH_TOKEN': 'PRIVATE-GITHUB', 'ANTHROPIC_API_KEY': 'PRIVATE-API', 'ANTHROPIC_BASE_URL': 'https://untrusted.invalid'}
            calls = []
            def child(argv, **kw):
                calls.append(argv)
                data = kw['stdin'].read()
                self.assertIn(context, data)
                self.assertIn(b'TAIL-CANARY', data)
                self.assertGreater(len(data), 300000)
                self.assertEqual(set(kw['env']), {'PATH','LANG','LC_ALL','CLAUDE_CODE_OAUTH_TOKEN','HOME','CLAUDE_CONFIG_DIR','TMPDIR'})
                self.assertNotEqual(kw['cwd'], os.getcwd())
                self.assertEqual(kw['cwd'], kw['env']['HOME'])
                for flag in ('--tools', '--setting-sources'):
                    self.assertEqual(argv[argv.index(flag)+1], '')
                self.assertEqual(kw['timeout'], 300)
                self.assertEqual(argv[argv.index('--max-turns')+1], '3')
                return SimpleNamespace(returncode=0, stdout=json.dumps(result).encode(), stderr=b'PRIVATE-STDERR')
            with patch.dict(os.environ, env, clear=True):
                saved = r.run_review('code', runner=child)
                self.assertEqual(saved['status'], 'reviewed')
                self.assertNotIn('PRIVATE', json.dumps(saved))
                self.assertEqual(len(calls), 1)
                def actual(argv, **kw):
                    expected = r.prompt_bytes('code', binding, context)
                    exe.write_text('import sys,hashlib\ndata=sys.stdin.buffer.read()\nassert hashlib.sha256(data).hexdigest()=='+repr(hashlib.sha256(expected).hexdigest())+'\nprint('+repr(json.dumps(result))+')\n')
                    return r.process.run([str(node), str(exe)], **kw)
                self.assertEqual(r.run_review('code', runner=actual)['status'], 'reviewed')
                def reply(raw, code=0):
                    return lambda *a, **k: SimpleNamespace(returncode=code, stdout=raw, stderr=b'PRIVATE')
                for raw, code in [(b'{}',0), (b'{"type":1,"type":2}',0), (b'['*2000+b'0'+b']'*2000,0), (b'PRIVATE',1)]:
                    saved = r.run_review('code', runner=reply(raw, code))
                    self.assertEqual(saved['status'], 'blocked')
                    self.assertNotIn('PRIVATE', json.dumps(saved))
                high = copy.deepcopy(result)
                high['structured_output']['findings'] = [{'severity':'high','path':'source.py','line':1,'description':'Defect.'}]
                self.assertEqual(r.run_review('code', runner=reply(json.dumps(high).encode()))['status'], 'changes-required')
                for key, value in [('REVIEW_PREPARE_OUTCOME','failure'), ('REVIEW_INSTALL_OUTCOME','skipped'), ('CLAUDE_CODE_OAUTH_TOKEN','')]:
                    with patch.dict(os.environ, {key:value}):
                        self.assertEqual(r.run_review('code', runner=lambda *a, **k: self.fail('must not execute'))['status'], 'blocked')
                package.write_text(json.dumps({'name':'@anthropic-ai/claude-code','version':'wrong'}))
                self.assertEqual(r.run_review('code', runner=lambda *a, **k: self.fail('wrong CLI must not execute'))['reason'], 'runtime')
                (root/'claude-review-input.txt').write_bytes(context.replace(b'a'*40, b'c'*40))
                self.assertEqual(r.run_review('code', runner=lambda *a, **k: self.fail('stale context must not execute'))['reason'], 'input')


if __name__ == '__main__':
    unittest.main(verbosity=2)

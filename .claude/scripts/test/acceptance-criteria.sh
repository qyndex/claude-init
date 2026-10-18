#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PYTEST'
import importlib.util,json,shutil,subprocess,tempfile,unittest
from pathlib import Path
root=Path.cwd();scripts=root/'.claude/scripts'
spec=importlib.util.spec_from_file_location('acceptance_section',scripts/'acceptance-criteria.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Sections(unittest.TestCase):
 def test_boundaries_and_nested_headings(self):
  text=b"# Intro AC-99\n## Acceptance criteria\n1. **AC-01**: required\n### Details\n2. **AC-2**: required\n## Approved amendment\nSee other spec AC-9\n"
  self.assertEqual(m.criteria(text),['AC-1','AC-2'])
 def test_fences_do_not_create_headings_or_requirements(self):
  self.assertEqual(m.criteria(b'## Acceptance criteria\nAC-1 real\n```md\n## Appendix\nAC-99 example\n```\nAC-2 real\n# End\nSee AC-9 outside\n'),['AC-1','AC-2'])
  self.assertEqual(m.criteria(b'~~~md\n## Acceptance criteria\nAC-9 example\n~~~\n## Acceptance criteria ##\nAC-1 real\n'),['AC-1'])
 def test_missing_empty_duplicate_and_malformed_sections_reject(self):
  for raw in [b'AC-1 alone',b'## Acceptance criteria\n## Next\nAC-1 outside',b'## Acceptance criteria\nAC-1\n## Acceptance criteria\nAC-2',b'## Acceptance criteria\nAC-0',b'## Acceptance criteria\nAC-1\n```',b'\xff',b'x'*(m.MAX_BYTES+1)]:
   with self.subTest(raw=raw[:100]):
    with self.assertRaises(ValueError):m.criteria(raw)
 def test_tab_heading_and_malformed_literal_heading(self):
  self.assertEqual(m.criteria(b'##\tAcceptance criteria\nAC-1 required\n'),['AC-1'])
  with self.assertRaises(ValueError):m.criteria(b'##tAcceptance criteria\nAC-1 required\n')
 def test_outside_definitions_reject_but_references_remain_valid(self):
  for definition in ['AC-9: extra', '**AC-9**: extra', '1. **AC-9**: extra', '- AC-9 extra']:
   with self.subTest(definition=definition):
    with self.assertRaises(ValueError):m.criteria(('## Acceptance criteria\nAC-1 real\n## Amendment\n'+definition+'\n').encode())
  self.assertEqual(m.criteria(b'## Acceptance criteria\nAC-1 real\n## Appendix\nSee AC-9 in another spec\n'),['AC-1'])
 def test_invalid_backtick_fence_cannot_hide_criteria(self):
  with self.assertRaises(ValueError):m.criteria(b'## Acceptance criteria\nAC-1 real\n```x``` text\nAC-2 real\n```\n')
 def test_only_markdown_line_endings_form_headings(self):
  for separator in ['\x0b','\x0c','\x1c','\x85','\u2028','\u2029']:
   with self.subTest(separator=separator):
    with self.assertRaises(ValueError):m.criteria(('intro'+separator+'## Acceptance criteria\nAC-1 real\n').encode())
  self.assertEqual(m.criteria(b'## Acceptance criteria\rAC-1 real\r\nAC-2 real\n'),['AC-1','AC-2'])
 def test_real_spec014_has_eight_criteria(self):
  self.assertEqual(m.criteria((root/'specs/active/014-authenticated-receipt-recovery.md').read_bytes()),['AC-'+str(i) for i in range(1,9)])
 def test_matcher_and_collector_use_same_section_and_keep_failure(self):
  with tempfile.TemporaryDirectory() as temporary:
   work=Path(temporary);(work/'.claude/scripts/lib').mkdir(parents=True);(work/'specs/active').mkdir(parents=True)
   for name in ['acceptance-criteria.py','spec-match.sh','collect-evidence.sh','lib/atomic-write.sh']:shutil.copy2(scripts/name,work/'.claude/scripts'/name)
   # Offline unit fixture only; this stub grants no real project verification.
   (work/'.claude/scripts/verify.sh').write_text('#!/usr/bin/env bash\nprintf "fixture-only smoke\\n"\n')
   (work/'specs/active/111-boundary.md').write_text('See AC-99 intro\n## Acceptance criteria\n1. AC-1 required\n2. AC-2 required\n## Approved continuation\nSee AC-9 in another spec\n')
   output=work/'verify'/(subprocess.check_output(['date','+%Y-%m-%d'],text=True).strip()+'-111-boundary');output.mkdir(parents=True)
   results=output/'results.json'
   def record(second):results.write_text(json.dumps({'testResults':[{'assertionResults':[{'fullName':'AC-1 fixture','status':'passed'},{'fullName':'AC-2 fixture','status':second}]}]}))
   record('passed')
   def run(script,*args):return subprocess.run(['bash',str(work/'.claude/scripts'/script),*args],cwd=work,capture_output=True,text=True)
   passed=run('spec-match.sh','111',str(results));self.assertEqual(passed.returncode,0,passed.stdout+passed.stderr)
   collected=run('collect-evidence.sh','111','--check-only');self.assertEqual(collected.returncode,0,collected.stdout+collected.stderr)
   doc=json.loads((output/'evidence.json').read_text());self.assertEqual((doc['ac_total'],doc['ac_proven']), (2,2))
   record('failed')
   failed=run('spec-match.sh','111',str(results));self.assertEqual(failed.returncode,1);self.assertIn('AC-2',failed.stdout)
   collected=run('collect-evidence.sh','111','--check-only');self.assertEqual(collected.returncode,1)
   doc=json.loads((output/'evidence.json').read_text());self.assertEqual(doc['ac_unproven'],['AC-2']);self.assertEqual(doc['verdict'],'FAIL')
   (work/'specs/active/111-boundary.md').write_text('No actual acceptance section; AC-1 elsewhere')
   self.assertNotEqual(run('spec-match.sh','111',str(results)).returncode,0)
   self.assertNotEqual(run('collect-evidence.sh','111','--check-only').returncode,0)
unittest.main(verbosity=2)
PYTEST

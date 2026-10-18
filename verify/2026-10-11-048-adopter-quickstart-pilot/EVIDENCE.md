## Evidence Bundle — Spec 048 (048-adopter-quickstart-pilot)
Spec: `specs/active/048-adopter-quickstart-pilot.md` · Commit: `10bcd08`

Retained results: [verify/2026-10-18-048-adopter-quickstart-pilot/attempt-dEj0nTDN/results.json](verify/2026-10-18-048-adopter-quickstart-pilot/attempt-dEj0nTDN/results.json)

### Acceptance criteria (3/3 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-18T12:16:55+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof
0 screenshot(s) captured under `verify/2026-10-18-048-adopter-quickstart-pilot/screenshots/` (named by AC).

### API traces
0 API trace file(s) under `verify/2026-10-18-048-adopter-quickstart-pilot/traces/`; full HAR at `verify/2026-10-18-048-adopter-quickstart-pilot/network.har`.

### Coverage
line ?% · branch ?% (gate: line≥90 branch≥85)

### Verdict: **PASS**

## Artifact index
- verify/2026-10-18-048-adopter-quickstart-pilot/evidence.json
- verify/2026-10-18-048-adopter-quickstart-pilot/attempt-dEj0nTDN/results.json
- verify/2026-10-18-048-adopter-quickstart-pilot/pr-body.md
- verify/2026-10-18-048-adopter-quickstart-pilot/EVIDENCE.md
- verify/2026-10-18-048-adopter-quickstart-pilot/results.json
- verify/2026-10-18-048-adopter-quickstart-pilot/smoke.log

## Actual capture and approved retention mapping

Actual local capture date: 2026-10-18. Actual UTC retention time: 2026-10-18T01:17:32.058165+00:00. The 2026-10-11 paths are approved retention locations, not observation dates. Generated metadata, timestamps and source bindings remain unchanged. The original results_file identifies the private retained attempt; its exact results bytes are committed at verify/2026-10-11-048-adopter-quickstart-pilot/results.json. The original capture is preserved outside this candidate. EVIDENCE.md receives only this appended mapping; its generated prefix remains identical. T222 stays open; historical d4/bc4d shadow is not current eligibility. No independent producer success, authority activation, merged delivery or product acceptance is claimed.

```json
[
  {
    "original": "verify/2026-10-18-048-adopter-quickstart-pilot/results.json",
    "retained": "verify/2026-10-11-048-adopter-quickstart-pilot/results.json",
    "original_sha256": "7bfc007946a0c95bef2e97d5361334fe652f1629b6284ab3ca384eafbc4f816d",
    "identical_copy_sha256": "7bfc007946a0c95bef2e97d5361334fe652f1629b6284ab3ca384eafbc4f816d"
  },
  {
    "original": "verify/2026-10-18-048-adopter-quickstart-pilot/evidence.json",
    "retained": "verify/2026-10-11-048-adopter-quickstart-pilot/evidence.json",
    "original_sha256": "eacc0ee54f27b5e0273c2560f2172691b2a28302a27f8a2f2338cd78e4480446",
    "identical_copy_sha256": "eacc0ee54f27b5e0273c2560f2172691b2a28302a27f8a2f2338cd78e4480446"
  },
  {
    "original": "verify/2026-10-18-048-adopter-quickstart-pilot/pr-body.md",
    "retained": "verify/2026-10-11-048-adopter-quickstart-pilot/pr-body.md",
    "original_sha256": "c34dc98e6429d6123de66b0f3f9229fb7a0fcca19839230a14e6c14f2da25a68",
    "identical_copy_sha256": "c34dc98e6429d6123de66b0f3f9229fb7a0fcca19839230a14e6c14f2da25a68"
  },
  {
    "original": "verify/2026-10-18-048-adopter-quickstart-pilot/EVIDENCE.md",
    "retained": "verify/2026-10-11-048-adopter-quickstart-pilot/EVIDENCE.md",
    "original_sha256": "3ec3877786e24d71a5f181192ed4d5aa36a7ed2f96032c766bf08ad83f8a8897",
    "identical_copy_sha256": "3ec3877786e24d71a5f181192ed4d5aa36a7ed2f96032c766bf08ad83f8a8897"
  },
  {
    "original": "verify/2026-10-18-048-adopter-quickstart-pilot/smoke.log",
    "retained": "verify/2026-10-11-048-adopter-quickstart-pilot/smoke.log",
    "original_sha256": "62ddbb66944df652a81992d95932f718c1d3eb132a1f31e91bd7c8cb32e83715",
    "identical_copy_sha256": "62ddbb66944df652a81992d95932f718c1d3eb132a1f31e91bd7c8cb32e83715"
  },
  {
    "original": "verify/2026-10-18/T-222/red.log",
    "retained": "verify/2026-10-11/T-222/red.log",
    "original_sha256": "68ac5ba6f6be6a639a045ec630fefb2843c397c7043559b97c7e94dda2fc9033",
    "identical_copy_sha256": "68ac5ba6f6be6a639a045ec630fefb2843c397c7043559b97c7e94dda2fc9033"
  },
  {
    "original": "verify/2026-10-18/T-222/green.log",
    "retained": "verify/2026-10-11/T-222/green.log",
    "original_sha256": "93b9259709c9d6386a587c27c7b8e34fee117870c63320688717ddfb451b6051",
    "identical_copy_sha256": "93b9259709c9d6386a587c27c7b8e34fee117870c63320688717ddfb451b6051"
  }
]
```

## Genuine GREEN chronology recovery

Independent review found that initial native RED and GREEN headers both recorded 2026-10-18T12:16:55+11:00. Their original bytes are preserved privately; the prior mapping above describes that initial retention. One real GREEN rerun used the identical TASKS acceptance command against candidate `a0c7774743cf1333023e144f7e763d1ba4a25378`, after the collector. It genuinely passed and produced the unchanged native header timestamp 2026-10-18T12:20:03+11:00. The approved GREEN path now retains these exact rerun bytes; no timestamp/header was edited. RED remains unchanged. Document/source, separate AC observations and collector block are unchanged; collector evidence remains bound to ancestor `10bcd08545f8cadb18b179bd582a809f9646fe93`. This rerun is later confirmation, not a relabeling of the original collector observation. Current mapping and command provenance follow.

```json
{
  "reason": "Independent review found original native RED/GREEN recorded within same second; genuine new GREEN required for strict chronology. No header edits.",
  "original_green_sha256": "93b9259709c9d6386a587c27c7b8e34fee117870c63320688717ddfb451b6051",
  "original_green_timestamp": "2026-10-18T12:16:55+11:00",
  "original_green_private_capture": "/private/tmp/factory-t222-merge-mode-proof-20261018/green-chronology-recovery/original-green.log",
  "rerun_green_sha256": "f541bd73b8ac07f5a8c7ef400546ead45581d05f91a25d113122fab29a535856",
  "rerun_green_timestamp": "2026-10-18T12:20:03+11:00",
  "rerun_original_path": "verify/2026-10-18/T-222/green.log",
  "rerun_private_capture": "/private/tmp/factory-t222-merge-mode-proof-20261018/green-chronology-recovery/rerun-green.log",
  "approved_retention_path": "verify/2026-10-11/T-222/green.log",
  "retained_sha256": "f541bd73b8ac07f5a8c7ef400546ead45581d05f91a25d113122fab29a535856",
  "red_timestamp": "2026-10-18T12:16:55+11:00",
  "strict_red_before_green": true,
  "command": {
    "label": "green-chronology-recovery",
    "argv": [
      "bash",
      ".claude/scripts/tdd-ledger.sh",
      "green",
      "T-222",
      "python3 -c \"from pathlib import Path; t=Path('docs/FACTORY-ADOPTER-QUICKSTART.md').read_text(); assert all(s in t for s in ['Prerequisites','Dry-run adoption','immutable','existing','python3 .claude/scripts/factory-adopt.py --from /path/to/reviewed-harness --into /path/to/target --dry-run']); assert not any(s in t for s in ['qyndex','C0C7T1Y29K5','5251754','T0B2VADDUG4']); print('AC-1 quickstart adoption contract passed'); from pathlib import Path; t=Path('docs/FACTORY-ADOPTER-QUICKSTART.md').read_text(); assert all(s in t for s in ['Protected readiness','factory-preflight.py --policy /path/to/protected-policy.json','block','merge authority','reporting','production','secrets']); print('AC-2 protected readiness contract passed'); from pathlib import Path; t=Path('docs/FACTORY-ADOPTER-QUICKSTART.md').read_text(); assert all(s in t for s in ['Delivery and acceptance','engineering verification','merged delivery','product acceptance','SLO','rollback','FACTORY-ADOPTER-SETUP.md','FACTORY-ACTIVATION.md']); print('AC-3 distinct delivery and acceptance contract passed')\""
    ],
    "source_commit": "a0c7774743cf1333023e144f7e763d1ba4a25378",
    "started_at": "2026-10-18T01:20:03.019860+00:00",
    "finished_at": "2026-10-18T01:20:03.072077+00:00",
    "exit_code": 0,
    "stdout": "\u26a0 GREEN captured but NO red.log exists for T-222.\n  TDD requires red BEFORE green. This task will fail verify.sh's TDD gate.\n\u2713 GREEN captured: verify/2026-10-18/T-222/green.log (exit 0 \u2014 passing)\n",
    "stderr": "\u26a0 tdd-ledger: no timeout/gtimeout found \u2014 accept command runs UNBOUNDED. brew install coreutils to fix.\n"
  },
  "document_source_unchanged": "10bcd08545f8cadb18b179bd582a809f9646fe93",
  "collector_source_unchanged": "10bcd08545f8cadb18b179bd582a809f9646fe93",
  "per_ac_and_collector_not_rerun": true
}
```

The native GREEN command warned that its actual-date directory had no red.log after the initial capture was moved privately. Its complete warning is retained above in stdout. The unchanged genuine earlier RED exists at the approved retention path. The retained pair is independently checked with the byte-identical canonical checker in a private fixture; no real task status or ledger header is modified.

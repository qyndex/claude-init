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

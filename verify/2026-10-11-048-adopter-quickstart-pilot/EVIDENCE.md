## Evidence Bundle — Spec 048 (048-adopter-quickstart-pilot)
Spec: `specs/active/048-adopter-quickstart-pilot.md` · Commit: `776cb3f`

### Acceptance criteria (3/3 proven)
| AC | Proven by | Result |
|----|-----------|--------|
| AC-1 | tagged test | ✓ PASS |
| AC-2 | tagged test | ✓ PASS |
| AC-3 | tagged test | ✓ PASS |

### Smoke test (exit codes are load-bearing)
```
# Smoke test — 2026-10-16T13:06:11+11:00
$ bash .claude/scripts/verify.sh

→ Integration coverage gate
  ✓ changed API/DB files have integration tests

verify: PASS
exit: 0
---
```

### Visual proof and API traces
None: this candidate contains documentation and local evidence only. No screenshot, trace or HAR file is claimed.

### Coverage
Not measured: documentation acceptance uses the three protected Python commands and smoke. No line/branch coverage threshold is claimed satisfied by unknown values.

### Verdict: **PASS**

## Artifact index
- verify/2026-10-11-048-adopter-quickstart-pilot/evidence.json
- verify/2026-10-11-048-adopter-quickstart-pilot/pr-body.md
- verify/2026-10-11-048-adopter-quickstart-pilot/acceptance.log
- verify/2026-10-11-048-adopter-quickstart-pilot/EVIDENCE.md
- verify/2026-10-11-048-adopter-quickstart-pilot/results.json
- verify/2026-10-11-048-adopter-quickstart-pilot/smoke.log

## Evidence boundary and review disposition

This is local bootstrap acceptance evidence, not an independent attestation. The protected verifier and independent reviewer produce separate exact-head proofs after publication. The source commit names the tested ancestor; subsequent candidate changes are restricted to these approved evidence files. Requiring its own final evidence commit to contain its own hash would be circular. Actual16October execution timestamps remain unchanged by the fixed11October storage allowlist.

The three results.json command arrays are passed directly to subprocess.run without a shell. Each Python -c source was compiled and then executed again; acceptance.log records the exact JSON argv, stdout and exit0. JSON string delimiters are not part of argv. No command source or exit result was invented or repaired to address the review's syntax claim.

The earlier review correctly identified generated artifact-index references to the temporary16October collection directory. They now point to this committed11October directory; nonexistent screenshot/trace/HAR references were removed. The historical failed review remains retained outside this candidate; this disposition does not turn it into a passing review. Fresh protected review is still required.

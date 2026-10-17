# Actual frozen-report source triage

The frozen report remains unchanged and all 4 error findings continue to block the repaired gate. No blanket suppression was applied.

- `.github/workflows/memory-rollup-weekly.yml:33`: active workflow directly interpolates dispatch input into shell. This is the concrete independent T327 correction; re-scan the integrated source to prove removal.
- `.claude/scripts/factory-worker-guard.py:155`: intentional `subprocess.Popen` of an argv list, with no shell=True. The guardian validates legacy/protected entry contracts and may replace argv via the offline container adapter before launch. This source inspection does not prove all executable/argv inputs are trustworthy; preserve the finding pending independent contract/container review. Applying shell quoting to an argv list would not establish that boundary.
- `.claude/scripts/foreground-watchdog.py:30`: intentional argv launcher for supervised foreground work, no shell=True; rejects background flags and enforces a bounded timeout with process-group cleanup. This is not a command allowlist. Preserve the finding pending caller/guardian boundary review; no injection bypass is demonstrated by the report alone.
- `verify/2026-06-12-gap-fixes/staged/.github/workflows/adr-gate.yml:24`: historical staged fixture under verify, not an active `.github/workflows` file. It is still present in the frozen scan and still counted; no archival exclusion or suppression is added by T326.

The 150 remaining warning findings are not certified safe by this severity-gate repair. Root retains the existing 9 Git-blob SHA1 protocol findings' separate scope assessment. This task neither re-runs the worker suites nor substitutes local source inspection for their live/contract verification. Detailed frozen error identities, messages and paths are recorded in frozen-scan-triage.json.

# Candidate-reachable source history secret scan

Final baseline: scan all candidate-reachable source history with the actual workflow command `gitleaks git --redact --exit-code 1 --log-opts "--full-history HEAD" --config .gitleaks.toml`. This retains full source history and upstream detectors while excluding unrelated data refs. The previous default command scanned all refs, including reporting-state checkpoints that are not ancestors of the PR source. This is a controlled source-selector change for review; no provider, policy or merge authority is activated.

Actual current repository: 143 candidate-reachable commits; without ignore file RED reports 4 previously audited public audit/temporary fixture findings; with the final 4 exact fingerprints GREEN reports zero. No reporting-state off-branch fingerprints remain in `.gitleaksignore`. The initial all-ref 48-finding/21-fingerprint audit and logs below are retained only as superseded audit history. Current `candidate-red.log`, `candidate-green.log` and `current_candidate_findings` in audit.json describe the final baseline.

The executable regression `.claude/scripts/test/gitleaks-candidate-history.sh` reads the actual workflow scanner command and executes Gitleaks 8.30.1 against a temporary Git repository with the same config and ignore file. It proves: old default all-ref scan detects an unrelated-branch synthetic credential; actual candidate-scoped command passes clean candidate history; a newly committed candidate credential in the previously baselined reports path is detected; after removing it in a later clean commit, it remains detected in ancestor history. All synthetic values/reports are discarded. The redacted regression summary is retained. Full actionlint, workflow baseline suite, shell syntax and diff whitespace checks pass.

An early attempt to suppress ignores using an empty `--gitleaks-ignore-path` directory still loaded default ignores and found zero; this was not RED proof. The actual RED was rerun with `.gitleaksignore` temporarily absent and found four. No evidence is claimed from that ineffective override.

## Superseded initial all-ref audit — 21-entry proposal NOT shipped (retained provenance)

# Exact historical secret-scan baseline

Gitleaks 8.30.1 with the unchanged shipped `.gitleaks.toml` and default full-history `git` command scanned 397 commits (~14.20 MB). RED found 48 generic-api-key heuristic matches. GREEN with `.gitleaksignore` found zero. The 48 findings collapse to 21 distinct scanner fingerprints because multiple keys share line 1 of historical minified JSON. The ignore file contains those 21 exact commit:path:rule:line fingerprints only, with reasons per class. No new path/rule exemption, workflow change or detector disablement was added.

Every finding was checked against its exact historical blob and scanner span without retaining matched values. The audit JSON records file, commit, line, fingerprint, classification and field paths only:

- 40 historical public reporting-state matches: derived SHA-256 alert/digest idempotency keys. All report stream hashes and each report's alert/digest key derivations were independently recomputed from public report fields and verified equal. Older report schema revisions omit the optional alerts root.
- 6 public audit JSON matches: public reporting receipt/confirmed-alert key fields, 64-character hash identifiers. These identify delivery/alert operations and do not authenticate requests.
- 2 retained failed Spec050 route-test log matches: 32-character receipt delivery_token generated in the discarded local temporary fixture. The failed native delivery was unavailable; these are not provider/Slack/GitHub credentials or reusable live receipts. The original failed log remains intact.

A separate fresh temporary Git repository copied the exact same scanner config and ignore file, then committed a deliberately synthetic api_key in the SAME reports path and line as an ignored historical report. Actual Gitleaks rejected it (exit 1, exactly one generic-api-key finding). This demonstrates the historical fingerprints do not suppress a new credential-shaped value in that path. The fixture value and raw scanner report were discarded; only bounded redacted output is retained.

Commands: `gitleaks git --redact --exit-code 1 --config .gitleaks.toml --report-format json --report-path <temporary-report>`, both before and after the ignore file; same command in the synthetic fixture. `git diff --check` passed. These are secret-scan baseline proofs, not hosted independent review or live shadow eligibility proof.

## Harness regression toolchain

Harness Validate installs pinned Gitleaks 8.30.1 from the official release archive before its all-tests loop and publishes the executable directory via GITHUB_PATH. The shipped regression checks both workflow pins and install ordering/exposure, then executes the actual source-scan command. A targeted validation executed the exact extracted installation shell with a controlled curl substitute supplying a local archive; it verified the exact official pinned Linux release URL/flags, extraction and GITHUB_PATH, then executed the locally extracted fixture binary/version. This proves installation shell wiring without claiming a Linux network download or Linux-binary execution on macOS. Actual GitHub Linux execution remains CI validation. Full actionlint, workflow baseline and candidate-history regression passed again.

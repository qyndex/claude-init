# Exact-source scanner audit policy (default off)

The operator approved design A on 2026-10-16. Implementation is not live approval. [ADR-0010](../../.claude/memory/decisions/0010-authenticated-exact-source-scanner-audit-policy.md) records the accepted architecture and separate activation boundary. The two proposed registry records describe intentional list-argv executors; they never authorize general scanner suppression, autonomous merge or deployment.

The normal Semgrep job remains available without any new environment or variable. It rejects every effective error and numeric security-severity >=7 under the existing SARIF semantics. To request audit mode, the caller must supply all three explicit arguments:

```bash
bash .claude/scripts/check-sarif.sh report.sarif \
  --audit-policy /canonical/checkout/.claude/security-audit-exceptions.json \
  --expected-registry-sha256 '<externally approved exact registry SHA256>' \
  --source-root /canonical/checkout
```

Computing that hash from a candidate registry does not authorize it. The caller must obtain it from a separately protected approval source. No protected hash, malformed hash or changed registry means failure, even if the candidate claims to suppress a finding. The gate reads raw SARIF without rewriting it. Accepted audit exceptions are counted and explicitly distinguished from a clean security scan. Numeric security-severity >=7 always blocks, including at an approved source location.

Each strict registry record binds an exact rule ID, canonical ASCII relative source path, one positive line number, whole-file SHA256, rationale and approval reference. Duplicate JSON keys/records, unknown fields, ambiguous or missing finding locations, duplicate findings, traversal and symlink source/root paths cannot grant approval. The verifier opens source directories/files without following symlinks. Every registry source hash is rechecked, including records absent from the current report. This deliberately supports a narrow inline source-location subset: artifact locations may contain only uri and optional %SRCROOT% uriBaseId, with no artifact-index resolution. Policy mode rejects supplied run.originalUriBaseIds mappings, including empty maps, and supplied invocation.workingDirectory, rather than guessing how to remap a source root. Unsupported locations remain unapproved; ordinary unwaived SARIF severity behavior is unchanged. SARIF suppression metadata is not an approval input.

## Reviewed boundaries

- `.claude/scripts/factory-worker-guard.py:155` is the legacy list-argv worker launcher. Routed callers pin runtime executables, filter coordinator environment and retain claims/fencing/cleanup. Mandatory intake rejects the legacy entry and uses separately pinned descriptors/native launch. Native same-user filesystem isolation is not proven. See `factory-worker-environment.sh`, `factory-supervisor.sh`, `factory-container.sh` and the T329 exact-source contract evidence.
- `.claude/scripts/foreground-watchdog.py:30` intentionally wraps an operator command in bounded process-group lifetime control. Its overnight caller supplies separate Claude argv. It inherits operator environment and is not a credential isolation or mandatory intake boundary. Literal argv/timeout/descendant contracts were tested; this is not a general sandbox claim.

The local fake-daemon tests establish adapter contracts; actual Linux Docker isolation was explicitly skipped in the local triage. The installable staged ADR input repair is not exempted by these records. Other scanner warnings have not been certified safe.

## Producer trust and activation package

`semgrep.yml` uses two mutually exclusive jobs. The original strict `semgrep` job runs without an environment whenever opt-in is absent or false, and for every non-main ref even when opt-in is true. Only explicit opt-in on `refs/heads/main` selects `semgrep-audit` with fixed environment `factory-security`. Its in-job guard checks the same main ref, verifies checkout HEAD equals `GITHUB_SHA`, and records that SHA. The scan, enforcement and raw-report upload run in that protected job; the expected registry hash is never transported into another job. No reporting/merge App keys or Slack tokens enter this workflow.

A skipped alternative job is not independent evidence of a passing scan. The current daily caller consumes the reusable workflow's aggregate `needs.semgrep.result` in `daily-batch-result`; activation review must verify the actual required-check names and caller aggregate include the selected job. Do not rely only on the conditionally skipped strict job name for opted-in main runs.

Raw SARIF remains retained for the approved 90 days and also submitted to advisory GitHub code scanning. SARIF can contain matched source snippets, including secret-rule matches. Artifact readers and code-scanning viewers may therefore see sensitive source material according to repository and GitHub access controls; public repository artifacts can be accessible to public readers. Review this exposure before activation, avoid inserting real secrets in fixtures, and handle any actual leaked secret through incident response. This documents the existing approved data flow and retention; it does not redact or silently shorten raw evidence.

The protected job pins checkout to `3d3c42e5aac5ba805825da76410c181273ba90b1` (v7), upload-artifact to `cf430e030ddbb5b0abf93d22962f4752f3646cd9` (v7), and upload-sarif to `6f2ac81f5cd81fe351a197ba0b00d91d03cd2aee` (v4). These commits were resolved from the official GitHub repository tag references (including the annotated CodeQL tag). Its container is `returntocorp/semgrep@sha256:529ee8a277ec8adc5b534d7c74eea0a47e9de21d62852b6ba7ac6ba9566845c3`, resolved from Docker Hub's public official repository manifest with content-digest verification. Retain those exact identities in the activation package and review changes before reuse; immutable execution dependencies do not freeze the remote p/ci, p/owasp-top-ten or p/secrets rule contents.

The SARIF gate ignores suppression metadata as approval. A local Semgrep 1.172.0 control retained an inline-nosem error in SARIF with `inSource` suppression both with and without `--disable-nosem`; both reports were rejected by the strict gate. That control does not establish every Semgrep version or the pinned container's behavior. Before activation, run the same extra-unapproved-inline-suppressed-finding negative against the exact pinned producer and retain its raw report/gate verdict. No scanner suppression flag or source waiver was added on an unverified assumption. The Python policy helper runs in isolated mode (`python3 -I`), excluding candidate script-directory/PYTHONPATH stdlib shadow imports; interpreter selection through PATH remains an execution-environment boundary.

Before activation, an independent reviewer and operator must review a concrete package containing:

1. Exact workflow/gate/helper/registry source revisions, whole-file source hashes and registry digest; the current proposed approval references are not a live authorization.
2. The actual `factory-security` environment configuration: deployment branch policy admits main only; appropriate operator protection is present; no implementation-agent credential has variable or environment-write authority.
3. `FACTORY_SECURITY_AUDIT_POLICY_SHA256` is an environment-scoped variable with the approved exact digest. Verify no same-named repository/organization variable provides fallback or shadowing. GitHub's `vars` context cannot independently attest a variable's origin; the workflow does not claim it can.
4. Repository opt-in remains off until that reviewed setup exists. A missing/unprotected auto-created environment is not approved setup. Main-only source and environment observations must be carried into the T289 readiness/cutover package.
5. Actual retained raw scanner output, positive exact-source acceptance, mutation/extra-error/numeric-high negative controls, and the operator's concrete cutover approval. Recheck environment/source/registry changes before reuse.

No environment, variable or secret is created by installing these files. Missing approval keeps the live scanner gate blocked. Changes to a record, source bytes, rule, path or location require a new concrete review and protected digest update; candidate PR content cannot update that trust anchor.

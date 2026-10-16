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

`semgrep.yml` uses two mutually exclusive jobs. When repository variable `FACTORY_SECURITY_AUDIT_ENABLED` is absent or differs from `true`, the original strict job runs with no environment. When explicitly enabled, a separate job uses fixed environment `factory-security`, checks `GITHUB_REF == refs/heads/main`, checks the checkout HEAD equals `GITHUB_SHA`, and records that SHA. The raw report stays in its own job and is retained as an artifact for90 days. The expected registry hash is read only in that protected job; it is never transported into a candidate/untrusted job. No reporting/merge App keys or Slack tokens enter this workflow.

Before activation, an independent reviewer and operator must review a concrete package containing:

1. Exact workflow/gate/helper/registry source revisions, whole-file source hashes and registry digest; the current proposed approval references are not a live authorization.
2. The actual `factory-security` environment configuration: deployment branch policy admits main only; appropriate operator protection is present; no implementation-agent credential has variable or environment-write authority.
3. `FACTORY_SECURITY_AUDIT_POLICY_SHA256` is an environment-scoped variable with the approved exact digest. Verify no same-named repository/organization variable provides fallback or shadowing. GitHub's `vars` context cannot independently attest a variable's origin; the workflow does not claim it can.
4. Repository opt-in remains off until that reviewed setup exists. A missing/unprotected auto-created environment is not approved setup. Main-only source and environment observations must be carried into the T289 readiness/cutover package.
5. Actual retained raw scanner output, positive exact-source acceptance, mutation/extra-error/numeric-high negative controls, and the operator's concrete cutover approval. Recheck environment/source/registry changes before reuse.

No environment, variable or secret is created by installing these files. Missing approval keeps the live scanner gate blocked. Changes to a record, source bytes, rule, path or location require a new concrete review and protected digest update; candidate PR content cannot update that trust anchor.

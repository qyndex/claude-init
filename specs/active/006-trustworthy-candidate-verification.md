---
id: 006
slug: trustworthy-candidate-verification
status: approved
owner: "@codex"
human_owner: "@operator"
created: 2026-10-09
updated: 2026-10-16
complexity: L
objective: KR-PLATFORM
service_tier: T2
feedback_refs: []
---

# Spec 006: Trustworthy candidate verification

## Problem statement

The repository audit found false success in candidate verification, scanners and evidence emission, plus failing baseline workflows/tests. The operator approved the factory improvement plan and requested implementation on 2026-10-09. This specification implements its first baseline repair slice; independent attestation, merge authority and durable orchestration remain later packages.

## Goals

Repair deterministic local verification and workflow baseline. Preserve existing initiative edits and historical audit artifacts. Use failing regression fixtures before each implementation change.

## Acceptance criteria

1. **AC-1**: Trusted coordinator verification scripts accept an explicit candidate root, reject a missing root, and run candidate-local commands there. Verified merge runs smoke, heavy and contract checks against that candidate after both rebase and mediation. Missing required scripts block instead of silently skipping. Failing dry-run verification must not advertise a passing merge.
2. **AC-2**: Local scanner invocation distinguishes unavailable tools from findings/execution failure; either blocks an explicitly selected applicable check. A failing installed scanner cannot become PASS through a fallback echo.
3. **AC-3**: Evidence collection rejects missing AC identifiers, unsuccessful runner execution, missing/malformed output and emission failure. Fresh attempts cannot reuse earlier results. A valid check-only bundle may consume existing explicitly prepared results, but still requires AC proof and valid JSON.
4. **AC-4**: Unsupported consumed contract types fail. Missing contract analysis remains an explicit legacy no-contract applicability outcome, pending F-01's required applicability contract.
5. **AC-5**: Workflow lint rejects no invalid job-level hashFiles conditions; Semgrep crashes/missing/malformed SARIF block, numeric high severity blocks, and an in-progress daily batch blocks merge eligibility.
   **AC-5 SARIF clarification (T-326, 2026-10-16)**: omitted result severity inherits the identified rule default; explicit result level takes precedence. Driver rule IDs, indexes and their identity agreement must be checked; ambiguous/malformed references fail closed. SARIF non-failure result kinds use their prescribed severity semantics; numeric security-severity still gates failure findings. Invalid consumed severity/kind/configuration cannot become a clean scan. Unsupported external rule/configuration resolution fails closed rather than silently ignoring metadata. The actual frozen Semgrep report must be rechecked and remaining findings reported without blanket suppression. This repairs the existing error/malformed-output gate contract and does not certify the entire repository security-clean.
6. **AC-6**: Open-question aging uses calendar dates consistently across Sydney daylight-saving changes. Dependency rollup handles intentionally empty stack/artifact sets while surfacing upstream failure and malformed artifacts.
7. **AC-7**: Malformed proposed ADR frontmatter is repaired without changing the decision. Historical patch-promotion tests assert installed behavior instead of reapplying already-promoted patches; genuine security coverage remains tested.
8. **AC-8**: All maintained shell suites and structural validation pass on this checkout's macOS runtime. Workflow lint and warning-level ShellCheck pass for changed code. Linux execution must be recorded separately from GitHub CI. Repair demonstrated date/awk portability failures in maintained suites; do not infer Linux health from macOS results.

9. **AC-9 (weekly dispatch input remains data)**: T-327 passes the optional manual week input through the weekly rollup step environment and a quoted shell argument. Shell substitutions and quote payloads remain literal or are rejected without executing commands. A valid ISO week reaches the intended rollup command; empty input retains current-week behavior and existing rollup validation stays unchanged. Tests execute the actual extracted workflow step with isolated command fixtures, without real GitHub writes or network calls. No trigger, permission or secret-access changes.

10. **AC-10 (supported staged ADR inputs remain data)**: T-328 repairs the still-installable staged ADR workflow to pass base-ref context through step environment and quoted argv, preserving its trigger, permissions and ADR decision logic. The installer installs the repaired payload byte-for-byte. Behavioral tests execute the actual supported and installed steps with isolated Git fixtures, proving shell-like substitutions and quotes remain literal and normal G40 ADR decisions still hold. Preserve the original snapshot identity as historical evidence; do not remove supported assets from scanning.

11. **AC-11 (authenticated exact-source audit exceptions)**: T-329 adds a default-off audit policy mode. An exact registry digest supplied outside candidate control authenticates strict rule/path/line/whole-source-SHA256 records with rationale and approval reference. Missing/mismatched approval, malformed or duplicate records, source/path/line/rule changes and additional unapproved errors block. Numeric security-severity >=7 is never waived; SARIF suppression metadata grants no approval, and raw scan bytes stay unchanged. Accepted audit exceptions are reported distinctly from a clean scan. The opt-in producer runs only from a frozen main checkout under a separately protected main-only factory-security environment; its hash never crosses into candidate execution. Default scanning needs no new environment. Initial two reviewed command-runner records and contract evidence remain inactive until concrete policy/environment/source review and operator cutover approval. No live setup or policy activation is authorized by implementation design approval.

## Non-goals

No automatic merging, production deployment, credential provisioning, schedule installation or constitution changes. No claim that these repairs establish trusted independent review, complete applicability, all required coverage, or safe rollback; those are later specifications. This spec does not close the entire F-00–F-04 readiness gate.

## Constraints

Bash 3.2 and Linux-compatible commands; no paid model invocation for fixtures. Audit findings A01–A03, A07, A09 and A24 drive scope. Existing dangerous rollback route is not exercised by testing.

## Open questions

Factory digest channel, production decision policy and trusted verification host are being asked independently; none blocks these repairs.

## References

- docs/audits/2026-10-09-repository-audit.md
- plans/AI-SOFTWARE-FACTORY.md

---
id: 006
slug: trustworthy-candidate-verification
status: approved
owner: "@codex"
human_owner: "@operator"
created: 2026-10-09
updated: 2026-10-09
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
6. **AC-6**: Open-question aging uses calendar dates consistently across Sydney daylight-saving changes. Dependency rollup handles intentionally empty stack/artifact sets while surfacing upstream failure and malformed artifacts.
7. **AC-7**: Malformed proposed ADR frontmatter is repaired without changing the decision. Historical patch-promotion tests assert installed behavior instead of reapplying already-promoted patches; genuine security coverage remains tested.
8. **AC-8**: All maintained shell suites and structural validation pass on this checkout's macOS runtime. Workflow lint and warning-level ShellCheck pass for changed code. Linux execution must be recorded separately from GitHub CI. Repair demonstrated date/awk portability failures in maintained suites; do not infer Linux health from macOS results.

## Non-goals

No automatic merging, production deployment, credential provisioning, schedule installation or constitution changes. No claim that these repairs establish trusted independent review, complete applicability, all required coverage, or safe rollback; those are later specifications. This spec does not close the entire F-00–F-04 readiness gate.

## Constraints

Bash 3.2 and Linux-compatible commands; no paid model invocation for fixtures. Audit findings A01–A03, A07, A09 and A24 drive scope. Existing dangerous rollback route is not exercised by testing.

## Open questions

Factory digest channel, production decision policy and trusted verification host are being asked independently; none blocks these repairs.

## References

- docs/audits/2026-10-09-repository-audit.md
- plans/AI-SOFTWARE-FACTORY.md

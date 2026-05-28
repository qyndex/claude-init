---
name: okr-align
description: Check that a spec or initiative aligns with a current-quarter OKR. Run automatically during /specify (Phase 2) and /initiative create. Flags work that has no KR backing.
when_to_use: Auto-runs during /specify and /initiative. Manual invocation when reviewing the backlog ("does this work map to a KR?"). User says "how does this align with Q3?".
argument-hint: "<spec-id-or-initiative-id>"
allowed-tools: Read, Glob, Grep
model: inherit
disable-model-invocation: true
---

# OKR Align

Every spec and initiative must declare which KR it serves. This skill is the alignment gate.

## Process

1. Read the target artifact (`specs/active/<id>.md` or `initiatives/active/<id>.md`).
2. Read `OKRs.md` to enumerate current-quarter KRs.
3. Check the artifact's frontmatter:
   - Spec: `objective: KR-<QYYYY>-<NN>` (required for non-trivial specs)
   - Initiative: KR linked in `## Strategic context`
4. Surface mismatches:
   - Missing field
   - KR ID doesn't exist in current quarter
   - KR is closed/superseded
5. Recommend next action:
   - "Add `objective: KR-2026Q3-04` to spec frontmatter"
   - "Propose a new KR in next quarter's cut" (if work is opportunistic but valid)
   - "Defer this spec until aligned with a future KR"

## What's exempt

- Bug fixes ≤ 20 LOC (per CLAUDE.md §VIII)
- Security patches (always urgent; KR-tagged retroactively)
- Compliance-driven work (use `KR-COMPLIANCE` synthetic tag)
- Platform / infra work that serves multiple KRs (use `KR-PLATFORM` synthetic tag)

## Output

```
OKR alignment check — spec 042
- objective: KR-2026Q3-04 ✓ (matches "Checkout failure rate 2.1% → 0.5%")
- KR owner: @alex (matches initiative 037 sponsor)
- KR status: active
- Verdict: ALIGNED

Initiative 042
- KR: KR-2026Q3-01 ✓
- KR-2026Q3-02 ✓
- KR-2026Q3-03 ✓
- Verdict: ALIGNED (3 KRs)
```

Mismatch example:
```
OKR alignment check — spec 058
- objective: missing
- Suggested KRs based on spec body:
  - KR-2026Q3-06 (tech debt) — confidence 70%
- Verdict: NEEDS-ALIGNMENT
  Recommend: edit specs/active/058-foo.md frontmatter → `objective: KR-2026Q3-06`
```

## Hard rules

- **Don't auto-assign a KR.** Always surface for human confirmation.
- **Synthetic tags (`KR-COMPLIANCE`, `KR-PLATFORM`) require a one-line rationale** in the spec.
- **Closed-KR alignment is invalid.** If a spec aligned to KR-2026Q2-* that's now closed, prompt the user to either close the spec or re-align.

## Hook

This skill is invoked automatically by:
- `/specify` (Phase 2 of 8-phase workflow) — gates spec approval
- `/initiative create` (gates initiative activation)
- `/roadmap cut` (validates all NOW items)

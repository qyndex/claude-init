---
name: specify
description: Author a feature spec under specs/active/. Captures problem, user stories, acceptance criteria, constraints, open questions. Phase 2 of the eight-phase workflow. Delegate the actual drafting to the architect agent.
when_to_use: User says "spec out", "write a spec for", "what's the spec for", "let's design X", or starts any feature larger than a 20-line bug fix.
argument-hint: "<feature name or one-line summary>"
model: opus
allowed-tools: Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, TodoWrite
---

# Specify

You are starting Phase 2 of the eight-phase workflow. Your output is a complete spec file under `specs/active/`.

## Process

1. **Allocate an ID.** `max(specs/active ∪ specs/archive) + 1` — archived ids are
   NEVER reused (e2e-audit spec-pipeline-5; reuse breaks TASKS.md spec: refs,
   analyze markers, and evidence dirs):
   `printf '%03d' $(( $(ls specs/active specs/archive 2>/dev/null | grep -oE '^[0-9]+' | sort -n | tail -1 | sed 's/^0*//') + 1 ))`
   Format `<id>-<slug>.md` (zero-padded to 3 digits: `001-user-login.md`).
   validate.sh fails duplicate ids across active+archive.
2. **Delegate to the architect** agent if the spec is non-trivial (any feature ≥ 100 LOC of expected impact). Otherwise inline.
3. **Use the template** at `specs/templates/spec.md`.
4. **Resolve open questions** by asking the user (one round, ≤ 4 questions via AskUserQuestion).
5. **Mark `status: approved`** when no open questions remain.

## Spec must contain

- Problem statement (what user pain, what business outcome)
- Goals (what's in scope) and Non-goals (what's explicitly out)
- User stories (`As a <role> I want <capability> so that <outcome>`)
- Acceptance criteria (testable, measurable, observable)
- Constraints (perf, security, compliance, compat)
- Open questions (with `[OQ]` prefix; spec is not approved until all are closed)
- Dependencies on other specs/features
- Estimated complexity (S / M / L / XL)

## Hard rules

- **No solutions.** The spec describes *what*, not *how*. Architecture goes in the plan.
- **Testable acceptance.** Each criterion must be expressible as a test or a metric.
- **No ambiguity.** Words like "fast", "user-friendly", "secure" must be quantified.
- **Cite the source.** If the spec implements a stakeholder ask, link the issue/doc/ticket.
- **Single feature.** If the spec spans multiple features, split it.

## Output

```
specs/active/<id>-<slug>.md   (status: draft → approved)
```

After save, notify the user: "Spec specs/active/<id>-<slug>.md ready. <N> open questions remain. Ready for /plan when approved."

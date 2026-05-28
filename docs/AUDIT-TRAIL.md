# Audit trail — answering "why and when did this happen?"

For a software factory that runs for years, the question is rarely *what* the code does today. It's:

- "When did we decide this approach?"
- "Who owned this and is that still true?"
- "What changed in the spec after we shipped phase 1?"
- "Which PR introduced this flag, and is it still gated?"
- "Why was this acceptance criterion removed?"

This doc gives you the recipes. Memory + git + the harness conventions cover all of them.

---

## 1. "When did we decide X?" (Decision archaeology)

ADRs are the durable record. Patterns are the stylized record. Specs are the *current* record. Use the right one.

```bash
# All ADRs that mention <topic>
grep -rl "<topic>" .claude/memory/decisions/

# All ADRs that touched authn over the last year
git log --since='1 year ago' --diff-filter=A --name-only .claude/memory/decisions/ \
  | xargs grep -l 'authn\|authentication'

# Walk supersession chain backward
grep -E '^- \*\*Status\*\*:.*superseded by' .claude/memory/decisions/ADR-XXXX.md
# → ADR-XXXX is superseded by ADR-YYYY
# → recurse into ADR-YYYY

# Find the ADR that ratified a current pattern
grep -E '^- \*\*Related ADRs?\*\*:' .claude/memory/patterns/<pattern>.md
```

---

## 2. "Who owns this?" (Ownership archaeology)

Ownership is encoded in three places: specs (`human_owner:`), ADRs (`Owners:`), and tasks (`owner:`).

```bash
# All specs owned by @alice
grep -l 'human_owner:.*@alice' specs/active/*.md specs/archive/*.md

# All ADRs owned by @alice
grep -lE '^- \*\*Owners?\*\*:.*@alice' .claude/memory/decisions/*.md

# All pending tasks owned by @alice
grep -A 5 '^- \[ \]' tasks/TASKS.md | grep -B 5 'owner:.*@alice'

# A person left — re-assign everything they owned
/owner-walk @alice --reassign-to @bob
```

---

## 3. "What changed in the spec?" (Scope drift)

Specs accumulate scope changes after `status: approved`. The `## Change history` section is the record.

```bash
# All scope changes on a spec
awk '/^## Change history/,/^## /' specs/active/042-checkout-v2.md \
  | grep -E '^- 20[0-9]{2}-[0-9]{2}-[0-9]{2}'

# Git history of the spec file
git log --follow -p specs/active/042-checkout-v2.md

# Detect drift — has the code drifted from the spec's AC?
/spec-drift-check 042
```

---

## 4. "When did this flag exist? Is it still gated?" (Flag archaeology)

```bash
# When was the flag added?
git log --diff-filter=A -S 'init_042_checkout_v2' --format='%h %ad %s'

# Is it still referenced in code?
grep -rE 'flag\(|isFeatureEnabled\(' src/ | grep init_042_checkout_v2

# Is it still in the flag registry?
grep init_042_checkout_v2 .claude/memory/flags/REGISTRY.md

# All flags older than 90 days that are still 100% (should be cleaned)
/flag list --stale
```

---

## 5. "Which PR introduced this?" (Code archaeology)

```bash
# The commit that introduced a line
git blame -L <line>,<line> <file>

# The PR that landed a commit (GitHub)
gh pr list --search "<sha>"  # or:
gh api repos/:owner/:repo/commits/<sha>/pulls

# All PRs that touched a file in the last 90 days
gh pr list --search "<file>" --state merged --limit 50

# Conventional commit type — what kind of changes have hit auth/?
git log --since='6 months ago' --format='%s' src/auth/ \
  | grep -oE '^(feat|fix|refactor|perf|security)' \
  | sort | uniq -c | sort -rn
```

---

## 6. "Why was this AC removed?" (Spec history)

```bash
# Diff between two spec versions (using git, the spec file is source of truth)
git log -p --follow specs/active/042-checkout-v2.md \
  | grep -E '^-.*AC-|^\+.*AC-'

# A removed AC will appear as a `- - **AC-N**:` line in some commit
# Find the commit + read its message for the why
git log --follow -S 'AC-3' specs/active/042-checkout-v2.md --format='%h %ad %s'
```

---

## 7. "What incidents have hit this subsystem?" (Pain archaeology)

```bash
# All incidents touching auth code
grep -rlE 'src/auth/|authn|authentication' .claude/memory/incidents/

# Recurrent incidents (frontmatter has recurred_at)
grep -rl '^recurred_at:' .claude/memory/incidents/

# Postmortems with outstanding action items
grep -rL 'status: closed' .claude/memory/incidents/*postmortem*.md

# Highest-pain subsystems (count incidents per top-level path)
grep -rhE '^affected_paths:' .claude/memory/incidents/ \
  | awk -F'/' '{print $1"/"$2}' | sort | uniq -c | sort -rn
```

---

## 8. "When was an ADR last verified?" (Trust archaeology)

```bash
# ADRs accepted >12mo ago with no last_verified
/adr-walk --verify-links

# All accepted ADRs sorted by last_verified
grep -lE '^- \*\*Status\*\*:.*accepted' .claude/memory/decisions/*.md \
  | xargs grep -lE '^- \*\*last_verified\*\*:' \
  | xargs -I{} sh -c 'echo "$(grep last_verified {} | head -1) | {}"' \
  | sort
```

---

## 9. "Where's the on-call runbook for X?" (Operational archaeology)

```bash
# Service runbooks
ls docs/runbooks/

# SLO target for a service
grep -A 3 '^- name: <service>' slo.yml

# Last 5 incidents for a service
grep -rl 'service: <service>' .claude/memory/incidents/ | sort -r | head -5
```

---

## 10. "What did we promise in the spec and did we deliver?" (Outcome archaeology)

```bash
# Spec said p95 < 200ms. Did we ship that? Re-run accept:
/spec-drift-check 042

# Trend baseline — did perf regress since we shipped?
/perf-trend src/checkout

# Success metric on the rollout — did it move?
grep -A 3 '^success_metric:' specs/active/042-checkout-v2.md
# → query the dashboard URL
```

---

## Git conventions that make audit easy

The harness enforces (via CLAUDE.md §VI + commitlint workflow) **Conventional Commits + trailers**:

```
feat(checkout): add v2 cart route

Constraint:  must not break v1 callers
Rejected:    full rewrite | too expensive
Directive:   spec 042 AC-3
Confidence:  high
Scope-risk:  localized
Not-tested:  edge cases for empty cart

Spec: specs/active/042-checkout-v2.md
Plan: plans/active/042-checkout-v2.md
Task: T-119
```

This means every commit answers WHY without needing to chase down old Slack threads. **`Spec:` + `Plan:` + `Task:` trailers are the durable backlinks** that survive PR squash-merges.

`/audit-trail <topic>` runs all of these recipes against a topic.

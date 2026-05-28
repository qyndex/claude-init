---
description: Codify a recurring anti-pattern into a semgrep rule. Fires when an incident's recurred_at counter ≥ 2, or manually for any anti-pattern. Auto-drafts under .semgrep/learned/ and opens a PR.
argument-hint: "<incident-id-or-slug> [--dry-run]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /codify-rule — turn recurring incidents into lint rules

Round 5 E2. The audit found incidents accumulate `recurred_at:` markers but never become enforcement. This closes that loop: when an incident has recurred ≥2 times, draft a semgrep rule that catches the class.

```bash
target="${1:-}"
dry_run="${2:-}"

if [ -z "$target" ]; then
  echo "Usage: /codify-rule <incident-id> [--dry-run]"
  echo
  echo "Candidate incidents (recurred ≥ 2):"
  bash .claude/scripts/memory-index.sh query --type incident --recurred | jq -r '.id'
  exit 1
fi

# Find the incident file
incident_file=".claude/memory/incidents/${target}.md"
if [ ! -f "$incident_file" ]; then
  # Try fuzzy match
  incident_file=$(ls .claude/memory/incidents/*${target}*.md 2>/dev/null | head -1)
fi
[ ! -f "$incident_file" ] && { echo "Incident not found: $target"; exit 1; }

id=$(basename "$incident_file" .md)
mkdir -p .semgrep/learned

# Extract key signal from incident
signal=$(grep -A 1 '^## Root cause\|^## Signal\|^## Anti-pattern' "$incident_file" | tail -5 | head -3)

rule_file=".semgrep/learned/${id}.yml"

cat > "$rule_file" <<EOF
# Auto-drafted from .claude/memory/incidents/${id}.md
# This rule needs human review before going into CI. Edit the patterns below.
#
# Why it exists: this incident has \`recurred_at:\` ≥ 2 entries — meaning the
# same class of bug shipped at least twice. Codifying as a rule prevents the
# third occurrence.

rules:
  - id: learned-${id}
    message: |
      This matches the anti-pattern from incident ${id}.
      ${signal:-See incident for context.}
      See: .claude/memory/incidents/${id}.md
    severity: WARNING
    languages: [generic]
    # TODO(human): replace the placeholder pattern below with the real anti-pattern
    # from the incident. Until then this rule is INERT: it matches only the literal
    # sentinel string (which never appears in real code), so it is safe to commit and
    # `semgrep --config <file>` parses it WITHOUT error. A bare comment as the pattern
    # — the previous stub — is not a valid semgrep pattern and aborts the whole scan.
    pattern: "REPLACE_ME_WITH_INCIDENT_SPECIFIC_PATTERN"
    paths:
      include:
        - "**/*"
EOF

echo "✓ Drafted rule: $rule_file"
echo
echo "Next steps:"
echo "  1. Read .claude/memory/incidents/${id}.md to understand the anti-pattern"
echo "  2. Edit $rule_file — replace the REPLACE_ME stub with concrete pattern(s)"
echo "  3. Test locally: semgrep --config=$rule_file ."
echo "  4. Add the rule path to .semgrep.yml include list"
echo "  5. Commit with Conventional Commit: feat(semgrep): codify ${id} pattern"
echo "  6. The daily-batch semgrep job will pick it up on next 8am run"

if [ "$dry_run" != "--dry-run" ]; then
  # Open follow-up task
  cat > /tmp/codify-finding.md <<EOF
- [ ] Refine .semgrep/learned/${id}.yml stub to actual patterns from incident ${id}
EOF
  bash .claude/scripts/findings-to-tasks.sh /tmp/codify-finding.md \
    --priority security \
    --source "codify-rule:${id}" \
    --default-owner "@security-team"
  rm -f /tmp/codify-finding.md
fi
```

## How this gets triggered

A subagent can't invoke a slash command, so the loop is closed by data, not by magic:

1. The reviewer (`agents/quality/reviewer.md`) and security (`agents/quality/security.md`) agents check `recurred_at` on every memory-read pass. When the counter hits ≥ 2, they **add a finding to their NEXUS handoff**: `Run /codify-rule <id> — incident recurred N times`.
2. `findings-to-tasks.sh` converts that finding into a `priority: security` task in `tasks/TASKS.md`.
3. A human (or the next autopilot pass picking up the security task) runs `/codify-rule <id>`.

There is also a nightly backstop: `dream-cron` scans `.claude/memory/incidents/` for any incident with `recurred_at` ≥ 2 that has **no** matching `.semgrep/learned/<id>.yml`, and queues the same security task — so a recurrence never silently fails to become a rule, even if the agents missed it.

## Hard rules

- **Never auto-commit the rule.** A bad rule that catches false positives erodes trust in semgrep more than the original bug erodes trust in code review. Human review the stub.
- **The stub is a starting point, not a finished rule.** It tells you WHAT to codify, not HOW.
- **One incident → one rule.** Don't bundle.
- **Test before adding to .semgrep.yml.** Run locally against the file the incident touched.

$ARGUMENTS

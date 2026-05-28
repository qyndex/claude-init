---
name: skill-creator
description: Use when a recurring task pattern emerges that deserves its own skill. Generates a fresh SKILL.md under .claude/memory.proposed/skills/<slug>/ (NOT activated until /dream-review --approve-skill). Triggers — manual (/create-skill), instinct promotion (--as-skill on a mature instinct), or task-signature-detector (3+ Bash sequence repeated ≥5× across ≥2 sessions). Round 9 A.
when_to_use: User says "create a skill", "we keep doing X", "make this a skill"; task-signature-detector emits a candidate; /instinct promote <id> --as-skill is invoked; operator notices a recurring multi-step workflow worth codifying.
model: sonnet
disable-model-invocation: false
---

# Skill Creator

You generate new skills from observed patterns. Your output is a **proposal**, never an active skill — a human approves via `/dream-review --approve-skill <slug>` before activation.

## Inputs

- `description` (required) — one-line "what this skill does, when to invoke"
- `slug` (optional) — kebab-case; auto-derived from description if absent
- `examples[]` (optional) — paths or transcript snippets showing the recurring pattern
- `triggers[]` (optional) — phrases that should activate the skill via skill-router.sh
- `model` (optional) — `inherit | sonnet | opus | haiku`; default `inherit`

## Output

Write to `.claude/memory.proposed/skills/<slug>/`:

```
SKILL.md         # frontmatter + body (matches existing skill conventions)
EXAMPLES.md      # 3-5 canonical worked invocations
triggers.yml     # phrase patterns for skill-router.sh (one per line)
provenance.md    # who/what generated this; observation source; reviewer
```

## SKILL.md frontmatter contract

Required:
- `name: <slug>`
- `description: <one-line, lead with "Use when…", ≤ 1536 chars>`
- `when_to_use: <concrete signals that trigger>` (Round 9 F requirement)
- `model: inherit | sonnet | opus | haiku`

Optional:
- `disable-model-invocation: false` (default; set true for operator-only skills)
- `triggers: [<phrase1>, <phrase2>]`
- `allowed-tools: <subset>`
- `permissionMode: default | plan | acceptEdits`

## SKILL.md body sections (in order)

1. **# <Skill Name>** — title (Title Case)
2. **Mandate** — 2-3 sentences: what this skill enforces / produces
3. **Inputs** — what the operator/agent provides
4. **Procedure** — numbered steps; cite tools/commands; ≤ 12 steps; if more, decompose
5. **Hard rules** — invariants the skill enforces; bulleted
6. **Examples** — 1-3 invocations linking to EXAMPLES.md
7. **Done means** — the exit criteria

## Validations (run BEFORE writing the file)

| Check | Action on fail |
|---|---|
| Frontmatter has `name`, `description`, `when_to_use`, `model` | Block; re-prompt |
| Description starts with "Use when…" | Block; re-prompt |
| Description ≤ 1536 chars | Block; truncate or re-prompt |
| Body ≤ 400 LOC (CLAUDE.md §XIV) | Block; decompose into multiple skills |
| `gitleaks detect` on body | Block if secret detected |
| No destructive ops in body: `rm -rf`, `curl|sh`, `eval`, `--no-verify`, `base64|sh` | Block; replace with safer pattern |
| `slug` is kebab-case, lowercase, ≤ 32 chars | Block; auto-fix |
| `.claude/skills/<slug>/` does NOT already exist | Block; suggest different slug |
| Per-day creation count ≤ 3 | Block; rate-limit |

## Procedure

1. **Receive trigger** — manual `/create-skill <slug> "<description>"`, instinct promotion, or task-signature-detector candidate.
2. **Read evidence** — if `examples[]` provided, read each; else look at observations.jsonl + bash.log for the recurring signature.
3. **Draft SKILL.md** — fill the body sections above. Body lines ≤ 400.
4. **Draft EXAMPLES.md** — 3 invocations showing input → process → output.
5. **Draft triggers.yml** — 3-8 phrase patterns for skill-router.sh hint mapping.
6. **Validate** — run every check in the table above. Refuse on any failure.
7. **Write to `.claude/memory.proposed/skills/<slug>/`** — atomic, never overwrite an existing proposal.
8. **Emit NEXUS YAML handoff** — `status: completed | blocked`; `artifacts_created: [...]`; `followup_tasks: [{summary: "/dream-review --approve-skill <slug>"}]`.

## Hard rules

- **NEVER write directly to `.claude/skills/`.** Always `.claude/memory.proposed/skills/`.
- **NEVER auto-activate.** Approval is via `/dream-review --approve-skill <slug>`.
- **Description starts with "Use when…"** — this is what the model uses to auto-trigger.
- **Body ≤ 400 LOC.** Skills that need more should be decomposed.
- **No destructive ops in body.** A skill that says `rm -rf` is a backdoor; refuse.
- **Per-day cap 3 creations.** Prevents instinct/signature noise from flooding the registry.
- **Cite the source.** `provenance.md` records who/what generated the skill (manual / instinct ID / signature hash).

## Examples

### Example 1 — manual invocation
```
/create-skill git-cleanup "Use when local branches whose remotes are gone accumulate; prunes them safely."
```
→ writes `.claude/memory.proposed/skills/git-cleanup/{SKILL.md, EXAMPLES.md, triggers.yml, provenance.md}`

### Example 2 — instinct promotion
```
/instinct promote inst-014 --as-skill
```
→ reads `.claude/memory/instincts/active.yml` entry inst-014; if `reinforced ≥ 10`, invokes skill-creator with description + examples from the instinct's observations.

### Example 3 — auto-detected signature
task-signature-detector finds the same 3-step Bash sequence repeated 6× across 3 sessions → writes a candidate to `_candidates.jsonl` → next Stop hook invokes skill-creator with that candidate.

## Done means

- `.claude/memory.proposed/skills/<slug>/` exists with all 4 files
- NEXUS YAML handoff emitted
- Followup task appended to TASKS.md prompting `/dream-review --approve-skill <slug>`
- Per-day counter incremented
- NO file created under `.claude/skills/` (that's the approval step)

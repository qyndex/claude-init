# Contributing to claude-init

Thanks for wanting to improve the harness. This repo is a **template `.claude/` scaffold** —
not a running app. There's no `package.json` or build step; every artifact is a shell script,
a Markdown file, or a JSON config. That shapes how you contribute.

Read [`CLAUDE.md`](CLAUDE.md) (the developer guide) and [`.claude/CLAUDE.md`](.claude/CLAUDE.md)
(the constitution the agent follows) before a non-trivial change.

## TL;DR

```bash
# 1. Fork + clone, then branch
git checkout -b feat/<short-slug>

# 2. Make your change under .claude/, .github/, docs/, scripts/, specs/, …

# 3. Validate (this is the "test suite" for this repo)
bash .claude/scripts/validate.sh          # must exit 0
shellcheck .claude/hooks/*.sh .claude/scripts/*.sh scripts/*.sh   # if you touched shell
find .claude .github .mcp.json -name '*.json' | xargs -I{} jq -e . {} >/dev/null  # JSON lint

# 4. Commit (Conventional Commits + trailers — see below), push, open a PR
```

## What to validate

`.claude/scripts/validate.sh` is the primary gate and is data-driven (it uses `find`, so
adding/removing files is reflected automatically). It checks JSON validity, YAML frontmatter,
executable bits, agent/skill/hook cross-references, security invariants, the constitution size
cap, MCP version pinning, and more. **A PR that fails `validate.sh` will not be merged.**

If you add a new script, `chmod +x` it. If you add a hook, register it in
`.claude/settings.json` (validate.sh fails until both sides exist). If you add an agent, its
frontmatter `model:` must match the routing table in `.claude/CLAUDE.md` §V.

## Commit format

Conventional Commits with git trailers (enforced by `commitlint.yml`):

```
feat(hooks): add pre-spawn cost gate

<body — what changed, how tested>

Constraint:    <what limited the design>
Rejected:      <alternative> | <why rejected>
Confidence:    high | medium | low
Scope-risk:    none | localized | broad

Co-Authored-By: Your Name <you@example.com>
```

Every `eslint-disable` / `# noqa` / `# type: ignore` needs a `JUSTIFICATION:` and `ISSUE: #N`
within 3 lines (enforced by `lint-exception-audit.yml`).

## The CI gates you'll meet on a PR

This repo dogfoods its own harness, so your PR runs the same gates the harness ships:

- **harness-validate** — runs `validate.sh`. Non-negotiable.
- **commitlint** — Conventional Commits + trailers.
- **claude-review / claude-security** — AI code + security review (advisory for community PRs).
- **evidence-gate** — expects proof that acceptance criteria pass. **Most PRs here are harness
  maintenance** (no application source), so they use the opt-in escape hatch: commit a
  `verify/<date>-<slug>/no-ac.json` describing the maintenance. `kind: "docs-only"` covers pure
  docs. See [`CLAUDE.md`](CLAUDE.md) → "the evidence-gate escape hatch". The hatch is rejected if
  the PR touches application source.

If Actions are disabled on a fork, a maintainer will run the gates on merge.

## Scope discipline (please read)

The harness follows **Karpathy's Four Principles** (`.claude/CLAUDE.md` §I): surgical changes,
simplicity first, every changed line traces to a stated goal. Concretely:

- **One concern per PR.** Don't refactor adjacent code you didn't need to touch.
- **Don't add speculative flexibility** or abstractions used once.
- **Match the surrounding style** — comment density, naming, idiom.
- **Security invariants are load-bearing.** Do not weaken `disableBypassPermissionsMode`, the
  `pre-bash-guard.sh` deny-list, the secret deny-list, or the constitution write-block. Changes
  here need an ADR and maintainer sign-off. See [`SECURITY.md`](SECURITY.md).

## Adding new components

| Component | Where | Required |
|---|---|---|
| Agent | `.claude/agents/<tier>/<name>.md` | frontmatter `name`, `description`, `model`, `permissionMode`; model matches §V |
| Skill | `.claude/skills/<name>/SKILL.md` | `name` + `description` frontmatter (one tight trigger sentence) |
| Hook | `.claude/hooks/<name>.sh` (executable) | register in `.claude/settings.json` |
| CI workflow | `.github/workflows/*.yml` | to gate merges, add the job to `.github/rulesets/main-protection.json` |

## Reporting bugs / requesting features

Use the issue templates under `.github/ISSUE_TEMPLATE/`. For anything security-sensitive, do
**not** open a public issue — follow [`SECURITY.md`](SECURITY.md).

## Code of Conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree your contributions are licensed under the repo's [MIT License](LICENSE).

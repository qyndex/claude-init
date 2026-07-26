# Security Policy

`claude-init` is a **security-focused** Claude Code harness: it ships hooks that block
destructive commands, scan for secrets, and gate autonomous agent behavior. Because teams adopt
it to *raise* their security baseline, we take issues in the harness itself seriously.

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report privately via one of:

- **GitHub Private Vulnerability Reporting** — the preferred channel. On this repo:
  **Security → Report a vulnerability** ([Advisories](https://github.com/qyndex/claude-init/security/advisories/new)).
- **Email** — `security@qyndex.com` with subject `claude-init security`.

Please include: the affected file(s)/version, a description, reproduction steps or a proof of
concept, and the impact you foresee. If you have a suggested fix, even better.

### What to expect

- **Acknowledgement** within 3 business days.
- **Assessment + severity** within 10 business days.
- A fix or mitigation plan communicated before any public disclosure. We follow coordinated
  disclosure and will credit you (unless you prefer to stay anonymous).

## What counts as a harness vulnerability

Because this repo is config + shell, the interesting classes are:

- **Guardrail bypass** — a way to defeat `pre-bash-guard.sh` (e.g. a command shape that reaches
  `rm -rf`, `curl | sh`, `--no-verify`, `git push --force origin main`, `eval`, `base64 | sh`
  past the segment-splitting), or to write to a deny-listed path (`.env*`, `*.pem`, `*.key`,
  `*credentials*`, the constitution).
- **Prompt-injection / privilege escalation** — content (a web page, an MCP response, a file)
  that flips the agent's role or coerces it past the permission model.
- **Secret exposure** — a code path that reads or logs `.env*`/keys, or a gitleaks gap that lets
  a secret slip into a Write/Edit.
- **Autonomous-merge / CI-gate defeat** — a way to arm auto-merge or bypass required status
  checks without the intended human/policy gate.

## What is NOT in scope

- The **BYO deploy pipeline** (`.github/workflows/canary-deploy.yml`) is a documented STUB — it
  runs no real deployment. Wiring it is the adopter's responsibility
  ([docs/DEPLOY-INTEGRATION.md](docs/DEPLOY-INTEGRATION.md)).
- Vulnerabilities in **third-party MCP servers** or plugins — report those upstream.
- Issues that require an already-compromised host or a malicious operator with shell access.

## Hardening notes for adopters

- The filesystem MCP **read** path is not gated by the settings deny-list — never store secrets
  in the repo tree. `gitleaks` (PreToolUse) + `.gitignore` are the mitigations.
- Keep `disableBypassPermissionsMode: "disable"` (the string, not boolean) in `settings.json`.
- Run `bash .claude/scripts/validate.sh` after any `.claude/` change — it enforces the security
  invariants above.

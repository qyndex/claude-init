#!/usr/bin/env bash
# Extract a brownfield repo's project conventions into AGENTS.md + a path-scoped rule. Round 14.
#
# Research (brownfield-onboarding.md): factory CLAUDE.md owns PROCESS; project-specific facts
# (stack, build/test/lint commands, domain conventions) belong in AGENTS.md — the cross-tool
# convention home. This writes a DRAFT for the human to refine; it never auto-converts ADRs
# (rationale gets lost) and never clobbers an existing AGENTS.md (only augments, idempotently).
#
# Usage:  extract-conventions.sh [--into <repo-dir>]

set -uo pipefail
INTO="$(pwd)"
[ "${1:-}" = "--into" ] && INTO="${2:-$(pwd)}"
# JUSTIFIED: the redirect hides the shell's own cd error so the `||` branch prints a friendlier message and exits; failure is explicitly handled, not swallowed
cd "$INTO" 2>/dev/null || { echo "cannot cd into $INTO"; exit 1; }

# ── Detect stack facts (quick heuristics; refine against atlas STRUCTURE.md) ──
pm=""; testcmd=""; lintcmd=""; lang=""
if   [ -f pnpm-lock.yaml ]; then pm="pnpm"
elif [ -f yarn.lock ];      then pm="yarn"
elif [ -f bun.lockb ] || [ -f bun.lock ]; then pm="bun"
elif [ -f package-lock.json ] || [ -f package.json ]; then pm="npm"; fi
if [ -f package.json ]; then
  lang="JavaScript/TypeScript"
  grep -q '"test"' package.json && testcmd="$pm test"
  grep -q '"lint"' package.json && lintcmd="$pm run lint"
fi
if [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; then
  lang="${lang:+$lang, }Python"; [ -z "$pm" ] && pm="pip/uv"
  [ -z "$testcmd" ] && testcmd="pytest"
  # JUSTIFIED: heuristic probe for a ruff config; -qs + the redirect mean a missing/ruff-less pyproject just leaves lintcmd unset for the (fill in) default below
  grep -rqs "ruff" pyproject.toml 2>/dev/null && lintcmd="ruff check ."
fi
[ -f go.mod ]     && { lang="${lang:+$lang, }Go";   testcmd="${testcmd:-go test ./...}"; lintcmd="${lintcmd:-go vet ./...}"; }
[ -f Cargo.toml ] && { lang="${lang:+$lang, }Rust"; testcmd="${testcmd:-cargo test}";   lintcmd="${lintcmd:-cargo clippy}"; }
[ -z "$lang" ]    && lang="(unknown — fill in)"
[ -z "$pm" ]      && pm="(fill in)"
[ -z "$testcmd" ] && testcmd="(fill in the project's test command)"
[ -z "$lintcmd" ] && lintcmd="(fill in)"

# JUSTIFIED: the redirect hides "no such directory" for whichever doc dirs are absent in this repo; the fallback yields an empty list when no ADRs exist (handled by the emit_section default)
adr_list="$(find docs adr decisions .claude/memory/decisions -type f \( -iname '*adr*' -o -iname '*decision*' \) 2>/dev/null | grep -v brownfield-backup | head -15 || true)"
MARKER="<!-- factory-adoption:conventions -->"

# emit_section: print the conventions block to stdout. printf with single-quoted formats
# keeps backticks LITERAL (no command substitution) — the bug a heredoc-in-$() introduced.
emit_section() {
  printf '%s\n' "$MARKER"
  printf '## Project conventions (extracted at adoption — REVIEW & REFINE)\n\n'
  printf '> Auto-drafted by extract-conventions.sh. The factory'"'"'s process rules live in\n'
  printf '> `.claude/CLAUDE.md`; THIS file holds project-specific facts. Edit freely.\n\n'
  printf -- '- **Language/stack:** %s\n' "$lang"
  printf -- '- **Package manager:** %s\n' "$pm"
  printf -- '- **Run tests:** `%s`\n' "$testcmd"
  printf -- '- **Lint:** `%s`\n' "$lintcmd"
  printf -- '- **Build/run:** (fill in the project'"'"'s build + start commands)\n'
  printf -- '- **Domain non-negotiables:** (fill in — invariants the factory must never violate)\n\n'
  printf '### Imported decisions (originals, not converted)\n'
  if [ -n "$adr_list" ]; then printf '%s\n' "$adr_list" | sed 's/^/- /'
  else printf -- '- (none found — link your ADRs/architecture docs here)\n'; fi
}

# AGENTS.md — augment (idempotent), never clobber an existing one.
if [ -f AGENTS.md ]; then
    # JUSTIFIED: marker probe guarded by the enclosing [ -f AGENTS.md ]; the redirect is defensive against a race-deleted file — absence then takes the augment branch
  if grep -qF "$MARKER" AGENTS.md 2>/dev/null; then
    echo "  AGENTS.md already has the conventions section — left as-is."
  else
    { printf '\n'; emit_section; } >> AGENTS.md
    echo "  augmented existing AGENTS.md with the extracted conventions section."
  fi
else
  { printf '# AGENTS.md\n\nProject context for AI agents. Factory process rules: see `.claude/CLAUDE.md`.\n\n'; emit_section; } > AGENTS.md
  echo "  wrote AGENTS.md (draft — review & refine)."
fi

# Path-scoped rule so conventions load when editing code.
mkdir -p .claude/rules
RULE=".claude/rules/project-conventions.md"
if [ ! -f "$RULE" ]; then
  {
    printf -- '---\npaths:\n  - "src/**"\n  - "lib/**"\n  - "app/**"\n---\n\n'
    printf '# Project conventions (brownfield — REFINE)\n\n'
    printf 'Extracted at adoption. See `AGENTS.md` for the full list. Key facts:\n'
    printf -- '- Stack: %s · package manager: %s\n' "$lang" "$pm"
    printf -- '- Tests: `%s` · Lint: `%s`\n\n' "$testcmd" "$lintcmd"
    printf 'Refine these globs + rules to match the real layout (see `.claude/memory/atlas/STRUCTURE.md`).\n'
  } > "$RULE"
  echo "  wrote $RULE (path-scoped; refine globs)."
else
  echo "  $RULE already exists — left as-is."
fi

#!/usr/bin/env bash
# PostToolUse hook for Write|Edit. Auto-formats the file based on extension.
# Best-effort; never blocks. Logs to .claude/hooks/.log/format.log.

set -uo pipefail

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')

if [ -z "$path" ] || [ ! -f "$path" ]; then
  exit 0
fi

# M-03: the memory-index and atlas-dirty case globs below are repo-RELATIVE
# (.claude/memory/...), but the Write/Edit tool often reports an ABSOLUTE
# file_path — so those cases never matched and the index touch never fired.
# Normalize an absolute path under the repo root to a repo-relative one.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
case "$path" in
  "$repo_root"/*) path="${path#"$repo_root"/}" ;;
esac

mkdir -p .claude/hooks/.log
log() { printf '%s %s\n' "$(date -Iseconds)" "$*" >> .claude/hooks/.log/format.log; }

ext="${path##*.}"

case "$ext" in
  ts|tsx|js|jsx|mjs|cjs|json|md|mdx|yaml|yml|css|scss|html)
    if command -v prettier >/dev/null 2>&1; then
      prettier --write --log-level error "$path" 2>>.claude/hooks/.log/format.log || log "prettier failed on $path"
    elif command -v npx >/dev/null 2>&1; then
      # JUSTIFIED: || true — this is a non-blocking format hook; a prettier failure (e.g. unparseable file) must never fail the user's Write
      npx --no-install prettier --write --log-level error "$path" 2>>.claude/hooks/.log/format.log || true
    fi
    ;;
  py)
    if command -v ruff >/dev/null 2>&1; then
      ruff format "$path" 2>>.claude/hooks/.log/format.log || log "ruff format failed on $path"
      # JUSTIFIED: || true — autofix is non-blocking; unfixable lint (e.g. syntax error) must not fail the user's Write
      ruff check --fix --quiet "$path" 2>>.claude/hooks/.log/format.log || true
    elif command -v black >/dev/null 2>&1; then
      # JUSTIFIED: || true — non-blocking format hook; a black failure on an unparseable file must not fail the user's Write
      black --quiet "$path" 2>>.claude/hooks/.log/format.log || true
    fi
    ;;
  rs)
    if command -v rustfmt >/dev/null 2>&1; then
      # JUSTIFIED: || true — non-blocking format hook; a rustfmt parse failure must not fail the user's Write
      rustfmt "$path" 2>>.claude/hooks/.log/format.log || true
    fi
    ;;
  go)
    if command -v gofmt >/dev/null 2>&1; then
      # JUSTIFIED: || true — non-blocking format hook; a gofmt parse failure must not fail the user's Write
      gofmt -w "$path" 2>>.claude/hooks/.log/format.log || true
    fi
    ;;
  sh|bash)
    if command -v shfmt >/dev/null 2>&1; then
      # JUSTIFIED: || true — non-blocking format hook; an shfmt parse failure must not fail the user's Write
      shfmt -w "$path" 2>>.claude/hooks/.log/format.log || true
    fi
    ;;
esac

# Round 5 C1: maintain typed memory index on writes to .claude/memory/**
# M-03: widened to 3 levels (…/*/*/*.md) so nested memory files (e.g.
# patterns/flask/foo.md) also refresh the index; the 2-level glob missed them.
case "$path" in
  .claude/memory/*.md|.claude/memory/*/*.md|.claude/memory/*/*/*.md)
    # JUSTIFIED: || true — index maintenance is a side effect; its failure must not fail the user's Write to memory
    bash .claude/scripts/memory-index.sh touch "$path" 2>>.claude/hooks/.log/format.log || true
    ;;
esac

# Round 8 C: mark atlas dirty when watched files change so session-start
# surfaces the staleness banner without waiting for the nightly refresh.
case "$path" in
  package.json|pnpm-lock.yaml|yarn.lock|tsconfig.json|next.config.*|pyproject.toml|requirements*.txt|Cargo.toml|Cargo.lock|go.mod|go.sum|prisma/schema.prisma|drizzle.config.*|turbo.json|nx.json|pnpm-workspace.yaml)
    mkdir -p .claude/memory/atlas
    touch .claude/memory/atlas/.dirty
    ;;
esac

# Round 9 F: regen skill registry when any SKILL.md changes.
case "$path" in
  .claude/skills/*/SKILL.md)
    # JUSTIFIED: || true — registry regen is a side effect; its failure must not fail the user's Write to a SKILL.md
    bash .claude/scripts/regen-skill-registry.sh >/dev/null 2>&1 || true
    ;;
esac

exit 0

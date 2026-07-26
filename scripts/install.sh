#!/usr/bin/env bash
# claude-init installer — drop the Claude Code golden harness into ANY repo, safely.
#
#   Run from the ROOT of the repo you want to harness:
#     curl -fsSL https://raw.githubusercontent.com/qyndex/claude-init/main/scripts/install.sh | bash
#
# What it does (and does NOT do):
#   1. Clones the factory to a TEMP dir (never overlays your repo root directly).
#   2. Runs reconcile-claude-dir.sh, which is adoption-safe: it BACKS UP any root
#      file it would overwrite (README.md, CLAUDE.md, …) to .brownfield-backup/<ts>/
#      and no-clobbers your own commands/hooks/workflows. It does NOT tar straight
#      into your repo root (which would silently clobber your README/CLAUDE.md).
#   3. Runs setup.sh (installs plugins, wires hooks, validates) unless you skip it.
#
# It is idempotent: re-running reconciles again (add UPGRADE=1 to pull newer
# factory-owned files, backed up first). Nothing is force-pushed; nothing leaves
# your machine. Everything happens inside YOUR working tree, on a branch you control.
#
# Environment overrides:
#   CLAUDE_INIT_REF=<branch|tag|sha>   factory ref to install (default: main)
#   CLAUDE_INIT_REPO=<url>             factory git URL (default: github.com/qyndex/claude-init)
#   INTO=<dir>                         target repo dir (default: current dir)
#   UPGRADE=1                          refresh factory-owned files (already-adopted repos)
#   SKIP_SETUP=1                       reconcile only, don't run setup.sh
#   SKIP_PLUGINS=1                     passed through to setup.sh
#   YES=1                              non-interactive (assume yes to prompts)
set -euo pipefail

REPO_URL="${CLAUDE_INIT_REPO:-https://github.com/qyndex/claude-init}"
REF="${CLAUDE_INIT_REF:-main}"
INTO="${INTO:-$(pwd)}"

say()  { printf '\033[1;36m→\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m %s\n' "$*"; }
die()  { printf '  \033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "claude-init installer"

# ── Preconditions ──────────────────────────────────────────────────────────
command -v git >/dev/null || die "git is required"
command -v jq  >/dev/null || warn "jq not found — REQUIRED before you use the harness (security hooks fail closed without it). Install: brew install jq / apt-get install jq"
[ -d "$INTO/.git" ] || die "not a git repo: $INTO — run this from the root of the repo you want to harness (or set INTO=<repo>)"

# Refuse to run against a dirty tree unless forced — reconcile writes into the tree
# and we want changes to land as a reviewable, revertable diff.
if [ -z "${YES:-}" ] && ! git -C "$INTO" diff --quiet 2>/dev/null; then
  warn "working tree at $INTO has uncommitted changes."
  warn "Reconcile writes into the tree; commit or stash first so the harness lands as a clean diff."
  warn "Override: YES=1 curl -fsSL … | bash"
  die  "halting on dirty tree"
fi

# ── Stage the factory OUTSIDE the target repo ──────────────────────────────
TMP="$(mktemp -d "${TMPDIR:-/tmp}/claude-init.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
say "Cloning factory ($REF) → temp"
git clone --quiet --depth 1 --branch "$REF" "$REPO_URL" "$TMP/factory" 2>/dev/null \
  || git clone --quiet --depth 1 "$REPO_URL" "$TMP/factory"   # ref may be a sha; fall back
[ -d "$TMP/factory/.claude" ] || die "clone did not contain .claude/ — is $REPO_URL correct?"
ok "factory staged at $TMP/factory"

RECON="$TMP/factory/.claude/scripts/reconcile-claude-dir.sh"
[ -f "$RECON" ] || die "reconcile-claude-dir.sh missing in factory — cannot install safely"

# ── Reconcile (adoption-safe: backs up + no-clobber) ───────────────────────
RECON_ARGS=(--from "$TMP/factory" --into "$INTO")
[ -n "${UPGRADE:-}" ] && RECON_ARGS+=(--upgrade)
say "Reconciling factory → $INTO ${UPGRADE:+(upgrade mode)}"
bash "$RECON" "${RECON_ARGS[@]}"
ok "reconcile complete — any overwritten root file is backed up under .brownfield-backup/"

# ── Setup ──────────────────────────────────────────────────────────────────
if [ -n "${SKIP_SETUP:-}" ]; then
  warn "SKIP_SETUP set — not running setup.sh. Run it yourself: bash .claude/scripts/setup.sh"
else
  say "Running setup.sh"
  ( cd "$INTO" && SKIP_PLUGINS="${SKIP_PLUGINS:-}" bash .claude/scripts/setup.sh ) \
    || warn "setup.sh reported issues — review its output above; the harness files are already in place"
fi

cat <<EOF

$(ok "claude-init installed into $INTO")

Next:
  1. Review the diff:      git -C "$INTO" status && git -C "$INTO" diff
  2. Commit the harness:   git -C "$INTO" add -A && git -C "$INTO" commit -m "chore: adopt claude-init harness"
  3. Open Claude Code:     claude
  4. Brand-new product?    /kickoff        (or read docs/STARTING-PROMPT.md)
     Existing/legacy repo? /adopt start    (six human-gated phases — docs/ADOPTION.md)

Manual steps that still need YOU (see README "Manual setup" + docs/OPERATOR-MANUAL.md):
  • GitHub: apply the branch ruleset (.github/rulesets/main-protection.json)
  • GitHub: enable Actions + set the ANTHROPIC_API_KEY secret for CI review
  • Optional: wire deploy per docs/DEPLOY-INTEGRATION.md (the shipped pipeline is a STUB)
EOF

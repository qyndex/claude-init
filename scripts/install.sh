#!/usr/bin/env bash
# claude-init installer — drop the Claude Code golden harness into ANY repo, safely.
#
#   Run from the ROOT of the repo you want to harness:
#     curl -fsSL https://raw.githubusercontent.com/qyndex/claude-init/main/scripts/install.sh | bash
#
# What it does (and does NOT do):
#   1. Clones the factory to a TEMP dir (never overlays your repo root directly).
#   2. Reconciles immutable source files using version/hash/mode ownership.
#      Foreign/customized collisions block before changes; private journals allow
#      exact rollback/recovery. Active source backlog, memory and pilot workflows
#      are excluded. README and adopter-owned ledger/memory remain untouched.
#   3. Checks required local tools unless skipped; no target setup is executed.
#
# Re-running reconciles again (add UPGRADE=1 to pull newer
# factory-owned files, backed up first). Nothing is force-pushed; nothing leaves
# your machine. Everything happens inside YOUR working tree, on a branch you control.
#
# Environment overrides:
#   CLAUDE_INIT_REF=<branch|tag|sha>   factory ref to install (default: main)
#   CLAUDE_INIT_REPO=<url>             factory git URL (default: github.com/qyndex/claude-init)
#   INTO=<dir>                         target repo dir (default: current dir)
#   UPGRADE=1                          refresh factory-owned files (already-adopted repos)
#   SKIP_SETUP=1                       skip required local tool check
#   CLAUDE_INIT_STATE_DIR=<absolute>    private 0700 journal root outside target
#   YES=1                              explicitly allow a dirty target tree
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
for option in YES UPGRADE SKIP_SETUP; do
  value="${!option:-0}"
  case "$value" in 0|1) ;; *) die "$option must be 0 or 1" ;; esac
done
[ -d "$INTO" ] || die "target directory unavailable: $INTO"
INTO="$(cd "$INTO" && pwd -P)"
TARGET_ROOT="$(git -C "$INTO" rev-parse --show-toplevel)" || die "not a Git repository: $INTO"
TARGET_ROOT="$(cd "$TARGET_ROOT" && pwd -P)"
[ "$INTO" = "$TARGET_ROOT" ] || die "INTO must be the repository root"
TARGET_STATUS="$(git -C "$INTO" status --porcelain)" || die "cannot inspect target state"
if [ -n "$TARGET_STATUS" ]; then
  [ "${YES:-0}" = 1 ] || die "target has staged, unstaged or untracked changes; commit/stash them or explicitly set YES=1"
  warn "YES=1 authorizes installation into a dirty target; review the resulting diff carefully"
fi
case "$REF" in ''|-*|*:*) die "unsupported source ref" ;; esac
git check-ref-format --allow-onelevel "$REF" >/dev/null || die "invalid source branch, tag or SHA"

# ── Stage the factory OUTSIDE the target repo ──────────────────────────────
TMP="$(mktemp -d "${TMPDIR:-/tmp}/claude-init.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
say "Cloning factory ($REF) → temp"
git init --quiet "$TMP/factory"
git -C "$TMP/factory" remote add origin "$REPO_URL"
git -C "$TMP/factory" fetch --quiet --depth 1 origin "$REF" || die "requested source ref could not be fetched; no fallback was installed"
SOURCE_SHA="$(git -C "$TMP/factory" rev-parse --verify 'FETCH_HEAD^{commit}')" || die "source ref is not a commit"
git -C "$TMP/factory" checkout --quiet --detach "$SOURCE_SHA"
ok "factory source commit $SOURCE_SHA"
[ -d "$TMP/factory/.claude" ] || die "clone did not contain .claude/ — is $REPO_URL correct?"
ok "factory staged at $TMP/factory"

RECON="$TMP/factory/.claude/scripts/reconcile-claude-dir.sh"
[ -f "$RECON" ] || die "reconcile-claude-dir.sh missing in factory — cannot install safely"

# ── Reconcile (adoption-safe: backs up + no-clobber) ───────────────────────
RECON_ARGS=(--from "$TMP/factory" --into "$INTO")
[ "${UPGRADE:-0}" = 1 ] && RECON_ARGS+=(--upgrade)
[ "${SKIP_SETUP:-0}" = 0 ] && RECON_ARGS+=(--check-tools)
say "Reconciling factory → $INTO ${UPGRADE:+(upgrade mode)}"
bash "$RECON" "${RECON_ARGS[@]}"
ok "transactional ownership reconciliation complete — activation remains disabled"

cat <<EOF

$(ok "claude-init installed into $INTO")

Next:
  1. Review the diff:      git -C "$INTO" status && git -C "$INTO" diff
  2. Commit reviewed files explicitly; keep private journals and credentials outside the repo.
  3. Open Claude Code:     claude
  4. Brand-new product?    /kickoff        (or read docs/STARTING-PROMPT.md)
     Existing/legacy repo? /adopt start    (six human-gated phases — docs/ADOPTION.md)

Read docs/FACTORY-ADOPTION.md before configuring live authority. Remaining per-repository steps:
  • Configure approved repository/spec/runtime policy and protected independent proof producers.
  • Apply reviewed per-repository workflows and protection explicitly; this installer does not copy pilot workflows.
  • Configure that repository's private reporting/feedback state and deployment adapter before activation.
EOF

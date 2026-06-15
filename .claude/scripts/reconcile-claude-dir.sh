#!/usr/bin/env bash
# Reconcile the factory .claude/ into a brownfield repo that already has its own. Round 14.
#
# `cp -nr .claude` is FORBIDDEN for a populated .claude/ — no-clobber leaves a frankenstein
# half-merge. This reconciler uses three buckets and NEVER silent-merges:
#   • factory-authoritative (process/orchestration) → overwrite, but BACK UP first
#   • never-overwrite (their knowledge + secrets + local state) → preserve verbatim
#   • merge-by-extraction (their conventions) → extracted to AGENTS.md by extract-conventions.sh
# Every direct conflict becomes an [OQ] in ADOPTION-REPORT.md routed through /clarify.
# Fully reversible: originals are copied to .brownfield-backup/<ts>/ (repo root, gitignored)
# with a MANIFEST.txt of every path adoption created; undo via --revert <ts>.
#
# Runs from anywhere (does NOT use the script-relative ROOT — it operates on --into):
#   reconcile-claude-dir.sh --from <factory-clone-dir> [--into <repo-dir>] [--dry-run]
#   reconcile-claude-dir.sh --revert <ts> [--into <repo-dir>]

set -uo pipefail
FROM=""; INTO="$(pwd)"; DRY=0; REVERT=""; UPGRADE=0
while [ $# -gt 0 ]; do case "$1" in
  --from) FROM="${2:-}"; shift 2 ;;
  --into) INTO="${2:-}"; shift 2 ;;
  --revert) REVERT="${2:-}"; shift 2 ;;
  --dry-run) DRY=1; shift ;;
  # --upgrade: re-reconcile an ALREADY-adopted repo onto a newer factory. In this
  # mode a same-named file the factory ALSO ships is treated as factory-owned and
  # UPDATED to the new version (backed up first, collision reported), instead of the
  # default adoption behavior that no-clobbers it. Files the factory does NOT ship
  # (the project's own commands/hooks/workflows) are still preserved either way.
  --upgrade) UPGRADE=1; shift ;;
  *) shift ;;
esac; done

[ -z "$FROM" ] && [ -z "$REVERT" ] && { echo "usage: reconcile-claude-dir.sh --from <factory-clone-dir> [--into <repo>] [--dry-run] | --revert <ts>"; exit 1; }
[ -n "$FROM" ] && { [ -d "$FROM/.claude" ] || { echo "no .claude/ found in factory dir: $FROM"; exit 1; }; }
# JUSTIFIED: a non-existent target makes cd fail; the muted system message is replaced by the clearer fallback error and a hard exit, so this never proceeds in the wrong directory
cd "$INTO" 2>/dev/null || { echo "cannot cd into target: $INTO"; exit 1; }

# ── Revert mode (e2e-audit brownfield-4): restore the pre-adoption .claude/ and
# delete the files adoption CREATED (per MANIFEST.txt) — never the repo's own. ──
if [ -n "$REVERT" ]; then
  BK=".brownfield-backup/$REVERT"
  if [ ! -d "$BK" ]; then
    echo "no backup at $BK. Available timestamps:"
    # JUSTIFIED: ls probe — an empty/absent backup dir falls through to the (none) line
    ls -1 .brownfield-backup 2>/dev/null || echo "  (none)"
    exit 1
  fi
  if [ -f "$BK/MANIFEST.txt" ]; then
    while IFS=$'\t' read -r verb path; do
      [ "$verb" = "created" ] || continue
      [ -n "$path" ] && [ -e "$path" ] && rm -f -- "$path"
    done < "$BK/MANIFEST.txt"
    echo "  deleted adoption-created files listed in $BK/MANIFEST.txt"
  else
    echo "  (no MANIFEST.txt in backup — restoring .claude/ only; scaffold files created by adoption stay in place)"
  fi
  rm -rf .claude && mkdir -p .claude && cp -R "$BK/." .claude/
  rm -f .claude/MANIFEST.txt
  echo "✓ reverted: .claude/ restored from $BK; adoption-created files removed per MANIFEST."
  exit 0
fi

ts="$(date +%Y%m%d-%H%M%S)"
# Backup lives OUTSIDE .claude/ — a backup dir nested inside the very tree we
# `cp -R` would recurse into itself (the macOS cp races the mkdir, producing
# .brownfield-backup/<ts>/.brownfield-backup/<ts>/… ad nauseam). Sibling dir is safe.
BK=".brownfield-backup/$ts"
REPORT="ADOPTION-REPORT.md"
# Factory owns PROCESS. These dirs are overwritten (after backup) — the harness
# is the sole author of agents/skills/scripts/routines/statuslines/output-styles,
# so a same-named file is a stale factory copy, not the project's own work.
FACTORY_DIRS="agents skills scripts routines statuslines output-styles"
# commands + hooks are MIXED: the factory ships some, but a brownfield repo
# legitimately authors its own (e.g. /deploy, pre-push-security.sh). Copy these
# NO-CLOBBER so the project's same-named file is PRESERVED, and report the
# collision as an [OQ] for human resolution — never silently overwrite custom
# automation (the previous cp -R clobbered them).
MERGE_DIRS="commands hooks"
FACTORY_FILES="CLAUDE.md settings.json"

run() { [ "$DRY" = 1 ] && echo "[dry-run] $*" || eval "$*"; }

# ── Greenfield fast-path: no existing .claude/ → plain copy ───────────────
if [ ! -d .claude ]; then
  echo "→ No existing .claude/ in $INTO — greenfield copy (no reconciliation needed)."
  run "cp -r '$FROM/.claude' .claude"
  # .github still copies NO-CLOBBER — even a repo without .claude/ can have its own CI
  # (brownfield-3); differing same-name files stay the repo's and are flagged.
  if [ -d "$FROM/.github" ]; then
    run "mkdir -p .github"
    while IFS= read -r f; do
      f="${f#./}"
      if [ -e ".github/$f" ] && ! cmp -s "$FROM/.github/$f" ".github/$f"; then
        echo "  [OQ] .github/$f exists and differs — repo's version kept (factory gate NOT applied)"
      fi
    done < <(cd "$FROM/.github" && find . -type f 2>/dev/null)
    run "cp -Rn '$FROM/.github/.' '.github/' 2>/dev/null || true"
  fi
  echo "✓ copied factory .claude/ + .github (no-clobber). Run: bash .claude/scripts/setup.sh"
  exit 0
fi

echo "→ Existing .claude/ found in $INTO — reconciling (3 buckets, never silent-merge)."
run "mkdir -p '$BK'"
# JUSTIFIED: recursive backup of regular files into the just-created backup dir; the muted stream + fallback swallow only per-entry warnings (sockets, perm-odd state files) so a cosmetic copy gripe doesn't abort adoption — regular files are still backed up, preserving reversibility
run "cp -R .claude/. '$BK/' 2>/dev/null || true"
echo "  backed up your original .claude/ → $BK"

# MANIFEST.txt (brownfield-4): every path adoption creates/overwrites, consumed by --revert.
MANIFEST="$BK/MANIFEST.txt"
manifest() { [ "$DRY" = 1 ] || printf '%s\t%s\n' "$1" "$2" >> "$MANIFEST"; }

# Backup hygiene (brownfield-4): the backup holds settings.local.json + .claude/state/ —
# gitignore it NOW, before the first `git add -A` WIP checkpoint can commit it to history.
if ! grep -qxF '.brownfield-backup/' .gitignore 2>/dev/null; then
  run "printf '\n# brownfield adoption backup (holds settings.local.json — never commit)\n.brownfield-backup/\n' >> .gitignore"
  echo "  added .brownfield-backup/ to .gitignore"
fi

# Preserve their CLAUDE.md if it is NOT already the factory's (signature check).
conflict_claude=""
# JUSTIFIED: the redirect drops grep stderr — only the match status is wanted, and a non-match (no factory signature) correctly triggers preservation of the user's existing CLAUDE.md
if [ -f .claude/CLAUDE.md ] && ! grep -q "Karpathy's Four Principles" .claude/CLAUDE.md 2>/dev/null; then
  run "cp .claude/CLAUDE.md .claude/CLAUDE.md.brownfield-orig"
  conflict_claude=1
  echo "  preserved your CLAUDE.md → .claude/CLAUDE.md.brownfield-orig"
fi
# Preserve their settings.json (custom permissions) before the factory's overwrites it.
conflict_settings=""
# JUSTIFIED: the redirect drops grep stderr — only the match status is wanted, and a non-match (no factory marker) correctly triggers preservation of the user's existing settings.json
if [ -f .claude/settings.json ] && ! grep -q "disableBypassPermissionsMode" .claude/settings.json 2>/dev/null; then
  run "cp .claude/settings.json .claude/settings.json.brownfield-orig"
  conflict_settings=1
fi

# Copy factory-authoritative dirs (factory files win; their extra files remain).
for d in $FACTORY_DIRS; do
  [ -d "$FROM/.claude/$d" ] || continue
  run "mkdir -p '.claude/$d'"
  run "cp -R '$FROM/.claude/$d/.' '.claude/$d/'"
  manifest overwritten ".claude/$d/"
done
# Mixed dirs (commands/hooks): NO-CLOBBER — preserve the project's own files,
# add the factory's, and record any same-name collision as an [OQ].
merge_collisions=""; merge_updated=""
for d in $MERGE_DIRS; do
  [ -d "$FROM/.claude/$d" ] || continue
  run "mkdir -p '.claude/$d'"
  # Detect collisions BEFORE copying (cp -Rn would silently keep theirs). Recurse with
  # find — MERGE_DIRS have subdirs (commands/swarm/*), so a top-level glob misses them.
  if [ -d ".claude/$d" ]; then
    while IFS= read -r rel; do
      rel="${rel#./}"
      src="$FROM/.claude/$d/$rel"
      [ -e ".claude/$d/$rel" ] || continue
      # Only a DIFFERING same-name file is interesting (identical = nothing to do).
      cmp -s "$src" ".claude/$d/$rel" && continue
      if [ "$UPGRADE" = 1 ]; then
        # Factory ships this name → factory-owned → UPDATE it (already backed up to $BK).
        run "cp '$src' '.claude/$d/$rel'"
        merge_updated="$merge_updated .claude/$d/$rel"
      else
        merge_collisions="$merge_collisions .claude/$d/$rel"
      fi
    done < <(cd "$FROM/.claude/$d" && find . -type f 2>/dev/null)
  fi
  # NO-CLOBBER pass: adds the factory's NEW files; in upgrade mode the differing
  # factory-owned files were already overwritten above, and the project's OWN files
  # (names the factory doesn't ship) are untouched by both passes.
  # JUSTIFIED: cp -n exits non-zero when it skips a colliding file (the no-clobber WIN, not an error) — collisions are captured above and reported; swallow so reconcile doesn't abort on the very behavior we want
  run "cp -Rn '$FROM/.claude/$d/.' '.claude/$d/' 2>/dev/null || true"
  manifest added ".claude/$d/ (no-clobber$([ "$UPGRADE" = 1 ] && echo '; factory files updated'))"
done
if [ "$UPGRADE" = 1 ] && [ -n "${merge_updated# }" ]; then
  # shellcheck disable=SC2086
  echo "  .claude commands/hooks: $(set -- $merge_updated; echo $#) factory file(s) updated (backed up to $BK)"
fi
for f in $FACTORY_FILES; do
  [ -f "$FROM/.claude/$f" ] && { run "cp '$FROM/.claude/$f' '.claude/$f'"; manifest overwritten ".claude/$f"; }
done

# .claude/VERSION is factory-authoritative but lives outside FACTORY_DIRS — copy it
# explicitly (overwrite: it stamps which harness release governs this repo).
[ -f "$FROM/.claude/VERSION" ] && { run "cp '$FROM/.claude/VERSION' '.claude/VERSION'"; manifest overwritten ".claude/VERSION"; }

# Complete the top-level scaffold the factory needs (.mcp.json + spec/plan/task/memory
# templates, OKRs/roadmap/slo, swarm templates). NO-CLOBBER: never overwrite a file the
# brownfield repo already owns — these fill the gaps validate.sh checks for, nothing more.
# Without this, a reconcile-only install leaves ~20 scaffold files missing (validate.sh
# [scaffold]/[memory]/[swarm]/[mcp] failures).
SCAFFOLD_FILES=".mcp.json OKRs.md roadmap.md slo.yml"
# Repo-root config files the factory's CI gates require (commitlint.yml needs
# commitlint.config.mjs, codecov.yml backs the coverage gate). The OLD reconcile
# never copied these, so an adopted repo got the WORKFLOW but not its config →
# commitlint failed [empty-rules]. Copy no-clobber on adopt; refresh on --upgrade.
# NOT included: .gitleaks.toml + release-please-* — those activate secret-scan /
# release-automation policy the adopting project must opt into deliberately.
ROOT_CONFIG_FILES="commitlint.config.mjs codecov.yml"
SCAFFOLD_DIRS="specs plans tasks docs initiatives .swarms"
for f in $SCAFFOLD_FILES; do
  [ -f "$FROM/$f" ] && [ ! -e "$f" ] && { run "cp '$FROM/$f' '$f'"; manifest created "$f"; }
done
for f in $ROOT_CONFIG_FILES; do
  [ -f "$FROM/$f" ] || continue
  if [ ! -e "$f" ]; then
    run "cp '$FROM/$f' '$f'"; manifest created "$f"
  elif [ "$UPGRADE" = 1 ] && ! cmp -s "$FROM/$f" "$f"; then
    # factory-owned config → refresh on upgrade (backed up to $BK)
    # JUSTIFIED: cosmetic per-entry copy gripe must not abort the upgrade; the config is still backed up before the overwrite below, preserving reversibility
    run "mkdir -p '$BK'"; run "cp '$f' '$BK/$f' 2>/dev/null || true"
    run "cp '$FROM/$f' '$f'"; manifest overwritten "$f"
  fi
done
# Factory dev artifacts that must NOT leak into an adopted repo's live set: the
# harness ships specs/plans 001-003 + memory ADRs + initiative STATE files for its
# OWN development. setup.sh template-clean archives them to docs/factory-history/,
# but a no-clobber SCAFFOLD copy would RE-ADD them (they're absent post-clean, so
# cp -Rn happily re-creates them) → duplicate-id + stale-spec validate failures in
# the adopted repo. Skip them in the copy: an adopted repo authors its own 001+.
factory_skip() {  # $1 = relative path under the scaffold dir $2
  case "$2/$1" in
    specs/active/00[1-3]-*.md|plans/active/00[1-3]-*.md|initiatives/active/*.STATE.md) return 0 ;;
  esac
  return 1
}
for d in $SCAFFOLD_DIRS; do
  [ -d "$FROM/$d" ] || continue
  run "mkdir -p '$d'"
  while IFS= read -r f; do
    f="${f#./}"
    factory_skip "$f" "$d" && continue
    # Copy each non-skipped factory file individually, no-clobber, recording creates.
    if [ ! -e "$d/$f" ]; then
      run "mkdir -p '$d/$(dirname "$f")'"
      run "cp '$FROM/$d/$f' '$d/$f'"
      manifest created "$d/$f"
    fi
  done < <(cd "$FROM/$d" && find . -type f 2>/dev/null)
done
# Upgrade mode: refresh factory-OWNED docs (the harness ships docs/AUTOPILOT.md,
# ARCHITECTURE.md, PLAYBOOK.md, …). The no-clobber scaffold pass above leaves them
# on their stale version; a docs file the factory ships is factory-owned, so update
# it. Project-authored docs (names the factory doesn't ship) are untouched. specs/
# plans/tasks/initiatives are NEVER refreshed — those are the project's own content.
docs_updated=0
if [ "$UPGRADE" = 1 ] && [ -d "$FROM/docs" ]; then
  while IFS= read -r f; do
    f="${f#./}"
    if [ -e "docs/$f" ] && ! cmp -s "$FROM/docs/$f" "docs/$f"; then
      run "mkdir -p '$BK/docs/$(dirname "$f")'"
      # JUSTIFIED: cosmetic per-entry copy gripe (odd perms) must not abort the upgrade; the doc is still backed up before the overwrite below, preserving reversibility
      run "cp 'docs/$f' '$BK/docs/$f' 2>/dev/null || true"
      run "cp '$FROM/docs/$f' 'docs/$f'"
      docs_updated=$((docs_updated + 1))
    fi
  done < <(cd "$FROM/docs" && find . -type f 2>/dev/null)
  [ "$docs_updated" -gt 0 ] && echo "  docs: $docs_updated factory doc(s) updated (backed up to $BK/docs/)"
fi
# .gitignore: append factory entries the repo lacks rather than overwriting (setup.sh also
# does this idempotently, but doing it here keeps a reconcile-only run consistent).
if [ -f "$FROM/.gitignore" ] && [ ! -e .gitignore ]; then
  run "cp '$FROM/.gitignore' .gitignore"
  manifest created ".gitignore"
fi

# ── .github CI gate layer (e2e-audit brownfield-3) ────────────────────────
# Without this, a brownfield repo ends adoption with ZERO factory merge gates
# (no evidence-gate, no commitlint, no no-issue-authority) while the constitution
# promises them. Factory files copy NO-CLOBBER; same-name files that differ stay
# the repo's and surface as [OQ]s — never silent-merged.
gh_collisions=""; gh_created=0; preexisting_ci=""
if [ -d "$FROM/.github" ]; then
  # JUSTIFIED: ls probe — no pre-existing workflows is the common case and yields an empty inventory
  preexisting_ci="$(ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | tr '\n' ' ' || true)"
  run "mkdir -p .github"
  # Upgrade mode overwrites factory-owned .github files — back the existing tree up first
  # (the default .claude/ backup at $BK does not cover .github/). Reversible via $BK.
  if [ "$UPGRADE" = 1 ] && [ -d .github ]; then
    run "mkdir -p '$BK/.github'"
    # JUSTIFIED: cosmetic per-entry copy gripes (odd perms) must not abort upgrade; regular files are still backed up, preserving reversibility
    run "cp -R .github/. '$BK/.github/' 2>/dev/null || true"
  fi
  gh_updated=0
  while IFS= read -r f; do
    f="${f#./}"
    if [ -e ".github/$f" ]; then
      if ! cmp -s "$FROM/.github/$f" ".github/$f"; then
        if [ "$UPGRADE" = 1 ]; then
          # Factory ships this workflow/action → factory-owned → UPDATE (backed up to $BK below).
          run "cp '$FROM/.github/$f' '.github/$f'"
          gh_updated=$((gh_updated + 1))
        else
          gh_collisions="${gh_collisions}  - \`.github/$f\` — exists in both and DIFFERS; the repo's version was kept.
"
        fi
      fi
    else
      manifest created ".github/$f"
      gh_created=$((gh_created + 1))
    fi
  done < <(cd "$FROM/.github" && find . -type f 2>/dev/null)
  run "cp -Rn '$FROM/.github/.' '.github/' 2>/dev/null || true"
  echo "  .github: $gh_created factory file(s) added (no-clobber)$([ "$UPGRADE" = 1 ] && [ "$gh_updated" -gt 0 ] && echo "; $gh_updated factory file(s) updated")$([ -n "$gh_collisions" ] && echo '; collisions → [OQ]')"
fi
# Git-hook managers that can collide with the factory commit protocol (husky/lefthook/
# pre-commit rejecting `WIP:` subjects + pre-bash-guard blocking --no-verify = deadlock).
hook_managers=""
for hm in .husky lefthook.yml .lefthook.yml lefthook.yaml .pre-commit-config.yaml; do
  [ -e "$hm" ] && hook_managers="${hook_managers}${hm} "
done
# JUSTIFIED: find probe — a sample-only .git/hooks is the default and contributes an empty inventory
git_hooks="$(find .git/hooks -type f ! -name '*.sample' 2>/dev/null | tr '\n' ' ' || true)"

# Seed factory templates under .claude/ that live OUTSIDE the FACTORY_DIRS list but that
# validate.sh requires (memory templates + report template). NO-CLOBBER so an existing
# brownfield .claude/memory/ (the user's knowledge — preserved above) is never overwritten;
# we only fill the missing template files the gate checks for.
CLAUDE_SEED_DIRS="memory templates"
for d in $CLAUDE_SEED_DIRS; do
  [ -d "$FROM/.claude/$d" ] || continue
  run "mkdir -p '.claude/$d'"
  run "cp -Rn '$FROM/.claude/$d/.' '.claude/$d/' 2>/dev/null || true"
done

# Extract their conventions into AGENTS.md + a project-conventions rule (human refines).
if [ -f "$FROM/.claude/scripts/extract-conventions.sh" ]; then
  run "bash '$FROM/.claude/scripts/extract-conventions.sh' --into '$INTO'"
fi

# Append the collision map + [OQ]s to the adoption report.
if [ "$DRY" = 0 ]; then
  {
    echo
    echo "## Existing \`.claude/\` collision map (reconcile $ts)"
    echo "- Backup of your original \`.claude/\`: \`$BK\` (gitignored). MANIFEST.txt lists every created/overwritten path; undo with \`bash .claude/scripts/reconcile-claude-dir.sh --revert $ts\`."
    echo "- **Preserved, never overwritten:** \`settings.local.json\`, \`.claude/state/\`, \`.claude/memory/\`, existing \`.claude/rules/*\`, \`conventions.yml\`, your secrets, **and your own \`.claude/commands/*\` + \`.claude/hooks/*\` (no-clobber — factory adds alongside, never replaces)**."
    echo "- **Factory now governs (overwritten, backed up):** agents, skills, scripts, routines, statuslines, output-styles, CLAUDE.md, settings.json."
    [ -n "${merge_collisions# }" ] && {
      echo "- [OQ] **Command/hook name collision** — these factory files were NOT installed because your repo already has a file of the same name (yours kept):${merge_collisions}. Decide per file: keep yours, adopt the factory's (copy from \`$BK\`), or rename. The factory version sits in the backup."
    }
    [ -n "$conflict_claude" ] && {
      echo "- Your original CLAUDE.md → \`.claude/CLAUDE.md.brownfield-orig\`. The factory CLAUDE.md (8-phase workflow, commit protocol, gates) governs process; **migrate your project conventions into \`AGENTS.md\`**."
      echo "- [OQ] Reconcile CLAUDE.md: review \`.brownfield-orig\` vs factory; decide per axis (factory wins on process; your conventions → AGENTS.md). Resolve via /clarify."
    }
    [ -n "$conflict_settings" ] && echo "- [OQ] Your settings.json → \`.brownfield-orig\`. Move any custom \`allow\`/\`deny\` permissions into \`.claude/settings.local.json\` (never committed)."
    echo
    echo "### .github CI gate layer (reconcile $ts)"
    echo "- Factory workflows/rulesets copied no-clobber: $gh_created new file(s); your existing files untouched."
    [ -n "$gh_collisions" ] && {
      echo "- [OQ] **.github collisions** — decide per file (factory gates evidence-gate/commitlint/no-issue-authority are required checks in \`.github/rulesets/main-protection.json\`; a kept repo version means that gate is NOT the factory's). Resolve via /clarify:"
      printf '%s' "$gh_collisions"
    }
    [ -n "$preexisting_ci" ] && echo "- [OQ] Pre-existing CI workflows detected (${preexisting_ci}) — verify they don't double-run against the factory gates (docs/CI-COST.md) and that their secrets still exist."
    [ -n "${hook_managers}${git_hooks}" ] && {
      echo "- [OQ] **Git-hook coexistence decision (resolve in Phase 2):** detected ${hook_managers}${git_hooks}."
      echo "  The factory's WIP checkpoints (\`WIP: <6-word>\` subjects) and commit trailers must pass YOUR hooks — \`pre-bash-guard.sh\` blocks \`--no-verify\`, so a rejecting commit-msg hook DEADLOCKS auto-mode loops."
      echo "  Either relax your commitlint/hook to accept \`WIP:\` subjects, or disable WIP checkpoints (.claude/skills/wip-checkpoint/SKILL.md)."
    }
  } >> "$REPORT"
fi

echo "✓ reconciled. Review the collision map in $REPORT, resolve [OQ]s via /clarify, then: bash .claude/scripts/setup.sh"

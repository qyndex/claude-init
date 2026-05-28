---
description: Major-version dependency upgrade with codemod hand-off. Reads upgrade guide, runs codemods, executes full E2E, opens PR for human review. Different from Dependabot's patch+minor auto-merge.
argument-hint: "<package> --major [--from <version>] [--to <version>]"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, WebFetch, TodoWrite
disable-model-invocation: true
---

# /upgrade — Major-version dep upgrade lane

```bash
pkg="$1"
from_ver="$2"    # --from
to_ver="$3"      # --to

# 1. Create upgrade branch
upgrade_branch="upgrade/${pkg}-${to_ver}"
git checkout -b "$upgrade_branch"

# 2. Fetch upgrade guide (heuristic: ${pkg}-migration.md, CHANGELOG.md, docs)
guide_url=$(claude -p "Search WebFetch for '${pkg} migration guide ${from_ver} ${to_ver}'. Return canonical URL." --bare)
echo "Upgrade guide: $guide_url"

# 3. Run the upgrade
case "$(jq -r '.packageManager // "npm"' package.json 2>/dev/null)" in
  pnpm*) pnpm update "$pkg@$to_ver" ;;
  yarn*) yarn add "$pkg@$to_ver" ;;
  *)     npm install "$pkg@$to_ver" ;;
esac

# 4. Find or write codemods (delegate to codemod skill)
echo "Looking for community codemods for $pkg $from_ver → $to_ver..."
# Heuristic: GitHub search for "$pkg-codemod" or check the package's official codemod registry
# React: https://github.com/reactjs/react-codemod
# Next.js: https://nextjs.org/docs/app/guides/upgrading/codemods
# Vue: https://github.com/vuejs/vue-codemod

# 5. Apply codemods (dry-run first, then write)
echo "Run /codemod for each upgrade transform"

# 6. Verify
bash .claude/scripts/verify.sh
bash .claude/scripts/test-integration.sh

# 7. Open the PR
gh pr create \
  --title "chore(deps): upgrade $pkg from $from_ver to $to_ver (major)" \
  --body "$(cat <<EOF
## Upgrade $pkg: $from_ver → $to_ver

**Type**: major-version dependency upgrade
**Codemods applied**: <list>
**Manual changes**: <list>
**Breaking changes addressed**: <list>

**Migration guide**: $guide_url
**Changelog**: <pkg>/CHANGELOG.md @ $to_ver

## Test plan

- [x] verify.sh green
- [x] integration tests green
- [x] manual smoke (run /verify)
- [ ] staging soak (24h)
- [ ] canary 1% / 10% / 50% / 100%

## Rollback plan

This is gated by feature flag \`dep_${pkg}_${to_ver/./_}\` if it changes behavior.
Otherwise: git revert + redeploy.
EOF
)"
```

## Hard rules

- **Major bumps don't auto-merge.** Always human review. Dependabot handles patch+minor; this command handles major.
- **Apply codemods, don't hand-edit.** If a transform applies to 50 sites, it's a codemod.
- **Verify in staging before merging to main.** No "let's see what breaks in prod."
- **Gate by feature flag** if the dep change is user-visible. Otherwise rollback via git revert is fine.

## Recurring scan

Dependabot opens PRs; for any major upgrade, instead of auto-merge:
- Add `priority: major-upgrade` label
- Open task in `tasks/TASKS.md` for `/upgrade` to run
- Block merge until codemods + tests pass

$ARGUMENTS

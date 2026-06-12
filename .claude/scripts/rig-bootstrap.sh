#!/usr/bin/env bash
# rig-bootstrap.sh — install the Playwright evidence rig into a web project
# (e2e-audit e2e-rig-4c). Idempotent; safe to re-run.
#
#   1. Copies .claude/templates/evidence/playwright.config.ts to the repo root
#      as playwright.evidence.config.ts (STANDALONE — never collides with a
#      brownfield project's own playwright.config.ts; all rig invocations use
#      `npx playwright test --config playwright.evidence.config.ts`).
#   2. Copies _evidence.ts to e2e/_evidence.ts (per-AC screenshot helper).
#   3. Installs @playwright/test (dev) + the chromium browser.
#
# Invoked by setup.sh on web-stack detection, by the verifier pre-first-run,
# or manually. Exit 0 on success/already-installed, 1 on a hard failure.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

[ -f package.json ] || { echo "rig-bootstrap: no package.json — browser rig is for web stacks; CLIs/APIs prove ACs via the stack runner (see collect-evidence.sh)"; exit 0; }

TPL=".claude/templates/evidence"
[ -d "$TPL" ] || { echo "rig-bootstrap: $TPL missing — harness install incomplete"; exit 1; }

if [ ! -f playwright.evidence.config.ts ]; then
  cp "$TPL/playwright.config.ts" playwright.evidence.config.ts
  echo "✓ playwright.evidence.config.ts installed (standalone --config rig)"
else
  echo "• playwright.evidence.config.ts already present"
fi

mkdir -p e2e
if [ ! -f e2e/_evidence.ts ]; then
  cp "$TPL/_evidence.ts" e2e/_evidence.ts
  echo "✓ e2e/_evidence.ts installed"
else
  echo "• e2e/_evidence.ts already present"
fi

if ! jq -e '.devDependencies["@playwright/test"] // .dependencies["@playwright/test"]' package.json >/dev/null 2>&1; then
  echo "→ npm i -D @playwright/test"
  npm i -D @playwright/test || { echo "✗ rig-bootstrap: @playwright/test install failed"; exit 1; }
else
  echo "• @playwright/test already a dependency"
fi

echo "→ npx playwright install chromium"
npx playwright install chromium || { echo "✗ rig-bootstrap: chromium install failed"; exit 1; }

echo "✓ evidence rig ready — author AC-tagged journeys in e2e/<spec-id>/ (tags: @AC-1 unpadded), run:"
echo "  VERIFY_FEATURE=<spec-slug> npx playwright test --config playwright.evidence.config.ts e2e/<spec-id>"
exit 0

#!/usr/bin/env bash
# Sentry release tracking + source maps — Round 12 A. Copy to scripts/ in shipped
# projects; call from the deploy/ship pipeline. Makes "click a prod error → see the
# introducing commit/PR" real (the Round 12 correlation chain).
#
# Requires: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT env vars.

set -euo pipefail

SHA="${RELEASE_SHA:-$(git rev-parse HEAD)}"
ENV="${DEPLOY_ENV:-production}"
RELEASE="${SENTRY_PROJECT:-app}@${SHA}"

command -v sentry-cli >/dev/null || npm install -g @sentry/cli

# 1. Create the release keyed on the commit SHA
sentry-cli releases new "$RELEASE"

# 2. Associate commits (enables "suspect commits" → the introducing PR)
sentry-cli releases set-commits "$RELEASE" --auto

# 3. Upload source maps so stack traces map to original source
if [ -d "${SOURCEMAP_DIR:-dist}" ]; then
  sentry-cli sourcemaps upload --release "$RELEASE" "${SOURCEMAP_DIR:-dist}"
fi

# 4. Mark the deploy (ties release → environment → timestamp)
sentry-cli releases deploys "$RELEASE" new -e "$ENV"

# 5. Finalize
sentry-cli releases finalize "$RELEASE"

echo "✓ Sentry release $RELEASE tracked for env=$ENV"
echo "  Errors now carry release=$SHA → suspect-commits → the introducing PR."
echo "  Correlation chain: trace_id ↔ release=$SHA ↔ commit ↔ spec (via spec.id OTEL attr)."

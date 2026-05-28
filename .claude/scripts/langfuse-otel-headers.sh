#!/usr/bin/env bash
# OTEL headers helper for Langfuse Cloud.
#
# Round 6 A. Claude Code calls this script (via settings.json otelHeadersHelper)
# every ~29 minutes to refresh OTLP headers. We emit Basic auth for Langfuse
# from a per-machine keys file OUTSIDE the repo so nothing committable leaks.
#
# Keys file path (gitignored by convention; create with chmod 600):
#   ~/.config/langfuse/keys.env
#
# Format:
#   LANGFUSE_PUBLIC_KEY=pk-lf-xxxxxxxx
#   LANGFUSE_SECRET_KEY=sk-lf-xxxxxxxx
#   # optional override:
#   LANGFUSE_HOST=https://cloud.langfuse.com
#
# Self-host: set LANGFUSE_HOST to your instance URL.
# Cloud EU: https://cloud.langfuse.com (EU region)
# Cloud US: https://us.cloud.langfuse.com
#
# Output: JSON object on stdout with header key/value pairs. Empty {} if
# keys not found — Claude Code will then attempt unauthenticated, Langfuse
# will reject 401, traces will drop. That's the desired safe-fail: no
# silent breakage of the harness, just a missing dashboard.

set -uo pipefail

keys_file="${LANGFUSE_KEYS_FILE:-$HOME/.config/langfuse/keys.env}"

if [ ! -f "$keys_file" ]; then
  echo '{}'
  exit 0
fi

# Source the keys file in a subshell to avoid polluting env
public_key=""
secret_key=""
host=""

while IFS='=' read -r key value; do
  # Skip comments and blank lines
  case "$key" in '#'*|'') continue ;; esac
  # Strip leading/trailing whitespace + quotes
  value="${value%\"}"; value="${value#\"}"
  case "$key" in
    LANGFUSE_PUBLIC_KEY) public_key="$value" ;;
    LANGFUSE_SECRET_KEY) secret_key="$value" ;;
    LANGFUSE_HOST) host="$value" ;;
  esac
done < "$keys_file"

if [ -z "$public_key" ] || [ -z "$secret_key" ]; then
  echo '{}'
  exit 0
fi

# Base64 of public:secret
auth=$(printf '%s:%s' "$public_key" "$secret_key" | base64 | tr -d '\n')

# Output the headers as JSON
cat <<EOF
{
  "Authorization": "Basic $auth",
  "x-langfuse-ingestion-version": "4"
}
EOF

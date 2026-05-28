#!/usr/bin/env bash
# PreToolUse hook for Write|Edit. Scans the proposed file content for secrets
# BEFORE the write hits disk. Uses gitleaks if installed; falls back to regex.

set -euo pipefail

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')
content=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // ""')

if [ -z "$content" ]; then
  exit 0
fi

# Block edits to .env, SSH, credentials, PEM/key/keystore, terraform state files.
# Use bash `[[ =~ ]]` regex (not `case` with `**`) — bash `case` doesn't do globstar,
# so `**/.ssh/*` in case only matches single-level depth (silent fail on deep paths).
blocked=0
case_path="${path}"
case_lower=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')

if [[ "$case_path" =~ \.env(\.[^/]+)?$ ]] \
  || [[ "$case_path" =~ /\.ssh/ ]] \
  || [[ "$case_path" =~ /\.gnupg/ ]] \
  || [[ "$case_path" =~ /\.aws/credentials ]] \
  || [[ "$case_lower" =~ credentials ]] \
  || [[ "$case_path" =~ \.(pem|key|p12|pfx|jks|keystore)$ ]] \
  || [[ "$case_path" =~ id_(rsa|ed25519|ecdsa|dsa) ]] \
  || [[ "$case_path" =~ \.(tfvars|tfstate)$ ]] \
  || [[ "$case_lower" =~ /secrets/ ]]; then
  blocked=1
fi

if [ "$blocked" = "1" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked by .claude/hooks/pre-write-secret-scan.sh: writing to '$path' is not permitted (matches secrets-file path policy). For env templates, edit .env.example by hand."
  }
}
EOF
  exit 0
fi

# Try gitleaks (preferred)
if command -v gitleaks >/dev/null 2>&1; then
  tmpf=$(mktemp)
  printf '%s' "$content" > "$tmpf"
  if ! gitleaks detect --no-banner --no-git --source "$tmpf" --redact -q 2>/dev/null; then
    rm -f "$tmpf"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked by .claude/hooks/pre-write-secret-scan.sh: gitleaks detected a secret in the proposed write to '$path'. Move the secret to environment variables and reference via process.env.* / os.environ.* / std::env."
  }
}
EOF
    exit 0
  fi
  rm -f "$tmpf"
fi

# Regex fallback for common secret patterns
regex_patterns=(
  # AWS
  'AKIA[0-9A-Z]{16}'                                          # AWS access key
  'ASIA[0-9A-Z]{16}'                                          # AWS STS temporary
  'aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}'
  # GitHub
  'ghp_[A-Za-z0-9]{36}'                                       # PAT classic
  'github_pat_[A-Za-z0-9_]{82}'                               # PAT fine-grained
  'gho_[A-Za-z0-9]{36}'                                       # OAuth
  'ghs_[A-Za-z0-9]{36}'                                       # GH server-to-server
  'ghu_[A-Za-z0-9]{36}'                                       # GH user-to-server
  # OpenAI
  'sk-proj-[A-Za-z0-9_-]{40,}'                                # OpenAI project key
  'sk-[A-Za-z0-9]{40,}'                                       # OpenAI v1 (and similar)
  # Anthropic — the hyphenated character class is critical
  'sk-ant-(api[0-9]+-)?[A-Za-z0-9_-]{80,}'
  # Stripe
  'sk_live_[0-9A-Za-z]{24,}'                                  # Stripe live secret
  'sk_test_[0-9A-Za-z]{24,}'                                  # Stripe test secret
  'rk_live_[0-9A-Za-z]{24,}'                                  # Stripe restricted
  'pk_live_[0-9A-Za-z]{24,}'                                  # Stripe publishable (warn)
  # Google / GCP
  'AIza[0-9A-Za-z_-]{35}'                                     # GCP API key
  '"type":[[:space:]]*"service_account"'                      # GCP service-account JSON
  'ya29\.[0-9A-Za-z_-]+'                                      # GCP OAuth token
  # Azure
  'DefaultEndpointsProtocol=https.*AccountKey=[A-Za-z0-9+/=]+' # Azure storage conn str
  # Slack
  'xoxb-[A-Za-z0-9-]{30,}'                                    # Bot token
  'xoxp-[A-Za-z0-9-]{30,}'                                    # User token
  'xoxa-[A-Za-z0-9-]{30,}'                                    # Workspace
  'xoxr-[A-Za-z0-9-]{30,}'                                    # Refresh
  # Generic credentials
  '-----BEGIN[A-Z[:space:]]+PRIVATE KEY-----'                 # PEM blocks
  'eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+' # JWT
  # SendGrid / Mailgun / Twilio
  'SG\.[A-Za-z0-9_-]{22,}\.[A-Za-z0-9_-]{40,}'                # SendGrid
  'key-[0-9a-f]{32}'                                          # Mailgun
  'SK[0-9a-f]{32}'                                            # Twilio
  # Heroku, DigitalOcean, npm, PyPI
  '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' # Generic UUID — high FP rate, used as last filter
  'dop_v1_[a-f0-9]{64}'                                       # DigitalOcean
  'npm_[A-Za-z0-9]{36}'                                       # npm token
  'pypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{50,}'                    # PyPI token
)

for pat in "${regex_patterns[@]}"; do
  if [[ "$content" =~ $pat ]]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked by .claude/hooks/pre-write-secret-scan.sh: regex matched a likely secret in '$path'. Move it to env vars."
  }
}
EOF
    exit 0
  fi
done

# ─── Round 5 C5: PII scrubber on memory writes ──────────────────────────
# When writing to .claude/memory/** (especially auto-dream / witness outputs
# that summarize transcript content), scrub common PII patterns. Different
# from the secret scan above — we WARN on PII (don't block), and the agent
# should rewrite without the PII.
case "$path" in
  .claude/memory/*|.claude/memory/.cache/*)
    pii_patterns=(
      # email
      '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
      # phone (US/international fragment)
      '\+?[0-9]{1,3}[-. ]?\(?[0-9]{3}\)?[-. ]?[0-9]{3}[-. ]?[0-9]{4}'
      # SSN-like
      '[0-9]{3}-[0-9]{2}-[0-9]{4}'
      # credit card-ish (rough)
      '4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}'
      # IP address (warn — sometimes legit, sometimes leaky log)
      '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
    )
    pii_hits=()
    for pat in "${pii_patterns[@]}"; do
      if [[ "$content" =~ $pat ]]; then
        pii_hits+=( "$(printf '%s' "$content" | grep -oE "$pat" | head -1)" )
      fi
    done
    if [ "${#pii_hits[@]}" -gt 0 ]; then
      hits_str=$(printf '%s, ' "${pii_hits[@]}" | sed 's/, $//')
      cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "PII detected in memory write to '$path': $hits_str. Memory files are long-lived — consider redacting (e.g., 'user@example.com' → 'a user'). Confirm to proceed."
  }
}
EOF
      exit 0
    fi
    ;;
esac

exit 0

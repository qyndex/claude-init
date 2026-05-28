---
description: Audit logs, fixtures, and test data for PII leaks. Semgrep + regex patterns for email/phone/CC/SSN. Run before /ship on any change touching log emissions or test fixtures.
argument-hint: "[--paths <glob>]"
allowed-tools: Read, Glob, Grep, Bash
disable-model-invocation: true
---

# /pii-audit — Catch PII leaks

```bash
paths="${1:-src/ tests/ fixtures/}"

echo "# PII audit"

# 1. Semgrep rule pack
if command -v semgrep >/dev/null; then
  echo "## Semgrep findings"
  semgrep --config=p/pii-detection $paths 2>/dev/null || \
  semgrep --config=auto --pattern-regex='(?i)(email|ssn|phone|credit.card|tax.id|passport)' $paths
fi

# 2. Regex patterns (fallback when semgrep absent)
echo
echo "## Regex findings"

# Emails in logs (excluding test@example.com test fixtures)
echo "### Emails (excluding test fixtures)"
rg -n '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b' $paths --type-add 'log:*.{log,txt,json}' -t log \
  | grep -v '@example\.\(com\|org\)' | grep -v '@test\.' | head -20

# Phone numbers (US format)
echo "### Phone numbers"
rg -n '\b(\+1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b' $paths | head -10

# Credit cards (Luhn-passing format only — strict)
echo "### Credit card patterns"
rg -n '\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b' $paths | head -10

# SSNs
echo "### SSN-shaped patterns"
rg -n '\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b' $paths | head -10

# 3. Structured-log redaction config check
echo
echo "## Logger redaction config"
echo "Looking for structlog processors / pino redact / winston filters..."
rg -n 'redact|REDACTED|\*{3,}|<REDACTED>' $paths --type-add 'cfg:*.{ts,js,py,yml,yaml}' -t cfg | head -10

echo
echo "If findings above are NOT in test fixtures with synthetic data, FIX BEFORE /ship."
echo "Add redaction at the logger level — never sanitize at the call site (too easy to miss)."
```

## Hard rules

- **Test fixtures must use synthetic data.** `test@example.com` / `555-0100` / Luhn-failing CCs / `000-00-0000` SSN.
- **Redact at the logger level, not the call site.** Field-level redaction (structlog processor / Pino redact array / Winston format filter) is the only reliable approach.
- **Never log raw request bodies.** Logging "request received" is fine; logging the body is not.
- **Audit on every change that touches log emissions or fixtures.** Add to `verify-loop` for changes under `src/api/` / `src/handlers/` / `tests/fixtures/`.

$ARGUMENTS

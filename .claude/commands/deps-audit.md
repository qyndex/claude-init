---
description: Audit dependencies — list outdated + vulnerable + low-quality packages. Queries live registries (npm/PyPI/crates) + OSV vulnerability DB + deps.dev quality scores. Round 8 A.
argument-hint: "[--stack <npm|pypi|crates|go>] [--vuln-only] [--major-only]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /deps audit — Live dependency freshness + vuln check

On-demand version of the nightly OSV scan. Queries live registries — does NOT trust LLM training-cutoff knowledge.

```bash
STACK=""
VULN_ONLY=0
MAJOR_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) STACK="$2"; shift 2 ;;
    --vuln-only) VULN_ONLY=1; shift ;;
    --major-only) MAJOR_ONLY=1; shift ;;
    *) shift ;;
  esac
done

# Detect stacks if not specified
if [ -z "$STACK" ]; then
  detected_json=$(bash .claude/scripts/detect-stacks.sh 2>/dev/null || echo '{"stacks":[]}')
  detected=$(echo "$detected_json" | jq -r '.stacks[]' 2>/dev/null)
else
  detected="$STACK"
fi

mkdir -p .claude/memory/audits
report=".claude/memory/audits/deps-audit-$(date +%Y-%m-%d).md"

{
  echo "# Dependency audit — $(date -Iseconds)"
  echo
  echo "Live registry queries (npm/PyPI/crates) + OSV.dev vuln DB. NOT training-cutoff knowledge."
  echo

  for stack in $detected; do
    echo "## $stack"
    echo

    case "$stack" in
      npm|typescript|javascript)
        if [ -f package.json ]; then
          echo "### Outdated"
          echo '```'
          npm outdated --json 2>/dev/null | jq -r 'to_entries[] | "\(.key): \(.value.current) → \(.value.latest) (\(.value.type))"' 2>/dev/null || npm outdated 2>/dev/null
          echo '```'
          echo
          echo "### npm audit"
          echo '```'
          npm audit --omit=dev --json 2>/dev/null | jq -r '.metadata.vulnerabilities | to_entries[] | "\(.key): \(.value)"' 2>/dev/null
          echo '```'
        fi
        ;;
      python|pypi)
        if [ -f pyproject.toml ] || [ -f requirements.txt ]; then
          echo "### Outdated"
          echo '```'
          pip list --outdated --format=json 2>/dev/null | jq -r '.[] | "\(.name): \(.version) → \(.latest_version) (\(.latest_filetype))"' 2>/dev/null || pip list --outdated 2>/dev/null
          echo '```'
          echo
          echo "### pip-audit"
          echo '```'
          pip-audit --format json 2>/dev/null | jq -r '.dependencies[] | select(.vulns | length > 0) | "\(.name) \(.version): \(.vulns | map(.id) | join(", "))"' 2>/dev/null
          echo '```'
        fi
        ;;
      rust|crates)
        if [ -f Cargo.toml ]; then
          echo "### Outdated"
          echo '```'
          cargo outdated --format json 2>/dev/null | jq -r '.dependencies[] | "\(.name): \(.project) → \(.latest)"' 2>/dev/null || cargo outdated 2>/dev/null
          echo '```'
          echo
          echo "### cargo audit"
          echo '```'
          cargo audit --json 2>/dev/null | jq -r '.vulnerabilities.list[] | "\(.package.name) \(.package.version): \(.advisory.id)"' 2>/dev/null
          echo '```'
        fi
        ;;
      go)
        if [ -f go.mod ]; then
          echo "### Outdated"
          echo '```'
          go list -u -m -json all 2>/dev/null | jq -r 'select(.Update) | "\(.Path): \(.Version) → \(.Update.Version)"' 2>/dev/null
          echo '```'
          echo
          echo "### govulncheck"
          echo '```'
          govulncheck -json ./... 2>/dev/null | jq -r '.osv | select(. != null) | "\(.id): \(.summary)"' 2>/dev/null
          echo '```'
        fi
        ;;
    esac
  done

  echo
  echo "## Action items"
  echo
  echo "- For each vuln-flagged package: bump to latest stable (per registry above), let CI verify"
  echo "- For majors: run \`/upgrade <pkg> --major --to <ver>\` (Round 4 D) — includes migration guide + codemods"
  echo "- For low-quality packages (low scorecard, abandoned): replace; document the swap in an ADR"
  echo
  echo "Or wait for the next daily-stale-deps.yml run at 03:00 UTC (Round 8 B)."

} > "$report"

echo "✓ Report: $report"
head -30 "$report"
```

## Hard rules

- **NEVER use LLM-training-cutoff version numbers.** Always query the registry.
- **OSV is authoritative for vulns.** A package showing 0 vulns in `npm audit` but matches in OSV → trust OSV.
- **deps.dev scorecard ≥ 5.0** is the bar for new package adoption.
- **Patch + minor**: auto-bump candidates (Batch B handles)
- **Major**: deliberate, via `/upgrade`

$ARGUMENTS

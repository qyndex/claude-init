#!/usr/bin/env bash
# Stale-deps scan — Round 8 B.
#
# For a given stack, emit a JSON list of bump candidates ranked by:
#   1. vulns-with-fix-available
#   2. major-stale-by-N-versions (if --include-majors)
#   3. minor-stale
#   4. patch-stale
#
# Usage: bash scan.sh <stack> [--include-majors]
# Output: /tmp/candidates-<stack>.json — [{pkg, from, to, kind, has_vuln, osv_ids}]

set -uo pipefail

STACK="${1:?stack required}"
INCLUDE_MAJORS=0
[ "${2:-}" = "--include-majors" ] && INCLUDE_MAJORS=1

OUT="/tmp/candidates-${STACK}.json"

case "$STACK" in
  npm|typescript)
    if [ ! -f package.json ]; then echo '[]' > "$OUT"; exit 0; fi
    npm outdated --json 2>/dev/null | jq --argjson maj "$INCLUDE_MAJORS" '
      to_entries | map({
        pkg: .key,
        from: .value.current,
        to: .value.latest,
        kind: (
          if (.value.current | split(".")[0]) == (.value.latest | split(".")[0]) then
            (if (.value.current | split(".")[1]) == (.value.latest | split(".")[1]) then "patch" else "minor" end)
          else "major" end
        ),
        has_vuln: false, osv_ids: []
      })
      | map(select(.kind != "major" or $maj == 1))
    ' > "$OUT"
    ;;
  python|pypi)
    if [ ! -f pyproject.toml ] && [ ! -f requirements.txt ]; then echo '[]' > "$OUT"; exit 0; fi
    pip list --outdated --format=json 2>/dev/null | jq --argjson maj "$INCLUDE_MAJORS" '
      map({
        pkg: .name, from: .version, to: .latest_version,
        kind: (
          if (.version | split(".")[0]) == (.latest_version | split(".")[0]) then "minor" else "major" end
        ),
        has_vuln: false, osv_ids: []
      })
      | map(select(.kind != "major" or $maj == 1))
    ' > "$OUT"
    ;;
  rust|crates)
    if [ ! -f Cargo.toml ]; then echo '[]' > "$OUT"; exit 0; fi
    cargo outdated --format json 2>/dev/null | jq --argjson maj "$INCLUDE_MAJORS" '
      .dependencies // [] | map({
        pkg: .name, from: .project, to: .latest,
        kind: (if .kind == "Major" then "major" else "minor" end),
        has_vuln: false, osv_ids: []
      })
      | map(select(.kind != "major" or $maj == 1))
    ' > "$OUT"
    ;;
  go)
    if [ ! -f go.mod ]; then echo '[]' > "$OUT"; exit 0; fi
    go list -u -m -json all 2>/dev/null | jq -s --argjson maj "$INCLUDE_MAJORS" '
      [.[] | select(.Update) | {
        pkg: .Path, from: .Version, to: .Update.Version,
        kind: (
          if (.Version | split(".")[0]) == (.Update.Version | split(".")[0]) then "minor" else "major" end
        ),
        has_vuln: false, osv_ids: []
      }]
      | map(select(.kind != "major" or $maj == 1))
    ' > "$OUT"
    ;;
  *)
    echo '[]' > "$OUT"
    ;;
esac

# Cross-reference OSV — mark has_vuln=true on any candidate whose CURRENT
# version has known vulns (these get priority since the bump fixes them).
if command -v jq >/dev/null && [ -s "$OUT" ]; then
  echo "→ OSV cross-reference for $STACK"
  tmp=$(mktemp)
  jq -c '.[]' "$OUT" | while IFS= read -r entry; do
    pkg=$(echo "$entry" | jq -r .pkg)
    from=$(echo "$entry" | jq -r .from)
    eco_name="$STACK"
    case "$STACK" in npm|typescript) eco_name="npm" ;; python|pypi) eco_name="PyPI" ;; rust|crates) eco_name="crates.io" ;; go) eco_name="Go" ;; esac

    osv=$(curl -fsSL -X POST "https://api.osv.dev/v1/query" \
      -H "Content-Type: application/json" \
      -d "{\"package\":{\"name\":\"$pkg\",\"ecosystem\":\"$eco_name\"},\"version\":\"$from\"}" \
      2>/dev/null)

    vulns=$(echo "$osv" | jq -r '.vulns // [] | length')
    if [ "${vulns:-0}" -gt 0 ]; then
      ids=$(echo "$osv" | jq -c '.vulns // [] | map(.id)')
      echo "$entry" | jq --argjson ids "$ids" '. + {has_vuln: true, osv_ids: $ids}' >> "$tmp"
    else
      echo "$entry" >> "$tmp"
    fi
  done
  jq -s '. | sort_by(if .has_vuln then 0 elif .kind == "minor" then 1 else 2 end)' "$tmp" > "$OUT"
  rm -f "$tmp"
fi

count=$(jq 'length' "$OUT")
echo "→ $count candidates for $STACK at $OUT"

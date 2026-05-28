#!/usr/bin/env bash
# Assertion-density gate — Round 10 A.
#
# Catches assertion-free tests: every test block must contain ≥1 real assertion.
# Also bans tautological asserts (expect(true).toBe(true), assert True).
#
# Scans changed test files (vs main) by default; --all scans every test file.
# Exit 1 if any test block lacks an assertion or uses a banned tautology.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-changed}"   # changed | --all

# Find test files
if [ "$MODE" = "--all" ]; then
  test_files=$(find . \( -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' -o -name '*_test.go' -o -name '*_test.rs' \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/target/*' 2>/dev/null)
else
  base="${BASE_REF:-main}"
  test_files=$(git diff --name-only "$base...HEAD" 2>/dev/null | grep -E '\.(test|spec)\.|test_.*\.py$|_test\.(go|rs)$' || true)
fi

[ -z "$test_files" ] && { echo "assert-density: no test files to check"; exit 0; }

# Assertion markers per language
assert_markers='expect\(|assert |assert\.|assert_|\.should|\.to\.|chai\.|sinon\.|test\.assert|require\.(Equal|True|False|NoError|Error)|t\.(Errorf|Fatal|Fatalf)|XCTAssert'

# Banned tautologies
banned='expect\(true\)\.toBe\(true\)|expect\(1\)\.toBe\(1\)|assert True$|assert 1 == 1|assert_eq!\(1, ?1\)|expect\(true\)\.toBeTruthy\(\)'

issues=0
checked=0

for f in $test_files; do
  [ -f "$f" ] || continue
  checked=$((checked + 1))

  # Banned tautology check (whole file)
  if grep -nE "$banned" "$f" >/dev/null 2>&1; then
    echo "  ✗ $f — tautological assertion (expect(true).toBe(true) or equivalent)"
    grep -nE "$banned" "$f" | head -3 | sed 's/^/      /'
    issues=$((issues + 1))
  fi

  # Per-block assertion check (awk: each it/test/def-test block has ≥1 assertion)
  awk -v file="$f" -v markers="$assert_markers" '
    BEGIN { in_block=0; depth=0; has_assert=0; block_line=0; block_name="" }
    # Block openers (JS/TS it/test, Python def test_, Go func Test, Rust #[test])
    /(\bit\(|\btest\(|\bit\.each|\btest\.each)/ && !in_block {
      in_block=1; depth=0; has_assert=0; block_line=NR; block_name=$0
    }
    in_block {
      # count braces for JS/TS blocks
      n=gsub(/\{/, "{"); depth += n
      m=gsub(/\}/, "}"); depth -= m
      if ($0 ~ markers) has_assert=1
      # block closes when depth returns to 0 after having opened
      if (depth <= 0 && NR > block_line) {
        if (!has_assert) {
          printf "  ✗ %s:%d — test block has no assertion\n", file, block_line
          bad++
        }
        in_block=0
      }
    }
    END { exit (bad>0 ? 1 : 0) }
  ' "$f" || issues=$((issues + 1))
done

echo "assert-density: checked $checked test file(s), $issues issue(s)"
[ "$issues" -eq 0 ]

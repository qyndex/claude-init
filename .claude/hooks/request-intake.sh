#!/usr/bin/env bash
# Protected generated settings supply all three absolute pinned paths.
set -euo pipefail
[ "$#" -eq 3 ] || exit 2
for path in "$@"; do case "$path" in /*) ;; *) exit 2 ;; esac; done
exec "$1" -I -S "$2" --descriptor "$3" --event UserPromptSubmit

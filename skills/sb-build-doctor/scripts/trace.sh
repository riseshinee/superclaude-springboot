#!/usr/bin/env bash
# Condenses a Spring Boot application log or pasted stack trace: the startup-failure report,
# distinct ERROR lines with counts, and distinct stack traces with framework frames collapsed.
#
# Usage:
#   bash trace.sh logs/app.log
#   bash trace.sh < trace.txt
#   ./gradlew bootRun 2>&1 | bash trace.sh
set -uo pipefail
src="${BASH_SOURCE[0]//\\//}"; here="${src%/*}"; [ "$here" = "$src" ] && here=.
export LC_ALL=C

out="$(awk -f "$here/extract-log.awk" "$@" | awk -f "$here/condense.awk")"
if [ -n "$out" ]; then
  printf '%s\n' "$out"
else
  echo "No stack traces, ERROR lines or startup-failure report found."
fi

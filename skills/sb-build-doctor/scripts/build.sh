#!/usr/bin/env bash
# Runs a Gradle or Maven build and prints a condensed report instead of the raw console output:
# compile errors, failed tests with trimmed stack traces, and the build tool's own failure summary.
# The full log is kept in .claude/build-doctor/last-build.log for targeted grep.
#
# Usage (from the project or module root):
#   bash build.sh                                   # default: test
#   bash build.sh compileJava                       # Gradle: compile only
#   bash build.sh test --tests 'com.acme.order.*'   # Gradle: one package/class
#   bash build.sh test -Dtest=OrderServiceTest      # Maven: one class
# Env: BUILD_TOOL=gradle|maven overrides detection.
# Exit code: the build's own exit code.
set -uo pipefail
src="${BASH_SOURCE[0]//\\//}"; here="${src%/*}"; [ "$here" = "$src" ] && here=.
here="$(cd "$here" && pwd)"

# --- detect the build tool --------------------------------------------------------------------------
tool="${BUILD_TOOL:-}"
if [ -z "$tool" ]; then
  if [ -f build.gradle ] || [ -f build.gradle.kts ] || [ -f settings.gradle ] || [ -f settings.gradle.kts ]; then
    tool=gradle
  elif [ -f pom.xml ]; then
    tool=maven
  else
    echo "sb-build-doctor: no build.gradle(.kts) or pom.xml in $PWD; run from the project or module root." >&2
    exit 2
  fi
fi

# Nearest wrapper in this directory or a parent; its directory is the project root.
find_up() {
  local dir="$PWD"
  while :; do
    [ -f "$dir/$1" ] && { echo "$dir"; return 0; }
    [ -z "$dir" ] || [ "$dir" = / ] && return 1
    dir="${dir%/*}"
  done
}

case "$tool" in
  gradle) wrapper=gradlew; win_wrapper=gradlew.bat; fallback=gradle; default_task=test; extra=(--console=plain) ;;
  maven)  wrapper=mvnw;    win_wrapper=mvnw.cmd;    fallback=mvn;    default_task=test; extra=(-B -Dstyle.color=never) ;;
  *) echo "sb-build-doctor: unknown BUILD_TOOL '$tool' (use gradle or maven)" >&2; exit 2 ;;
esac

if wrapper_dir="$(find_up "$wrapper")"; then
  project_root="$wrapper_dir"
  cmd=("$wrapper_dir/$wrapper")
  # A wrapper script checked out with CRLF fails under bash; use the Windows launcher instead.
  if IFS= read -r first_line < "$wrapper_dir/$wrapper" && [[ $first_line == *$'\r' ]] && [ -f "$wrapper_dir/$win_wrapper" ]; then
    cmd=("$wrapper_dir/$win_wrapper")
  fi
elif command -v "$fallback" >/dev/null 2>&1; then
  project_root="$PWD"
  cmd=("$fallback")
else
  echo "sb-build-doctor: neither ./$wrapper nor '$fallback' on PATH was found." >&2
  exit 2
fi

[ "$#" -eq 0 ] && set -- "$default_task"
for arg in "$@"; do
  [[ $arg == --console* ]] && extra=()
done

# --- run --------------------------------------------------------------------------------------------
state_dir="$project_root/.claude/build-doctor"
mkdir -p "$state_dir"
[ -f "$state_dir/.gitignore" ] || printf '*\n' > "$state_dir/.gitignore"
log="$state_dir/last-build.log"
marker="$state_dir/.started"
: > "$marker"

SECONDS=0
"${cmd[@]}" "${extra[@]}" "$@" > "$log" 2>&1 < /dev/null
code=$?
secs=$SECONDS

export LC_ALL=C
root1="$project_root"
root2="$( (cd "$project_root" && pwd -W) 2>/dev/null || true)"
rel_log="${log#"$PWD"/}"

# --- test reports written by this run --------------------------------------------------------------
xml_files=()
while IFS= read -r f; do xml_files+=("$f"); done < <(
  find . \( -name node_modules -o -name .git -o -name .gradle \) -prune -o \
    \( -path '*/build/test-results/*' -o -path '*/target/surefire-reports/*' -o -path '*/target/failsafe-reports/*' \) \
    -name 'TEST-*.xml' -newer "$marker" -print 2>/dev/null)

junit_out=""
totals=""
if [ "${#xml_files[@]}" -gt 0 ]; then
  junit_out="$(awk -f "$here/junit.awk" "${xml_files[@]}")"
  totals="${junit_out##*@@TOTALS }"
  junit_out="${junit_out%@@TOTALS *}"
fi

# --- report -----------------------------------------------------------------------------------------
report="$(
  if [ "$code" -eq 0 ]; then status="BUILD SUCCESSFUL"; else status="BUILD FAILED"; fi
  echo "$status  ($tool $* | exit $code | ${secs}s)"
  if [ -n "$totals" ]; then
    read -r t f e s <<< "$totals"
    echo "Tests: $t run, $f failed, $e errors, $s skipped"
  elif [[ " $* " =~ [[:space:]](test|build|check|verify|package|install|integrationTest)[[:space:]] ]]; then
    echo "Tests: no new test reports (tests up-to-date, filtered out, or never reached)"
  fi
  echo

  if [ "$code" -ne 0 ]; then
    have_xml=0; [ -n "$junit_out" ] && have_xml=1
    summary="$(awk -v root1="$root1" -v root2="$root2" -v have_xml="$have_xml" -f "$here/summarize.awk" "$log")"
    startup="$(awk -v only_startup=1 -f "$here/extract-log.awk" "$log")"
    [ -n "$summary" ] && printf '%s\n\n' "$summary"
    [ -n "$startup" ] && printf '%s\n\n' "$startup"
    if [ -n "$junit_out" ]; then
      echo "## Test failures"
      printf '%s\n' "$junit_out" | awk -v root1="$root1" -v root2="$root2" -f "$here/condense.awk"
    fi
    if [ -z "$summary$startup$junit_out" ]; then
      echo "## Last lines of the log (no known error pattern matched)"
      grep -v '^[[:space:]]*$' "$log" | tail -n 25
    fi
  fi
)"
printf '%s\n' "$report"

# --- circuit breaker: the same failure 3 runs in a row within 10 minutes ---------------------------
history="$state_dir/failures"
if [ "$code" -eq 0 ]; then
  rm -f "$history"
else
  sig="$(printf '%s\n' "$report" | sed '1,/^$/d' | grep -v -e '^##' -e '^[[:space:]]*$' -e '^[[:space:]]*\.\.\.' | head -n 3 \
    | tr -d '0-9' | cksum | cut -d' ' -f1)"
  now="$(date +%s)"
  echo "$now $sig" >> "$history"
  tail -n 3 "$history" > "$history.tmp" && mv "$history.tmp" "$history"
  same=0; oldest="$now"
  while read -r ts s; do
    if [ "$s" = "$sig" ]; then same=$((same + 1)); [ "$ts" -lt "$oldest" ] && oldest="$ts"; else same=0; oldest="$now"; fi
  done < "$history"
  if [ "$same" -ge 3 ] && [ $((now - oldest)) -le 600 ]; then
    echo
    echo "!! CIRCUIT BREAKER: the same failure occurred $same times in a row within 10 minutes."
    echo "!! Stop changing code. Report to the user instead: the failure, the fixes you tried, your"
    echo "!! hypotheses, and what you need from them. See 'Circuit breaker' in the sb-build-doctor skill."
  fi
fi

log_lines="$(wc -l < "$log" | tr -d " ")"
echo
echo "Full log: $rel_log ($log_lines lines). grep it for specifics; do not print it whole."
exit "$code"

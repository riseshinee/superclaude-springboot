#!/usr/bin/env bash
# PreToolUse hook: stops any tool call (Read, Grep, Bash, ...) that names a protected path, so the
# file's contents never enter Claude's context. Complements permissions.deny, which does not see
# paths inside arbitrary shell commands.
set -uo pipefail
src="${BASH_SOURCE[0]//\\//}"; here="${src%/*}"; [ "$here" = "$src" ] && here=.
source "$here/lib.sh" || { echo "[sb-security-guard] lib.sh missing; blocked (fail-closed)." >&2; exit 2; }

load_policy
read_payload

# Only fields that say what gets read or run. Written content (Edit new_string, Write content) is left
# alone so adding ".env" to .gitignore or documenting it isn't blocked.
TARGET_FIELD='"(file_path|notebook_path|path|glob|command)"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
rest="$PAYLOAD"
PAYLOAD=""
while [[ $rest =~ $TARGET_FIELD ]]; do
  PAYLOAD+=" ${BASH_REMATCH[2]}"
  rest="${rest/"${BASH_REMATCH[0]}"/}"
done

if first_match path protected-paths; then
  block "Access to a protected path was blocked: $MATCH (security policy: protected path)" \
    "Company security policy forbids giving this path's contents to Claude. Do not work around it with another command or path; ask the user for the information you need in masked form."
fi
exit 0

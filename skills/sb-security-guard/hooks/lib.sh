#!/usr/bin/env bash
# Shared helpers for the sb-security-guard hooks. Sourced, not executed.
#
# Hooks run on every prompt and tool call, so this file uses bash builtins only ([[ =~ ]], parameter
# expansion, read) and never forks grep/sed/awk: process creation costs whole seconds per hook under
# Git Bash on Windows. No jq/node/python required either.

# Claude Code on Windows may hand hooks a backslash path (C:\proj\.claude\...); fold it to slashes.
GUARD_HOOKS_DIR="${BASH_SOURCE[0]//\\//}"
case "$GUARD_HOOKS_DIR" in
  */*) GUARD_HOOKS_DIR="${GUARD_HOOKS_DIR%/*}" ;;
  *)   GUARD_HOOKS_DIR=. ;;
esac
GUARD_SKILL_DIR="$GUARD_HOOKS_DIR/.."
# Byte-wise, case-insensitive matching: predictable across locales and safe for UTF-8 (Korean) input.
LC_ALL=C
shopt -s nocasematch

# Sets POLICY: the project policy wins, the skill's bundled default is the fallback.
resolve_policy() {
  local root="${CLAUDE_PROJECT_DIR:-.}"
  root="${root//\\//}"
  POLICY=""
  if [ -f "$root/.claude/security-policy.conf" ]; then
    POLICY="$root/.claude/security-policy.conf"
  elif [ -f "$GUARD_SKILL_DIR/policy/security-policy.conf" ]; then
    POLICY="$GUARD_SKILL_DIR/policy/security-policy.conf"
  fi
}

# Sets RULES to the entries of one [section]: comments, blank lines, indentation and CRLF stripped.
policy_section() {
  local line in_section=0
  RULES=()
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
      '' | '#'*) continue ;;
      '['*']') [ "$line" = "[$1]" ] && in_section=1 || in_section=0; continue ;;
    esac
    [ "$in_section" -eq 1 ] && RULES+=("$line")
  done < "$POLICY"
}

# Sets ERE to a regex that finds the gitignore-style glob $1 anywhere inside a larger string (a
# file_path or a shell command). Bounded on both sides so ".env" does not match "app.env" and
# "*.key" does not match code like "entry.key()".
GLOB_END='([[:space:]"'"'"'`\\;:,|&<>)]|$)'
glob_to_ere() {
  local glob="${1#./}" body="" tail="" c i=0
  glob="${glob#/}"
  case "$glob" in
    */'**') glob="${glob%/\*\*}"; tail='(/.*)?' ;;
  esac
  while [ "$i" -lt "${#glob}" ]; do
    c="${glob:i:1}"
    if [ "${glob:i:3}" = '**/' ]; then body+='(.*/)?'; i=$((i + 3)); continue; fi
    if [ "${glob:i:2}" = '**' ]; then body+='.*'; i=$((i + 2)); continue; fi
    case "$c" in
      '*') body+='[^/]*' ;;
      '?') body+='[^/]' ;;
      [.+\(\)\{\}\|^\$\[\]\\]) body+="\\$c" ;;
      *) body+="$c" ;;
    esac
    i=$((i + 1))
  done
  ERE="(^|[^A-Za-z0-9_.-])$body$tail$GLOB_END"
}

# Sets PAYLOAD from the hook's stdin JSON, minus session metadata (cwd, transcript path, ids) so only
# user/tool content is scanned, with JSON-escaped Windows separators (C:\\a\\b) folded into slashes.
META_FIELD='"(cwd|transcript_path|scratchpad_dir|session_id|prompt_id|tool_use_id)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"'
read_payload() {
  IFS= read -r -d '' PAYLOAD || true
  while [[ $PAYLOAD =~ $META_FIELD ]]; do
    PAYLOAD="${PAYLOAD/"${BASH_REMATCH[0]}"/}"
  done
  PAYLOAD="${PAYLOAD//\\\\//}"
}

# first_match <regex|keyword|path> <section>: sets MATCH to the first rule of <section> found in PAYLOAD.
first_match() {
  local rule
  policy_section "$2"
  for rule in "${RULES[@]}"; do
    case "$1" in
      regex)   [[ $PAYLOAD =~ $rule ]] ;;
      keyword) [[ $PAYLOAD == *"$rule"* ]] ;;
      path)    glob_to_ere "$rule"; [[ $PAYLOAD =~ $ERE ]] ;;
    esac && { MATCH="$rule"; return 0; }
  done
  return 1
}

# Exit code 2 is the blocking signal for both UserPromptSubmit and PreToolUse; stderr is the reason.
block() {
  printf '[sb-security-guard] %s\n' "$@" >&2
  exit 2
}

# Fail closed: without a policy nothing can be verified, so nothing goes through.
load_policy() {
  resolve_policy
  [ -n "$POLICY" ] || block "No security policy (.claude/security-policy.conf) found; blocked (fail-closed)."
}

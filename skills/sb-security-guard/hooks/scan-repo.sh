#!/usr/bin/env bash
# Audit helper: finds policy violations already sitting in the repository.
# Prints ONLY locations (file:line) and rule names, never matched content, so running it through
# Claude does not pull the secrets it finds into the conversation.
# Usage: CLAUDE_PROJECT_DIR=<project> bash scan-repo.sh
set -uo pipefail
src="${BASH_SOURCE[0]//\\//}"; here="${src%/*}"; [ "$here" = "$src" ] && here=.
here="$(cd "$here" && pwd)"
export CLAUDE_PROJECT_DIR="$(cd "${CLAUDE_PROJECT_DIR:-.}" && pwd)"
source "$here/lib.sh"
shopt -u nocasematch

cd "$CLAUDE_PROJECT_DIR" || exit 1
resolve_policy
[ -n "$POLICY" ] || { echo "no policy file found"; exit 1; }
echo "policy: $POLICY"

# .claude/ is skipped in content searches: the policy file and this skill's tests contain the very
# patterns and sample values being searched for.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  in_git=1
  list_files() { git ls-files; }
  # -I skips binaries; cut keeps "file:line" and drops the matched text.
  search() { git grep -n -I -i "$@" -- . ':!.claude' | cut -d: -f1,2; }
else
  in_git=0
  echo "(not a git repository: scanning the working tree)"
  excludes=(--exclude-dir=.git --exclude-dir=build --exclude-dir=target --exclude-dir=.gradle --exclude-dir=node_modules --exclude-dir=.claude)
  list_files() { find . -type f -not -path './.git/*' | sed 's#^\./##'; }
  search() { grep -r -n -I -i "${excludes[@]}" "$@" . | sed 's#^\./##' | cut -d: -f1,2; }
fi

findings=0
report() { # <title> <lines...>
  local title="$1"; shift
  [ "$#" -eq 0 ] && return
  echo; echo "## $title"
  printf '  %s\n' "$@"
  findings=$((findings + $#))
}

policy_section protected-paths
patterns=("${RULES[@]}")
files=()
while IFS= read -r f; do
  for g in "${patterns[@]}"; do
    glob_to_ere "$g"
    if [[ "/$f" =~ $ERE ]]; then files+=("$f   [$g]"); break; fi
  done
done < <(list_files)
if [ "$in_git" -eq 1 ]; then
  report "Protected files committed to git (remove from history + .gitignore)" "${files[@]}"
else
  report "Protected files present (confirm they are excluded from VCS)" "${files[@]}"
fi

policy_section secret-patterns
hits=()
for rule in "${RULES[@]}"; do
  while IFS= read -r loc; do hits+=("$loc   [secret-patterns: ${rule:0:40}...]"); done < <(search -E -e "$rule")
done
report "Secret / PII patterns in files" "${hits[@]}"

policy_section sensitive-keywords
hits=()
for rule in "${RULES[@]}"; do
  while IFS= read -r loc; do hits+=("$loc   [sensitive-keywords: $rule]"); done < <(search -F -e "$rule")
done
report "Confidential keywords in files" "${hits[@]}"

echo
echo "total findings: $findings"

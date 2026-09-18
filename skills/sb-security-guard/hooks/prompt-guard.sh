#!/usr/bin/env bash
# UserPromptSubmit hook: stops a prompt that carries secrets, personal data, or confidential/business
# terms. A blocked prompt is erased and never sent to the model.
set -uo pipefail
src="${BASH_SOURCE[0]//\\//}"; here="${src%/*}"; [ "$here" = "$src" ] && here=.
source "$here/lib.sh" || { echo "[sb-security-guard] lib.sh missing; blocked (fail-closed)." >&2; exit 2; }

load_policy
read_payload

deny() {
  block "Prompt blocked. It was not sent to Claude." \
    "  Reason: $1" \
    "  Rule:   $MATCH" \
    "  Action: remove or mask (****) the value and try again. If this is a false positive, ask your security team to adjust .claude/security-policy.conf."
}

first_match regex secret-patterns && deny "contains what looks like a secret or personal data (secret/PII pattern)"
first_match keyword sensitive-keywords && deny "contains a confidential or internal business keyword"
# Protected paths are not checked here: naming ".env" in a question is fine, and @file mentions of
# protected files are already refused by the Read deny rules that setup generates.
exit 0

#!/usr/bin/env bash
# Verifies the active policy: every regex compiles, and the hooks block/allow representative inputs.
# Usage: CLAUDE_PROJECT_DIR=<project> bash selftest.sh    (exit 0 = all passed)
set -uo pipefail
src="${BASH_SOURCE[0]//\\//}"; HOOKS="${src%/*}"
[ "$HOOKS" = "$src" ] && HOOKS=.
source "$HOOKS/lib.sh"

resolve_policy
if [ -z "$POLICY" ]; then
  echo "FAIL  no policy file found"; exit 1
fi
echo "policy: $POLICY"
failures=0

check_compiles() { # <section> <label>
  local rule
  policy_section "$1"
  echo "ok    [$1] ${#RULES[@]} rule(s)"
  for rule in "${RULES[@]}"; do
    [ "$2" = path ] && { glob_to_ere "$rule"; rule="$ERE"; }
    [[ "" =~ $rule ]]
    if [ $? -eq 2 ]; then
      echo "FAIL  invalid rule in [$1]: $rule"; failures=$((failures + 1))
    fi
  done
}
check_compiles secret-patterns regex
check_compiles sensitive-keywords keyword
check_compiles protected-paths path

# expect <block|allow> <hook> <json-field> <value>
expect() {
  local want="$1" hook="$2" field="$3" value="$4" body got
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  if [ "$hook" = prompt ]; then
    body="\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"$value\""
  else
    body="\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Tool\",\"tool_input\":{\"$field\":\"$value\"}"
  fi
  printf '{"session_id":"selftest","cwd":"C:\\\\work\\\\secrets\\\\app",%s}' "$body" \
    | bash "$HOOKS/$hook-guard.sh" >/dev/null 2>&1
  [ $? -eq 2 ] && got=block || got=allow
  if [ "$got" = "$want" ]; then
    echo "ok    $want  $hook  $4"
  else
    echo "FAIL  expected $want, got $got  $hook  $4"; failures=$((failures + 1))
  fi
}

# expect_tool_json <block|allow> <label> <raw tool_input JSON object>
expect_tool_json() {
  local got
  printf '{"hook_event_name":"PreToolUse","tool_name":"Tool","tool_input":%s}' "$3" \
    | bash "$HOOKS/tool-guard.sh" >/dev/null 2>&1
  [ $? -eq 2 ] && got=block || got=allow
  if [ "$got" = "$1" ]; then
    echo "ok    $1  tool  $2"
  else
    echo "FAIL  expected $1, got $got  tool  $2"; failures=$((failures + 1))
  fi
}

echo "--- prompt-guard (default rules) ---"
expect block prompt prompt 'spring.datasource.password: S3cretPassw0rd!'
expect block prompt prompt 'cannot connect with aws key AKIAIOSFODNN7EXAMPLE'
expect block prompt prompt 'url: jdbc:mysql://admin:pa55word@db.acme.io:3306/app'
expect block prompt prompt 'query customer by RRN 900101-1234567'
expect block prompt prompt 'this design doc is CONFIDENTIAL'
expect block prompt prompt 'the DB server is at 10.20.30.40'
expect allow prompt prompt 'create a sign-up API in UserService'
expect allow prompt prompt 'String token = jwtProvider.createToken(user);'
expect allow prompt prompt 'password: ${DB_PASSWORD}'
expect allow prompt prompt 'how do I set up a .env file?'
expect allow prompt prompt 'difference between localhost:8080 and 127.0.0.1'
expect allow prompt prompt 'private String password;'

echo "--- tool-guard (default rules) ---"
expect block tool file_path 'C:\work\app\.env'
expect block tool command 'cat src/main/resources/application-prod.yml'
expect block tool path 'config/secrets'
expect block tool file_path '/home/dev/.aws/credentials'
expect block tool command 'openssl x509 -in certs/server.pem -text'
expect allow tool file_path 'C:\work\app\src\main\java\com\acme\UserService.java'
expect allow tool file_path 'src/main/resources/application.yml'
expect allow tool command './gradlew test'
expect allow tool command 'grep -n "entry.key()" src/Foo.java'
expect allow tool file_path 'src/main/java/com/acme/env/EnvConfig.java'
expect block tool glob '**/*.pem'
expect_tool_json allow 'Edit .gitignore adding .env' '{"file_path":"C:\\\\work\\\\app\\\\.gitignore","old_string":"build/","new_string":"build/\\n.env\\n*.pem"}'
expect_tool_json block 'Grep over secrets dir' '{"pattern":"password","path":"src/main/resources/secrets","output_mode":"content"}'

echo "---"
if [ "$failures" -eq 0 ]; then echo "PASS  all checks"; else echo "FAILED  $failures check(s)"; fi
[ "$failures" -eq 0 ]

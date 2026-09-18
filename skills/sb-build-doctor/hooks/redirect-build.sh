#!/usr/bin/env bash
# Optional PreToolUse hook (Bash/PowerShell): turns away raw Gradle/Maven build and test runs, whose
# console output can cost thousands of tokens, and points Claude at scripts/build.sh instead.
# Informational commands (--version, tasks, dependencies, help) pass. Prefixing a command with
# BUILD_DOCTOR_RAW=1 bypasses the hook. Bash builtins only: it runs on every shell tool call.
IFS= read -r -d '' input || true

field='"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
[[ $input =~ $field ]] || exit 0
cmd="${BASH_REMATCH[1]}"

[[ $cmd == *build.sh* || $cmd == *trace.sh* || $cmd == *BUILD_DOCTOR_RAW=1* ]] && exit 0

launcher='(^|[;&|([:space:]])([^[:space:]]*[/\\])?(gradlew|gradle|mvnw|mvn)(\.bat|\.cmd)?([[:space:]]|$)'
[[ $cmd =~ $launcher ]] || exit 0

goal='[[:space:]:](test|build|check|verify|package|install|compile[A-Za-z]*|integrationTest|assemble)([[:space:]]|$)'
[[ $cmd =~ $goal ]] || exit 0

echo "[sb-build-doctor] Run builds and tests through the condensing wrapper instead; raw output wastes context:" >&2
echo "  bash .claude/skills/sb-build-doctor/scripts/build.sh <task> [args]" >&2
echo "  e.g. build.sh test --tests 'com.acme.order.*' (Gradle) / build.sh test -Dtest=OrderServiceTest (Maven)" >&2
echo "It prints compile errors, failed tests and trimmed stack traces, and saves the full log." >&2
echo "Only if the raw console is truly needed, prefix the command with BUILD_DOCTOR_RAW=1." >&2
exit 2

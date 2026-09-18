---
name: sb-build-doctor
description: Use this skill whenever you build, compile, or test a Spring Boot (Gradle or Maven) project, or diagnose why a build, test, or application startup fails. It runs the build through a wrapper that returns only compile errors, failed tests, and trimmed stack traces instead of thousands of lines of console output, condenses application logs, and stops repeated failed fix attempts. Triggers on "run the tests", "build it", "does it compile", "fix the failing tests", "the build is broken", "compile error", "test failure", "the app won't start", "APPLICATION FAILED TO START", "look at this stack trace", or any ./gradlew / mvn run.
---

# Build Doctor for Spring Boot

Raw Gradle/Maven output and Spring stack traces are mostly noise (progress lines, framework frames, repeated traces) and can cost thousands of tokens per run. The scripts here keep the signal and leave the noise in a log file.

`$S` = `.claude/skills/sb-build-doctor/scripts`. Run the scripts with the Bash tool (they need bash; Git Bash on Windows), from the project or module root.

## Running builds and tests

Always use `bash $S/build.sh <task> [args]` instead of calling `./gradlew`, `./mvnw`, `gradle`, or `mvn` directly. Arguments go to the build tool unchanged.

| Goal | Gradle | Maven |
|---|---|---|
| Compile only | `build.sh compileJava` (tests: `compileTestJava`) | `build.sh test-compile` |
| One test class | `build.sh test --tests 'com.acme.order.OrderServiceTest'` | `build.sh test -Dtest=OrderServiceTest` |
| One package | `build.sh test --tests 'com.acme.order.*'` | `build.sh test '-Dtest=com/acme/order/**'` |
| Full suite | `build.sh test` or `build.sh build` | `build.sh verify` |

- **Go from narrow to wide**: compile, then the affected test class, then the full suite once at the end. A full suite after every edit is the most expensive habit.
- Set the Bash tool timeout to 600000 for full builds; the first run can download dependencies.
- The report shows status, exit code, duration, test counts, then only what failed: compile errors with the source context, the build tool's failure summary, and each failed test with framework frames collapsed into `... N framework frame(s)`. A passing build prints three lines.

## Reading the result

- Act on the report. Don't re-run the build just to see more output.
- If you need more detail, grep the saved log with a specific pattern and a line limit, e.g. `grep -n -A 30 'OrderServiceTest' .claude/build-doctor/last-build.log | head -60`. Never `cat` the log or read it whole.
- `Tests: no new test reports` means Gradle considered the tests up-to-date or your filter matched nothing. Check the filter before assuming success. Add `--rerun` (Gradle 7.6+) to force a run.
- `## Last lines of the log` means no known error pattern matched. Read those lines, and grep the log if they are not enough.

## Application logs and stack traces

For a startup failure (`bootRun`, a jar that won't start) or a log file the user points to, run `bash $S/trace.sh <logfile>`, or pipe into it (`... 2>&1 | bash $S/trace.sh`). It prints the `APPLICATION FAILED TO START` report, distinct ERROR lines with counts, and distinct stack traces, condensed.

In a Spring trace the root cause is the **last** `Caused by:`. Fix that one; the outer `BeanCreationException`/`UnsatisfiedDependencyException` layers only show the path to it.

## Circuit breaker

When the same failure repeats 3 runs in a row within 10 minutes, `build.sh` prints `!! CIRCUIT BREAKER`. Then stop editing code and report to the user instead:

```
## Stuck: <one-line failure>
- Failure: <error / failing test, from the report>
- Tried: <each attempted fix and what happened>
- Hypotheses: <most likely causes, ranked>
- Need from you: <decision, information, or access that would unblock this>
```

Continue only after the user responds. The breaker resets on the next successful build. Apply the same rule to yourself when you notice you are repeating a fix that already failed.

## Optional: enforce it (setup)

Without enforcement Claude may still call `./gradlew` directly, for example when this skill wasn't loaded for a request. If the user wants the wrapper enforced, merge `templates/settings.build-doctor.json` into `.claude/settings.json` (shared) or `.claude/settings.local.json` (personal). Keep every existing key, hook, and rule; append and de-duplicate. The merge adds:

- `hooks/redirect-build.sh` as a `PreToolUse` hook for Bash/PowerShell. It turns away raw build and test runs with a pointer to `build.sh`, lets informational commands (`--version`, `tasks`, `dependencies`) through, and lets a command prefixed with `BUILD_DOCTOR_RAW=1` bypass it.
- allow rules so `build.sh` and `trace.sh` run without a permission prompt.

If `sb-security-guard` is active, its deny rules forbid you from editing `.claude/settings.json`. In that case print the merged JSON for the user to apply themselves. The change takes effect in new sessions.

## Known limits

- Error detection is pattern-based: javac, Kotlin, Maven compiler output, Gradle's `What went wrong`, JUnit XML reports (Gradle, Surefire, Failsafe), and Spring's startup report. Anything else falls back to the last 25 log lines.
- Test failures come from `TEST-*.xml` files written during this run. Frameworks that don't write JUnit XML only show up through the console fallback.
- The app/framework split uses package prefixes. A company library under an unlisted prefix counts as an app frame. Add its prefix to `is_framework` in `scripts/condense.awk` if it is noisy.
- On Korean Windows, javac may print CP949 text, which can appear garbled. Locations and structure stay readable.

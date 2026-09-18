---
name: sb-security-guard
description: Use this skill to make a project safe for company use of Claude Code — keeping internal business logic, secrets, credentials, personal data (PII), and confidential material from ever being sent to Claude. Sets up blocking hooks and permission deny rules driven by a per-company policy file, audits a project for violations, and verifies the guard works. Triggers on "/sb-security-guard", "security guard setup", "apply the company security policy", "check this project before rolling out Claude", "prevent secrets from being sent to Claude", or questions about what data may be given to Claude in this project.
---

# Security Guard for Claude Code

Keeps sensitive data out of Claude's context **by enforcement, not by asking nicely**. Instructions to the model can be ignored or bypassed; hooks and permission rules run in the harness before anything reaches the model.

| Layer | Mechanism | What it stops |
|---|---|---|
| Prompt guard | `UserPromptSubmit` hook → `hooks/prompt-guard.sh` | A prompt containing secrets, PII, or confidential keywords. The prompt is erased and **never sent**. |
| Tool guard | `PreToolUse` hook → `hooks/tool-guard.sh` | Any tool call (Read, Grep, Bash `cat`, ...) naming a protected path, so file contents never enter context. |
| Deny rules | `permissions.deny` in `.claude/settings.json` | Built-in file tools, `@file` mentions, and Grep/Glob results touching protected paths; edits to the guard itself. |
| Policy | `.claude/security-policy.conf` | The single source of rules above, owned by the security team. |

The policy has three sections: `[secret-patterns]` (ERE regexes), `[sensitive-keywords]` (fixed strings), `[protected-paths]` (gitignore globs). The bundled default lives in `policy/security-policy.conf`; the project copy overrides it.

Pick the mode from the user's request: `setup`, `audit`, or `verify`. With no clear mode, run `audit` first and offer `setup`.

**Rule for yourself in every mode:** never open, print, or quote the contents of a protected path or a line the scan flagged — not to "confirm" a finding, not with a different command. Work only from the locations the scripts print. If the user pastes something that looks sensitive and it got through, tell them and suggest adding a rule; don't repeat the value.

Paths below are relative to the project root. `$SKILL` = `.claude/skills/sb-security-guard`.

## Mode: setup

1. **Preconditions.** Confirm `$SKILL/hooks/prompt-guard.sh` exists (installed via this repo's install script) and `bash` is on PATH (Git Bash on Windows). If `.claude/settings.json` already contains the guard hooks, the deny rules forbid you from editing it and the policy — go to step 6 instead.
2. **Create the project policy.** If `.claude/security-policy.conf` doesn't exist, copy `$SKILL/policy/security-policy.conf` there. Never overwrite an existing one.
3. **Customize before locking.** Once step 4 lands, you can no longer edit the policy, so collect company-specific rules now. Ask the user (one question round) for:
   - internal packages/directories holding core business logic Claude must not read (e.g. `src/main/java/**/pricing/**`) → `[protected-paths]`
   - project code names, confidentiality labels, business terms that must not appear in prompts → `[sensitive-keywords]`
   - production config file names that differ from the defaults (e.g. `application-live.yml`) → `[protected-paths]`

   Skim the project layout (directory names only — `src/main/java` package tree, `src/main/resources` file names) to propose concrete candidates rather than asking in the abstract. Add the answers to the project policy.
4. **Write settings.** Merge `$SKILL/templates/settings.security.json` into `.claude/settings.json` (the shared, committed file — not `settings.local.json`, which each developer could drop):
   - Keep every existing key, allow rule, and hook. Append; de-duplicate.
   - Regenerate the protected-path deny rules from the project policy's `[protected-paths]`: for each glob `G`, one `Read(G)` and one `Edit(G)`. A glob without a leading `**/` or `/` must be written as `/G` so it anchors at the project root. Keep the three guard self-protection rules (`Edit(/.claude/settings.json)`, `Edit(/.claude/security-policy.conf)`, `Edit(/.claude/skills/sb-security-guard/**)`).
5. **Verify** (mode below), then tell the user the guard takes effect for new sessions — they should restart Claude Code — and that the policy and settings are now human-edited only.
6. **Re-sync after policy changes** (guard already active): don't try to edit the locked files or work around the deny rules. Print the regenerated `permissions.deny` array for the user to paste into `.claude/settings.json` themselves, then run `verify`.

## Mode: audit

Run each check, then produce the report below. Don't fix anything unasked.

1. **Guard wiring** — read `.claude/settings.json` (and note if the hooks exist only in `settings.local.json` or `~/.claude/settings.json`, which don't travel with the repo):
   - both hooks registered and pointing at existing scripts
   - `Read`/`Edit` deny rules present for every `[protected-paths]` glob in the project policy
   - self-protection deny rules present
   - project policy exists; `[sensitive-keywords]` / `[protected-paths]` contain company-specific entries beyond the defaults (if not, flag that business logic is unprotected)
2. **Repository scan** — run `CLAUDE_PROJECT_DIR="$PWD" bash $SKILL/hooks/scan-repo.sh`. It prints locations only; keep it that way. It reports protected files committed to git, secret/PII pattern hits, and confidential keyword hits.
3. **Supporting hygiene** — `.gitignore` covers `.env*`, key stores, and production config; secrets in `application*.yml` are externalized as `${ENV_VAR}` placeholders.

```
## Security Guard Audit

### 🔴 Critical — data can reach Claude today
- [location] Issue → Fix

### 🟠 High — guard gaps
- ...

### 🟡 Medium — hygiene
- ...

### ✅ In place
- ...
```

Critical: guard missing or not in shared settings, a protected file committed to git, a plaintext secret in a tracked file. High: a deny rule missing for a policy glob, no company-specific business-logic paths/keywords, self-protection missing. Medium: `.gitignore` gaps, noisy rules the team should tune.

## Mode: verify

Run `CLAUDE_PROJECT_DIR="$PWD" bash $SKILL/hooks/selftest.sh`. It checks that every rule compiles and that representative inputs are blocked or allowed. Report failures as-is. A failing default case after the security team intentionally removed that rule is expected — say so rather than "fixing" the policy. When the user reports a false positive/negative, suggest the exact rule change for them to apply.

## Known limits (tell the user during setup)

- The hooks fail closed when their policy or library is missing, but a hook that times out, or can't start because `bash` isn't on PATH, doesn't block. The scripts use only bash builtins to stay fast (~0.3 s per call).
- Path matching sees the text of a tool call, not what a program opens: `grep -r .`, a Gradle task, or a script that reads a protected file indirectly isn't caught. For OS-level enforcement enable Claude Code's sandbox; for org-wide enforcement that developers can't remove, distribute the hooks and deny rules via managed settings.
- Regex/keyword detection is best-effort: an unknown secret format or business logic pasted without a keyword gets through. The policy has to reflect what the company actually considers sensitive.
- Contents of files Claude is allowed to read are not scanned; keep sensitive logic under a protected path.

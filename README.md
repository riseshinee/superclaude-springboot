# superclaude-springboot

[한국어](./README.ko.md)

A set of **Spring Boot-specialized Claude Code Skills**, inspired by the persona/expert-command concept of the [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework). Install these into a project and Claude Code will automatically pick the right skill for code generation, architecture review, and performance diagnostics that follow Spring Boot conventions.

## Install

Run the install script with the path to your target Spring Boot project. It copies the skills into `<target>/.claude/skills/`.

```bash
# macOS / Linux / Git Bash
./install.sh /path/to/your-spring-boot-project
```

```powershell
# Windows PowerShell
./install.ps1 -TargetProject "C:\path\to\your-spring-boot-project"
```

If a skill with the same name already exists, you'll be asked whether to overwrite it. To install a single skill, you can also just copy the `skills/<skill-name>` folder directly into your project's `.claude/skills/` — each skill is self-contained and has no dependency on the others.

## Skills included

| Skill | Triggers on | What it does |
|---|---|---|
| `sb-scaffold` | "generate a controller", "create an entity", "scaffold a REST API" | Generates Controller/Service/Repository/Entity/DTO following layered-package conventions: constructor injection, DTO records, LAZY associations, etc. |
| `sb-architecture-review` | "review the architecture", "check the layer structure", PR review | Reviews dependency direction, DTO boundaries, exception handling, transaction boundaries, and test slices, ranked by severity |
| `sb-jpa-doctor` | "N+1 problem", "queries are slow", "review this JPA mapping" | Detects N+1 issues and prescribes fetch join/`@EntityGraph`/batch size fixes; flags association-mapping pitfalls and bulk-operation consistency issues |
| `sb-perf-ops` | "tune the production environment", "GC/memory issue", "connection pool" | Diagnoses HikariCP sizing, JVM/GC tuning, caching strategy, Actuator observability, and graceful shutdown |
| `sb-security-guard` | `/sb-security-guard setup\|audit\|verify`, "check this project before rolling out Claude" | Sets up hooks and deny rules that keep internal business logic, secrets, and personal data from being sent to Claude, and audits the project for violations |

## Usage

Once installed, no explicit invocation is needed — Claude Code automatically loads the matching skill when the conversation fits its description. To force a specific skill, just name it directly, e.g. "use sb-jpa-doctor to look at this repository."

## Company rollout security (`sb-security-guard`)

Instead of asking the model not to look at sensitive data, this skill **enforces it in the Claude Code harness**.

| Layer | What it does |
|---|---|
| Prompt guard (`UserPromptSubmit` hook) | Erases a prompt containing secret/PII patterns or confidential keywords — it is **never sent to the model** |
| Tool guard (`PreToolUse` hook) | Blocks Read/Grep/Bash/... calls that name a protected path, so file contents never enter context |
| Deny rules (`permissions.deny`) | Block built-in file tools and `@file` mentions on protected paths, and stop Claude from editing the guard itself |
| Policy (`.claude/security-policy.conf`) | Single source for the rules above: `[secret-patterns]` (regex), `[sensitive-keywords]`, `[protected-paths]` (globs), edited per company |

Rollout:

1. Install the skills with the install script.
2. In Claude Code, run `/sb-security-guard setup`. It copies the policy, asks for your core business-logic packages and internal keywords, then registers the hooks and deny rules in `.claude/settings.json`.
3. Restart Claude Code, then run `/sb-security-guard verify` to check what gets blocked and allowed.
4. Run `/sb-security-guard audit` to find protected files committed to git and plaintext secrets. The report shows locations only, never contents.
5. Commit `.claude/settings.json` and `.claude/security-policy.conf`. After setup, only people can edit them, so route changes through security review.

It only needs `bash` (Git Bash on Windows), with no jq, Node, or Python. The hooks use bash builtins only and take about 0.3 s per call.

Limits: path blocking is based on the text of a tool call, so it doesn't catch indirect reads such as `grep -r .` or a build script opening a file. For OS-level enforcement, add Claude Code's sandbox; for org-wide enforcement developers can't turn off, distribute the settings as managed settings.

## Roadmap

- Consider adding a test-generation/review skill (`sb-test-writer`)
- Once the skill set stabilizes, consider packaging it as a Claude Code plugin for marketplace distribution

## License

MIT — see [LICENSE](./LICENSE).

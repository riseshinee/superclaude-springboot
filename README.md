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

## Usage

Once installed, no explicit invocation is needed — Claude Code automatically loads the matching skill when the conversation fits its description. To force a specific skill, just name it directly, e.g. "use sb-jpa-doctor to look at this repository."

## Roadmap

- Consider adding a test-generation/review skill (`sb-test-writer`)
- Once the skill set stabilizes, consider packaging it as a Claude Code plugin for marketplace distribution

## License

MIT — see [LICENSE](./LICENSE).

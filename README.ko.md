# superclaude-springboot

[English](./README.md)

[SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework)의 페르소나·전문 커맨드 컨셉을 참고해, **Spring Boot 프로젝트 전용 Claude Code Skills**로 재구성한 모음입니다. 프로젝트에 설치해두면 Claude Code가 상황에 맞춰 자동으로 해당 스킬을 불러와 Spring Boot 컨벤션에 맞는 코드 생성, 아키텍처 리뷰, 성능 진단을 수행합니다.

## 설치

대상 Spring Boot 프로젝트 경로를 인자로 주고 설치 스크립트를 실행하면 `<target>/.claude/skills/`에 스킬이 복사됩니다.

```bash
# macOS / Linux / Git Bash
./install.sh /path/to/your-spring-boot-project
```

```powershell
# Windows PowerShell
./install.ps1 -TargetProject "C:\path\to\your-spring-boot-project"
```

이미 같은 이름의 스킬이 있으면 덮어쓸지 물어봅니다. 스킬 하나만 필요하면 `skills/<스킬명>` 폴더를 직접 대상 프로젝트의 `.claude/skills/`에 복사해도 됩니다 (각 스킬은 다른 스킬에 의존하지 않는 자기완결형입니다).

## 제공 스킬

| 스킬 | 트리거 상황 | 하는 일 |
|---|---|---|
| `sb-scaffold` | "컨트롤러 만들어줘", "엔티티 생성", "REST API 스캐폴딩" | 레이어드 패키지 구조에 맞춰 Controller/Service/Repository/Entity/DTO를 생성자 주입·DTO record·LAZY 연관관계 등 컨벤션에 맞게 생성 |
| `sb-architecture-review` | "아키텍처 리뷰해줘", "레이어 구조 봐줘", PR 리뷰 | 의존성 방향, DTO 경계, 예외 처리, 트랜잭션 경계, 테스트 슬라이스 등을 심각도별로 리뷰 |
| `sb-jpa-doctor` | "N+1 문제", "쿼리 느려요", "JPA 매핑 리뷰" | N+1 탐지 및 fetch join/`@EntityGraph`/batch size 처방, 연관관계 매핑 함정, 벌크 연산 정합성 진단 |
| `sb-perf-ops` | "운영 환경 튜닝", "GC/메모리 문제", "커넥션 풀" | HikariCP 사이징, JVM/GC 튜닝, 캐싱 전략, Actuator 관측성, graceful shutdown 진단 |

## 사용 방법

설치 후에는 별도 호출 없이, 대화 내용이 스킬 설명과 맞으면 Claude Code가 자동으로 해당 스킬을 불러옵니다. 특정 스킬을 명시적으로 쓰고 싶다면 이름을 직접 언급하면 됩니다. 예: "sb-jpa-doctor로 이 리포지토리 봐줘".

## 향후 계획

- 테스트 코드 생성/리뷰 스킬(`sb-test-writer`) 추가 검토
- 스킬 세트가 안정화되면 Claude Code 플러그인(마켓플레이스 배포) 형태로 확장 검토

## License

MIT — [LICENSE](./LICENSE) 참고.

---

> 참고: 스킬 본문(`skills/*/SKILL.md`)과 스크립트 메시지는 전역 배포를 위해 영어로 작성되어 있습니다. 이 파일은 저장소 개요를 위한 한글 번역본입니다.

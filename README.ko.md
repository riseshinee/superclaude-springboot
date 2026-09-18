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
| `sb-security-guard` | `/sb-security-guard setup\|audit\|verify`, "사내 도입 전 보안 점검" | 내부 비즈니스 로직·시크릿·개인정보가 Claude로 전송되지 않도록 hook과 deny 규칙을 설정하고, 프로젝트의 위반 사항을 점검 |
| `sb-build-doctor` | "테스트 돌려줘", "빌드가 깨졌어", "앱이 안 떠요", Gradle/Maven 실행 전반 | 빌드를 래퍼로 실행해 컴파일 에러·실패 테스트·축약된 스택 트레이스만 돌려주고(전체 로그는 파일로 보관), Spring 로그를 요약하며, 같은 실패가 반복되면 서킷 브레이커로 수정 시도를 멈춤 |

## 사용 방법

설치 후에는 별도 호출 없이, 대화 내용이 스킬 설명과 맞으면 Claude Code가 자동으로 해당 스킬을 불러옵니다. 특정 스킬을 명시적으로 쓰고 싶다면 이름을 직접 언급하면 됩니다. 예: "sb-jpa-doctor로 이 리포지토리 봐줘".

## 사내 도입 전 보안 설정 (`sb-security-guard`)

모델에게 "민감 정보를 읽지 마"라고 지시하는 대신, **Claude Code 하네스 단계에서 강제로 차단**합니다.

| 계층 | 동작 |
|---|---|
| 프롬프트 가드 (`UserPromptSubmit` hook) | 시크릿·개인정보 패턴이나 대외비 키워드가 들어간 프롬프트를 지우고, **모델로 전송하지 않음** |
| 도구 가드 (`PreToolUse` hook) | 보호 경로를 가리키는 Read/Grep/Bash 등의 도구 호출을 차단해 파일 내용이 컨텍스트에 들어가지 않게 함 |
| deny 규칙 (`permissions.deny`) | 보호 경로에 대한 기본 파일 도구와 `@파일` 언급을 차단하고, Claude가 가드 설정 자체를 수정하지 못하게 함 |
| 정책 파일 (`.claude/security-policy.conf`) | 위 규칙의 단일 출처. `[secret-patterns]`(정규식), `[sensitive-keywords]`(키워드), `[protected-paths]`(glob) 섹션으로 구성되며 회사별로 수정 |

도입 절차:

1. 설치 스크립트로 스킬을 설치합니다.
2. Claude Code에서 `/sb-security-guard setup`을 실행합니다. 정책 파일이 복사되고, 핵심 비즈니스 로직 패키지와 사내 키워드를 물어본 뒤 `.claude/settings.json`에 hook과 deny 규칙을 등록합니다.
3. Claude Code를 재시작하고 `/sb-security-guard verify`로 차단과 허용 동작을 확인합니다.
4. `/sb-security-guard audit`로 git에 커밋된 보호 파일이나 평문 시크릿이 있는지 점검합니다. 결과에는 위치만 표시되고 내용은 출력되지 않습니다.
5. `.claude/settings.json`과 `.claude/security-policy.conf`를 커밋합니다. 설정 이후 이 파일들은 사람만 수정할 수 있으니, 보안 담당자 리뷰를 거쳐 변경하세요.

요구 사항은 `bash`(Windows는 Git Bash)뿐이며, jq·Node·Python은 필요 없습니다. hook은 bash 내장 기능만 써서 호출당 약 0.3초가 걸립니다.

한계: 경로 차단은 도구 호출의 텍스트를 기준으로 합니다. 따라서 `grep -r .`이나 빌드 스크립트처럼 파일을 간접적으로 읽는 경우는 막지 못합니다. OS 수준 차단이 필요하면 Claude Code 샌드박스를, 개발자가 끌 수 없는 조직 단위 강제가 필요하면 managed settings 배포를 함께 사용하세요.

## 토큰 절감 빌드 (`sb-build-doctor`)

Gradle/Maven 원본 출력과 Spring 스택 트레이스는 대부분 진행 로그와 프레임워크 프레임입니다. 테스트 한 번에 수십 KB가 Claude 컨텍스트에 들어갈 수 있습니다. `sb-build-doctor`는 조치에 필요한 부분만 남깁니다.

| 스크립트 | 반환 내용 |
|---|---|
| `scripts/build.sh <task> [args]` | 상태, 테스트 수, 소스 위치가 포함된 컴파일 에러, 빌드 도구의 실패 요약, 실패한 테스트(JUnit XML 기반, 프레임워크 프레임 축약). 성공하면 3줄만 출력합니다. 전체 로그는 `.claude/build-doctor/last-build.log`에 저장됩니다. |
| `scripts/trace.sh <log>` | 애플리케이션 로그용. `APPLICATION FAILED TO START` 리포트, 중복 제거된 ERROR 줄과 횟수, 중복 제거·축약된 스택 트레이스를 보여줍니다. |

같은 실패가 10분 안에 3번 연속 나오면 `build.sh`가 서킷 브레이커를 작동시킵니다. Claude는 수정을 멈추고, 같은 시도를 반복하는 대신 시도한 내용을 보고합니다. 샘플 Spring Boot 프로젝트에서 실패한 `mvn test` 로그 43KB가 약 2.5KB로 줄었고, 모든 실패와 근본 원인은 그대로 남았습니다.

래퍼 사용을 강제하려면 `templates/settings.build-doctor.json`을 `.claude/settings.json`에 병합하세요. 원본 `./gradlew test`/`mvn verify` 실행을 막고 `build.sh`로 안내하는 hook과, 스크립트를 권한 확인 없이 실행하는 allow 규칙이 추가됩니다.

## 향후 계획

- 테스트 코드 생성/리뷰 스킬(`sb-test-writer`) 추가 검토
- 스킬 세트가 안정화되면 Claude Code 플러그인(마켓플레이스 배포) 형태로 확장 검토

## License

MIT — [LICENSE](./LICENSE) 참고.

---

> 참고: 스킬 본문(`skills/*/SKILL.md`)과 스크립트 메시지는 전역 배포를 위해 영어로 작성되어 있습니다. 이 파일은 저장소 개요를 위한 한글 번역본입니다.

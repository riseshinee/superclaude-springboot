---
name: sb-architecture-review
description: Use this skill when reviewing Spring Boot code for architecture and layering quality — dependency direction between Controller/Service/Repository, DTO boundary leaks, DI style, exception handling consistency, transaction boundaries, or test slice usage. Triggers on "review the architecture", "check the layer structure", "how is this design", "review this PR", or requests to critique the structure/quality of existing Spring Boot code.
---

# Spring Boot Architecture Reviewer

Review Spring Boot code (or a diff) against the checklist below, and **report findings ranked by severity**. Don't modify code on your own initiative — present the review first, and apply fixes only if the user asks.

## Review checklist

### 1. Dependency direction (Critical)
- Does the flow always go one-way: `Controller → Service → Repository`?
- No reverse dependency where a Repository references a Service, or an Entity references a Repository/Service?
- Does the Controller ever call a Repository directly, skipping the Service layer?
- Any circular references between Services (A injects B, B injects A)?

### 2. Separation of concerns (High)
- Is business logic (conditionals, calculations, state transitions) leaking into the Controller? Controllers should only validate the request and delegate.
- Is all business logic pushed into procedural Service code while Entities become an anemic domain model — are at least the core invariants enforced inside the Entity?
- Does a single Service class span multiple aggregates/transaction boundaries and take on too many responsibilities?

### 3. API boundaries (Critical)
- Is an Entity ever exposed directly as a `@RequestBody`/`@ResponseBody`/response object? (risks: JPA proxy serialization, lazy-loading exceptions, tight coupling between the API and DB schema)
- Is Bean Validation missing on Request DTOs?
- Does a list endpoint that should paginate instead return unbounded results?

### 4. Dependency injection style (Medium)
- Is `@Autowired` field injection used anywhere? → unify on constructor injection (`@RequiredArgsConstructor` + `private final`).
- If a circular dependency is worked around with `@Lazy`, flag it as a sign of a design flaw.

### 5. Exception handling consistency (High)
- Is there a domain exception hierarchy, or is a raw `RuntimeException` thrown directly?
- Does the Controller build status codes manually with try-catch instead of centralizing via `@RestControllerAdvice`/`@ExceptionHandler`?
- Do exception messages leak internal details (SQL, stack traces) into client responses?

### 6. Transaction boundaries (Critical)
- Do write-operation methods have `@Transactional`?
- Does the code follow the pattern of class-level `@Transactional(readOnly = true)` plus `@Transactional` overrides on write methods?
- Any self-invocation problem — calling a `@Transactional` method from within the same class (`this.method()`), which bypasses the proxy?
- Does an external call (HTTP, messaging) happen inside a `@Transactional` block, unnecessarily extending the transaction?
- Does a `@Transactional` method throw a checked exception without `rollbackFor`, so the rollback silently doesn't happen (only unchecked exceptions roll back by default)?

### 7. Test structure (Medium)
- Is `@SpringBootTest` (full context load) overused for simple validation logic?
- Are test slices used appropriately — `@DataJpaTest` for Repositories, `@WebMvcTest` + mocked Service for Controllers?
- Does a test depend on an actual commit while `@Transactional` rollback masks the failure?

## Report format

```
## Architecture Review Results

### 🔴 Critical
- [file:line] Issue description → Recommended fix

### 🟠 High
- ...

### 🟡 Medium
- ...

### ✅ Done well
- ...
```

Don't list items with no issues — keep the report concise and focused on actual findings. When severity is ambiguous, add one line explaining why it matters and the concrete scenario where it breaks.

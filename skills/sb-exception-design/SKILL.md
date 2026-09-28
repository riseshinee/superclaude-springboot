---
name: sb-exception-design
description: Use this skill when designing or fixing error handling in a Spring Boot REST API — the business exception hierarchy, error codes, @RestControllerAdvice global handler, the error response format (ProblemDetail / RFC 9457 or a custom body), validation error responses, and error logging levels. Triggers on "design exception handling", "unify error responses", "add an error code", "global exception handler", "ProblemDetail", "validation error format", "why does this return 500", "the error response leaks a stack trace", or when adding a new exception to an existing API.
---

# Spring Boot Exception & Error Response Design

Make every failure leave the API in **one predictable shape**, with a status code that matches the cause and nothing internal leaked. If the project already has an error response format that clients depend on, **keep the format** and fix the plumbing behind it; changing a public error contract is a breaking change and needs the user's decision.

## Step 1 — Survey what exists

- Find every `@RestControllerAdvice`/`@ControllerAdvice` and `@ExceptionHandler`. More than one global advice without `@Order` means handler selection is arbitrary.
- List custom exceptions and where they're thrown. Note raw `RuntimeException`/`IllegalStateException` thrown from business code, and try-catch blocks in Controllers that build a `ResponseEntity`.
- Check `spring.mvc.problemdetails.enabled` and whether the advice extends `ResponseEntityExceptionHandler`.
- Check `server.error.include-stacktrace`, `include-message`, `include-binding-errors` — none should be `always` in production.

## Design

### Exception hierarchy
One base unchecked exception carrying an error code; domain exceptions extend it. Callers catch nothing — the global handler maps it.

```java
public enum ErrorCode {
    ORDER_NOT_FOUND(HttpStatus.NOT_FOUND, "ORDER-001", "Order not found"),
    ORDER_ALREADY_PAID(HttpStatus.CONFLICT, "ORDER-002", "Order is already paid"),
    MEMBER_NOT_FOUND(HttpStatus.NOT_FOUND, "MEMBER-001", "Member not found"),
    INVALID_INPUT(HttpStatus.BAD_REQUEST, "COMMON-001", "Invalid input"),
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "COMMON-999", "Internal server error");

    private final HttpStatus status;
    private final String code;
    private final String message;
    // constructor + getters
}

public class BusinessException extends RuntimeException {
    private final ErrorCode errorCode;

    public BusinessException(ErrorCode errorCode, String detail) {
        super(detail);
        this.errorCode = errorCode;
    }

    public ErrorCode getErrorCode() { return errorCode; }
}

public class OrderNotFoundException extends BusinessException {
    public OrderNotFoundException(Long id) {
        super(ErrorCode.ORDER_NOT_FOUND, "Order not found. id=" + id);
    }
}
```

- Split the enum per domain (`OrderErrorCode implements ErrorCode` interface) once it passes ~30 entries.
- The `code` is the client contract: stable, never reused, documented. The message may change.
- Keep exceptions **unchecked**. Checked business exceptions don't roll back `@Transactional` by default and leak into every signature.
- Don't create an exception class per error code unless callers or tests need to tell them apart; `new BusinessException(ErrorCode.ORDER_ALREADY_PAID, ...)` is fine.

### Status code mapping
| Situation | Status |
|---|---|
| Malformed JSON, type mismatch, Bean Validation failure | 400 |
| Not authenticated / not allowed | 401 / 403 (let Spring Security produce these) |
| Resource doesn't exist | 404 |
| State conflict: duplicate, already processed, optimistic lock failure | 409 |
| Well-formed but violates a business rule | 422 or 400 — pick one project-wide and stick to it |
| Downstream timeout / unavailable | 502 / 503 / 504 |
| Anything unexpected | 500, generic message only |

### Response format
For a new API, use **`ProblemDetail`** (Spring 6 / Boot 3, RFC 9457) and add `code` (and `errors` for validation) as extension properties:

```json
{
  "type": "about:blank",
  "title": "Not Found",
  "status": 404,
  "detail": "Order not found. id=42",
  "instance": "/api/orders/42",
  "code": "ORDER-001"
}
```

If the project already returns a custom body (e.g. `ErrorResponse(code, message)`), keep that shape and apply every other rule here to it.

### Global handler
Extend `ResponseEntityExceptionHandler` so Spring MVC's own exceptions (malformed JSON, unsupported media type, missing parameter, 405, ...) come out in the same format instead of the default error page.

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(BusinessException.class)
    public ProblemDetail handleBusiness(BusinessException e) {
        ErrorCode errorCode = e.getErrorCode();
        log.warn("Business exception: code={}, detail={}", errorCode.getCode(), e.getMessage());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(errorCode.getStatus(), e.getMessage());
        problem.setProperty("code", errorCode.getCode());
        return problem;
    }

    @Override
    protected ResponseEntity<Object> handleMethodArgumentNotValid(
            MethodArgumentNotValidException e, HttpHeaders headers, HttpStatusCode status, WebRequest request) {
        List<Map<String, Object>> errors = e.getBindingResult().getFieldErrors().stream()
            .map(fe -> Map.<String, Object>of(
                "field", fe.getField(),
                "message", Objects.requireNonNullElse(fe.getDefaultMessage(), "invalid")))
            .toList();
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, ErrorCode.INVALID_INPUT.getMessage());
        problem.setProperty("code", ErrorCode.INVALID_INPUT.getCode());
        problem.setProperty("errors", errors);
        return ResponseEntity.status(status).body(problem);
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail handleUnexpected(Exception e) {
        log.error("Unhandled exception", e);
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.INTERNAL_SERVER_ERROR, ErrorCode.INTERNAL_ERROR.getMessage());
        problem.setProperty("code", ErrorCode.INTERNAL_ERROR.getCode());
        return problem;
    }
}
```

Also cover, when relevant:
- `HandlerMethodValidationException` (Boot 3.2+) — `@Validated` constraints on `@RequestParam`/`@PathVariable`; override `handleHandlerMethodValidationException` with the same `errors` shape.
- `ConstraintViolationException` from Service-level method validation → 400.
- `ObjectOptimisticLockingFailureException`, `DataIntegrityViolationException` (unique key) → 409 with a generic message; never echo the SQL or constraint name.
- `AccessDeniedException`/`AuthenticationException` thrown inside a controller reach the advice before Spring Security's entry point — rethrow them or map to 403/401 explicitly so a catch-all `Exception` handler doesn't turn them into 500.

### Logging rules
- 4xx: `warn` (or `info`) with code and detail, **no stack trace** — these are client mistakes and flood logs otherwise.
- 5xx: `error` **with** stack trace, exactly once, in the handler. Don't log-and-rethrow in Services.
- Never log request bodies that may carry personal data or credentials.
- Include a trace id (MDC / Micrometer tracing) in the log line; optionally return it as a `traceId` property so users can quote it to support.

## Anti-patterns to flag

- try-catch in a Controller that builds the error `ResponseEntity`
- `catch (Exception e) { return null; }` or swallowing and continuing in a Service
- `e.getMessage()` of a non-business exception (SQL, NPE, library errors) returned to the client
- Throwing `ResponseStatusException` deep inside domain/Service code (ties the domain to HTTP)
- 200 OK with `{"success": false}` bodies
- Several global advices competing without `@Order` / `basePackages`

## Verification

Add or update `@WebMvcTest` cases (see `sb-test-writer` if installed) asserting status, `$.code`, and for validation `$.errors[0].field`, for: one business exception, one validation failure, malformed JSON, and an unexpected exception (mock the Service to throw `RuntimeException` and assert the body contains no internal message).

## Output checklist

- [ ] One global advice, extending `ResponseEntityExceptionHandler`
- [ ] Every failure path returns the same body shape with a stable `code`
- [ ] Status codes match the table; no 500 for client errors
- [ ] No internal messages or stack traces in responses
- [ ] 4xx logged without stack trace, 5xx logged once with it
- [ ] Error contract changes flagged to the user as breaking, if any

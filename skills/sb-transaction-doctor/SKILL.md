---
name: sb-transaction-doctor
description: Use this skill when diagnosing Spring transaction behavior in a Spring Boot project — @Transactional not taking effect, a rollback that doesn't happen (or happens unexpectedly), UnexpectedRollbackException, LazyInitializationException, propagation choices (REQUIRES_NEW, NESTED), readOnly semantics, transaction-bound events (@TransactionalEventListener), @Async with transactions, external calls inside a transaction, or connection pool exhaustion caused by transactions. Triggers on "@Transactional doesn't work", "it didn't roll back", "rollback-only", "UnexpectedRollbackException", "LazyInitializationException", "should this be REQUIRES_NEW", "transaction boundary", "the event fires before commit", or "the data isn't saved".
---

# Spring Transaction Diagnostics

Find why a transaction behaves differently from what the code seems to say, and prescribe the smallest fix. Almost every case comes down to one of: **the proxy was bypassed**, **the exception didn't trigger rollback**, **work ran outside the transaction or the wrong one**, or **the transaction was held too long**.

## Step 1 — Gather facts before guessing

- The exact symptom: what was expected to be saved/rolled back, and what actually happened. Get the exception and stack trace if there is one (use `sb-build-doctor`'s `trace.sh` on long logs if installed).
- The full call path from the entry point (Controller, listener, scheduler, consumer) to the write, including **which class** each method lives in.
- `@Transactional` import: `org.springframework.transaction.annotation.Transactional` vs `jakarta.transaction.Transactional` — both work, but only Spring's has `readOnly`/`propagation`/`rollbackFor` with Spring semantics. Flag mixed use.
- Number of DataSources / `TransactionManager` beans, `spring.jpa.open-in-view`, and any custom `@EnableTransactionManagement` settings.
- To confirm at runtime, enable `logging.level.org.springframework.transaction.interceptor=TRACE` (shows "Getting transaction for [...]" / "Completing transaction") and `org.springframework.orm.jpa.JpaTransactionManager=DEBUG`. `TransactionSynchronizationManager.isActualTransactionActive()` in a breakpoint answers "am I in a transaction here?".

## Diagnosis by symptom

### "@Transactional has no effect"
| Cause | How to spot it | Fix |
|---|---|---|
| **Self-invocation** | `this.save()` or a plain call to a `@Transactional` method in the same class | Move the transactional method into another bean, or put `@Transactional` on the outer public entry method |
| `private` method | Annotation on a private method (never intercepted) | Make the entry point the annotated method; don't annotate private helpers |
| `final` method / class | CGLIB can't override it (common with Kotlin without the `allopen`/`spring` plugin) | Remove `final` / add the plugin |
| Object not a Spring bean | Created with `new`, or called before the proxy exists (`@PostConstruct`) | Inject it; move startup work to `ApplicationRunner` / `@EventListener(ApplicationReadyEvent.class)` |
| Wrong transaction manager | Several DataSources; the write goes to DB B while the default manager is for DB A | `@Transactional(transactionManager = "bTransactionManager")` |
| Work on another thread | `@Async`, `CompletableFuture`, parallel stream, executor inside the method | The new thread has **no** transaction; make the async method itself `@Transactional` and pass IDs, not entities |

### "It didn't roll back"
- **Checked exception**: by default only `RuntimeException` and `Error` roll back. Either make the business exception unchecked, or add `rollbackFor = Exception.class`. (Spring 6.2 can make this global via `@EnableTransactionManagement(rollbackOn = RollbackOn.ALL_EXCEPTIONS)` — only if the team agrees.)
- **Exception caught inside the transaction** and not rethrown — the method returns normally, so it commits.
- **The write happened in a different transaction**: `REQUIRES_NEW` inner method, a `@TransactionalEventListener`, or an async call committed independently.
- **Non-transactional resource**: MyISAM tables, a file write, an HTTP call, a message already sent — none of these roll back with the DB.

### "It rolled back even though I caught the exception" (`UnexpectedRollbackException`)
An inner `@Transactional` method (default `REQUIRED`, so the **same** transaction) threw a runtime exception, which marked the whole transaction rollback-only. Catching it in the outer method doesn't clear that mark, so the commit fails.
- If the inner failure should be tolerated: don't make the inner method transactional-and-throwing; validate first, or return a result instead of throwing.
- If the inner work must commit or fail on its own: `REQUIRES_NEW` (separate connection — see pool warning below).
- Use `noRollbackFor` only for an exception that genuinely leaves state consistent.

### `LazyInitializationException`
A LAZY association was touched after the persistence context closed — typically DTO mapping in the Controller, JSON serialization of an entity, or an async/event handler.
- Fetch what's needed inside the Service transaction (fetch join / `@EntityGraph`; see `sb-jpa-doctor`) and return DTOs.
- Don't "fix" it with `FetchType.EAGER`, `hibernate.enable_lazy_load_no_trans`, or by turning Open Session in View on.
- If `spring.jpa.open-in-view` is `true` (Boot's default, with a startup warning), lazy loading works in controllers but holds a DB connection for the whole request. Recommend `false` for APIs, and fix the resulting exceptions at the Service layer.

### "Saved data isn't visible" / "the event fired before commit"
- A plain `@EventListener` or a message sent inside the transaction runs **before commit**; a consumer may read data that isn't committed yet or that later rolls back. Use `@TransactionalEventListener` (default `AFTER_COMMIT`), or the Outbox pattern for messages that must not be lost.
- In an `AFTER_COMMIT` listener the original transaction is finished; DB writes there need their own transaction. Since Spring 6.1, a `@Transactional` listener method must use `REQUIRES_NEW` (or `NOT_SUPPORTED`) or startup fails.
- `AFTER_COMMIT` listeners don't run if there was no transaction at all — unless `fallbackExecution = true`.

### Connection pool exhaustion / long transactions
- **External calls inside a transaction** (HTTP, messaging, file I/O, `Thread.sleep`, waiting on locks) hold a DB connection for the call's full duration. Move them outside: read → call → short write transaction, or do the write then call after commit.
- **`REQUIRES_NEW` under load**: each level holds its own connection while the outer one waits. With pool size N and N concurrent outer transactions, every thread waits for a second connection that never frees — a deadlock that looks like `Connection is not available, request timed out`. Keep `REQUIRES_NEW` rare, or size the pool for it (see `sb-perf-ops`).
- Class-level `@Transactional` on a Controller or a facade that also does slow work.

## Propagation and `readOnly` quick guide

| Setting | Use it for | Watch out |
|---|---|---|
| `REQUIRED` (default) | Almost everything | Inner failure dooms the whole transaction |
| `REQUIRES_NEW` | Audit logs / failure records that must persist even when the caller rolls back | Extra connection; its commit isn't undone by the outer rollback |
| `NESTED` | Savepoint-based partial rollback with JDBC/`DataSourceTransactionManager` | Savepoints aren't supported through the JPA/Hibernate dialect (`NestedTransactionNotSupportedException`) |
| `MANDATORY` | Methods that must never start their own transaction | Throws if called without one — useful as an assertion |
| `readOnly = true` | Queries. With Hibernate it skips dirty checking and snapshots, and can route to a replica with a routing DataSource | Writes inside are silently not flushed — no error, just no update |

Pattern: class-level `@Transactional(readOnly = true)`, and `@Transactional` on write methods only.

## Tests that hide transaction bugs

- A `@Transactional` test wraps the code in an outer transaction, so self-invocation, missing `@Transactional`, `LazyInitializationException`, and `REQUIRES_NEW` behavior all look fine in tests. To test a real boundary, use `@SpringBootTest` **without** `@Transactional` on the test and clean up explicitly (or use `TransactionTemplate` in the test).
- Rollback-at-end tests never flush: call `flush()` to surface constraint violations.

## Diagnostic report format

```
## Transaction Diagnosis

### Symptom
What was expected vs. what happened.

### Root cause
[Class#method:line] Why the transaction behaved this way (one cause, with evidence from code or TRACE logs).

### Fix
Minimal code change, and why it's the smallest one that works.

### How to verify
The test (not wrapped in @Transactional) or log line that proves it.

### Related risks found
- ...
```

Report the root cause you verified; if the evidence supports more than one cause, say what would tell them apart instead of guessing.

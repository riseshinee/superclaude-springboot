---
name: sb-jpa-doctor
description: Use this skill when diagnosing JPA/Hibernate data-layer issues in a Spring Boot project — N+1 query problems, slow queries, entity mapping/fetch-strategy review, cascade or orphan-removal pitfalls, or persistence-context inconsistencies after bulk updates. Triggers on "N+1 problem", "queries are slow", "review this JPA mapping", "persistence context", "fetch join", "@EntityGraph" or similar Hibernate/JPA performance questions.
---

# JPA/Hibernate Data-Layer Diagnostics

Diagnose performance and consistency issues in code using Spring Data JPA / Hibernate, and prescribe a concrete fix.

## N+1 problems

### Detection patterns
- A `@OneToMany`/`@ManyToMany` collection accessed inside a loop (`for`, `stream().map()`) — if the collection is LAZY, each element triggers an extra query.
- A `@ManyToOne` left EAGER and used in a list-fetching endpoint — the associated entity is queried once per item in the list.
- DTO conversion code that walks an association (`entity.getAssociation().getField()`) inside list-processing logic.

### Fixes (by situation)
- **Single-item fetch + one or two associations**: use `@EntityGraph(attributePaths = {"member", "items"})` on the Repository method.
- **List fetch + a to-one association**: use a JPQL `fetch join` to load it in one query (`select o from Order o join fetch o.member`).
- **List fetch + a to-many association (collection fetch join)**: combining pagination with a collection fetch join triggers Hibernate's in-memory pagination warning (`HHH000104`). Instead, set `default_batch_fetch_size` (e.g. 100) to resolve it via batched `IN` queries, or fetch the collection with a separate query.
- **Complex read-model screens**: don't reuse the entity graph at all — use a JPQL constructor expression (`new` projection) or QueryDSL to fetch only the needed columns as a DTO projection.

### How to verify
- Set `spring.jpa.properties.hibernate.generate_statistics: true` plus `org.hibernate.stat: debug` logging in `application.yml` to see the query count.
- In local/test environments, use `p6spy` or `spring.jpa.show-sql: true` with `format_sql: true` to count the actual queries fired.
- Add a regression test that seeds 10+ rows, calls the API, and asserts the query count — recommended over relying on manual inspection.

## Association mapping review

- **Owning side**: the `@ManyToOne` side holds the FK, so it must be the owner. Check that `@OneToMany(mappedBy = ...)` is on the inverse side — a common mistake is `save`-ing from the non-owning side and the FK never updating.
- **Bidirectional convenience methods**: is there a helper (`addItem`) that sets both sides of a bidirectional association together? Setting only one side desyncs the persistence context's first-level cache from actual state.
- **Default fetch types**: `@OneToMany`/`@ManyToMany` default to LAZY, while `@ManyToOne`/`@OneToOne` default to **EAGER** — confirm LAZY is set explicitly where intended.
- **cascade**: is `CascadeType.ALL` applied out of habit? Especially on `@ManyToMany` or a reference-only association, `ALL` can unintentionally delete/modify the associated entity. Reserve `cascade = ALL, orphanRemoval = true` for relationships where the aggregate root clearly owns the child (e.g., Order-OrderItem).
- **`@OneToOne` LAZY pitfall**: only the FK-holding (owning) side can actually get a lazy proxy. On the non-owning side, Hibernate eagerly fetches regardless of the LAZY setting.

## Persistence context / bulk operations

- A `@Modifying` bulk UPDATE/DELETE bypasses the persistence context and writes directly to the DB, so subsequently reading the same entity in the same transaction can return a **stale first-level-cache value**. Use `@Modifying(clearAutomatically = true)` to clear the persistence context, or re-fetch the entity after the bulk operation.
- Reading right after `saveAll` may not reflect the latest state due to flush timing — remember that `save` issues the actual query only at flush/commit time.
- For large-scale data processing (tens of thousands of rows or more), suggest `JdbcTemplate` batch operations or a dedicated batch framework instead of the JPA entity approach.

## Diagnostic report format

```
## JPA Diagnostic Results

### Issues found
1. [Class/Method] N+1 occurring at: ... → Fix: fetch join / @EntityGraph / batch_fetch_size
2. [Class] Risky cascade setting: ...

### Recommended actions (in priority order)
1. ...
2. ...
```

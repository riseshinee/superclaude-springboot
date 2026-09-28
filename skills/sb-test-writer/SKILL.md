---
name: sb-test-writer
description: Use this skill when writing or reviewing tests for a Spring Boot (Java) project — unit tests for Services and domain logic, @WebMvcTest controller tests, @DataJpaTest repository tests, Testcontainers-backed integration tests, or test fixtures and data builders. Triggers on "write tests", "add a test for this", "increase test coverage", "test this controller/service/repository", "this test is flaky", "tests are slow", "review these tests", or right after new Spring Boot code has been generated and needs tests.
---

# Spring Boot Test Writer

Write tests that pin down behavior with the **smallest Spring context that can prove it**. If the project already has test conventions (base classes, fixture factories, naming, AssertJ vs Hamcrest, JUnit 4 vs 5), **follow them** over the defaults below.

## Step 1 — Read the project before writing

- Spring Boot version (`build.gradle(.kts)` / `pom.xml`): decides `@MockitoBean` (Boot 3.4+) vs `@MockBean` (deprecated since 3.4), and `@ServiceConnection` (3.1+).
- Test dependencies already present: Testcontainers, AssertJ, Spring Security Test, REST Docs, ArchUnit. Don't add a dependency without telling the user.
- Existing tests: copy their package layout, naming, and fixture style. Check for an abstract integration-test base class and reuse it.
- Which DB the production code targets. Native queries or DB-specific features mean H2 tests prove little — prefer Testcontainers.

## Step 2 — Pick the test type

| What's under test | Test type | Context |
|---|---|---|
| Domain logic in an Entity/value object, pure calculations | Plain JUnit | None |
| Service orchestration (branches, exceptions, calls to collaborators) | Mockito unit test (`@ExtendWith(MockitoExtension.class)`) | None |
| Request mapping, validation, status codes, JSON shape, error responses | `@WebMvcTest(XxxController.class)` + mocked Service | MVC slice |
| Custom queries, `@Query`, `@EntityGraph`, mappings, constraints | `@DataJpaTest` (+ Testcontainers if DB-specific) | JPA slice |
| JSON (de)serialization of a DTO | `@JsonTest` | Jackson slice |
| A full use case across layers, transactions, security filter chain | `@SpringBootTest` + Testcontainers | Full |

Default to the cheapest row that covers the behavior. `@SpringBootTest` is for a few end-to-end flows, not for every Service method.

## Rules

- **One behavior per test**, named for the behavior: `create_throwsWhenMemberMissing()` or `@DisplayName("회원이 없으면 주문 생성에 실패한다")`. Structure the body as given / when / then.
- **Assert outcomes, not implementation.** Prefer asserting the returned value, persisted state, or response body over `verify(...)` of every collaborator call. Use `verify` only when the call itself is the behavior (e.g. an event was published, an email was sent).
- **Use AssertJ**: `assertThat(...)`, `assertThatThrownBy(...)`/`assertThatExceptionOfType(...)`, `extracting(...)`.
- **Cover the unhappy paths**: not found, validation failure (each constraint that matters), duplicate/conflict, unauthorized. These are where regressions hide.
- **Test data through fixtures**, not 15-line constructors repeated in every test. Add a `XxxFixture` class with static factory methods (`OrderFixture.order()`, `OrderFixture.orderOf(member)`), or reuse the Entity's own factory method.
- **Don't test the framework**: no tests for getters, Lombok, `JpaRepository.save/findById` with no custom logic, or Spring's own validation annotations in isolation.
- **Keep the context cache warm**: every distinct combination of `@MockitoBean`s, properties, and profiles creates a new Spring context. Put shared integration-test setup in one abstract base class instead of varying it per test.
- **Mind `@Transactional` in tests**: `@DataJpaTest` and `@Transactional` tests roll back and may never flush, hiding constraint violations and `LazyInitializationException`. Call `em.flush(); em.clear();` before asserting on persisted state, and don't put `@Transactional` on `@SpringBootTest` tests that are meant to exercise the real transaction boundary.
- **No `Thread.sleep`** for async code — use Awaitility (`await().atMost(...)`).

## Templates

### Service unit test
```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock OrderRepository orderRepository;
    @Mock MemberRepository memberRepository;
    @InjectMocks OrderService orderService;

    @Test
    void create_savesOrderForMember() {
        Member member = MemberFixture.member();
        given(memberRepository.findById(1L)).willReturn(Optional.of(member));
        given(orderRepository.save(any(Order.class))).willAnswer(inv -> inv.getArgument(0));

        OrderResponse response = orderService.create(new CreateOrderRequest("book", 1L));

        assertThat(response.productName()).isEqualTo("book");
    }

    @Test
    void create_throwsWhenMemberMissing() {
        given(memberRepository.findById(1L)).willReturn(Optional.empty());

        assertThatThrownBy(() -> orderService.create(new CreateOrderRequest("book", 1L)))
            .isInstanceOf(MemberNotFoundException.class);
    }
}
```

### Controller slice test
```java
@WebMvcTest(OrderController.class)
class OrderControllerTest {

    @Autowired MockMvc mockMvc;
    @MockitoBean OrderService orderService;   // Boot < 3.4: @MockBean

    @Test
    void create_returns201() throws Exception {
        given(orderService.create(any())).willReturn(new OrderResponse(1L, "book", "kim"));

        mockMvc.perform(post("/api/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"productName": "book", "memberId": 1}
                    """))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.id").value(1));
    }

    @Test
    void create_returns400WhenProductNameBlank() throws Exception {
        mockMvc.perform(post("/api/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"productName": "", "memberId": 1}
                    """))
            .andExpect(status().isBadRequest());

        then(orderService).shouldHaveNoInteractions();
    }
}
```

If Spring Security is on the classpath, the slice loads the security filter chain: add `@WithMockUser` and `.with(csrf())` for state-changing requests, or import the project's security config.

### Repository slice test (Testcontainers)
```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class OrderRepositoryTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired OrderRepository orderRepository;
    @Autowired TestEntityManager em;

    @Test
    void findWithMemberById_loadsMemberInSameQuery() {
        Member member = em.persist(MemberFixture.member());
        Order order = em.persist(OrderFixture.orderOf(member));
        em.flush();
        em.clear();

        Order found = orderRepository.findWithMemberById(order.getId()).orElseThrow();

        assertThat(Hibernate.isInitialized(found.getMember())).isTrue();
    }
}
```

Match the container image to the production DB and version. When several test classes need the container, move it into a shared base class or a `@TestConfiguration` with a `@Bean @ServiceConnection` so it starts once.

### Query-count regression test (for N+1 fixes)
Enable `spring.jpa.properties.hibernate.generate_statistics=true` for the test, seed 10+ rows, call the method, then assert on `entityManagerFactory.unwrap(SessionFactory.class).getStatistics().getPrepareStatementCount()`.

## Running the tests

If `sb-build-doctor` is installed, run tests through its `build.sh` (e.g. `build.sh test --tests OrderServiceTest`) so only failures come back. Otherwise run just the new test classes first, then the full suite. Don't report tests as passing unless they were actually run.

## Reviewing existing tests

When asked to review tests, report by severity:
- **Critical**: tests that can't fail (no assertions, assertions inside a swallowed `catch`, asserting on the mock's own stub), tests that pass only because rollback hides a flush error.
- **High**: missing unhappy paths for public endpoints, `@SpringBootTest` where a slice would do, H2 standing in for DB-specific behavior, `Thread.sleep`.
- **Medium**: over-verification of collaborator calls, duplicated setup that belongs in a fixture, per-class context variations that break caching.

## Output checklist

- [ ] Each test uses the cheapest context that proves the behavior
- [ ] Unhappy paths (not found, validation, conflict, auth) are covered
- [ ] Assertions check outcomes, and every test can actually fail
- [ ] Persisted-state assertions flush and clear first
- [ ] Tests were run, and the result is reported as-is

---
name: sb-scaffold
description: Use this skill when generating new Spring Boot code for a feature — Controller, Service, Repository, Entity, DTO, or a full REST API slice. Triggers on requests like "generate a controller", "create an entity", "scaffold a REST API", "create a DTO", "add a repository", or any request to scaffold a new domain/feature in a Spring Boot (Java) project.
---

# Spring Boot Code Scaffolding

Generate Controller/Service/Repository/Entity/DTO for a new feature (domain) following the conventions below. If the existing project already has an established convention (package layout, naming), **prefer the existing style** over this skill's defaults; use the defaults below for new projects or when no convention exists yet.

## Package layout (package-by-feature)

```
com.example.app
├── domain/{feature}/
│   ├── {Feature}.java              # Entity
│   ├── {Feature}Repository.java    # Spring Data JPA Repository
│   ├── {Feature}Service.java       # Business logic
│   └── {Feature}Exception.java     # Domain exception (if needed)
├── api/{feature}/
│   ├── {Feature}Controller.java
│   ├── {Feature}Request.java       # or CreateXxxRequest / UpdateXxxRequest
│   └── {Feature}Response.java
└── common/
    ├── exception/GlobalExceptionHandler.java
    └── exception/ErrorResponse.java
```

If the project instead follows package-by-layer (`controller/`, `service/`, `repository/` at the top level), follow that structure, but keep the classes for one feature grouped and easy to locate.

## Rules

- **Use constructor injection only.** No `@Autowired` field injection. Use Lombok `@RequiredArgsConstructor` with `private final` fields.
- **Keep Controllers thin.** They only validate the request (`@Valid`) and delegate to a Service — no business logic.
- **Never expose Entities directly** in API requests/responses. Always go through Request/Response DTOs.
- **Write DTOs as Java `record`s.** Records are the default for immutable data-transfer objects; annotate fields with Bean Validation (`@NotBlank`, `@Size`, `@Email`, etc.).
- **Default associations to `FetchType.LAZY`.** JPA's spec default for `@ManyToOne`/`@OneToOne` is EAGER — override it explicitly to LAZY.
- **Entity ↔ DTO mapping**: give the DTO a static factory method (`static XxxResponse from(Xxx entity)`), or use a MapStruct mapper when the conversion is non-trivial. Don't hand-copy fields one by one inside the Service.
- **Handle exceptions via domain exceptions + `@RestControllerAdvice`.** Don't build HTTP status codes with try-catch inside the Controller.
- Consider pagination (`Pageable`) by default for list endpoints.

## Templates

### Entity
```java
@Entity
@Table(name = "orders")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String productName;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "member_id", nullable = false)
    private Member member;

    @Builder
    private Order(String productName, Member member) {
        this.productName = productName;
        this.member = member;
    }

    public static Order create(String productName, Member member) {
        return Order.builder().productName(productName).member(member).build();
    }
}
```

### Repository
```java
public interface OrderRepository extends JpaRepository<Order, Long> {

    @EntityGraph(attributePaths = "member")
    Optional<Order> findWithMemberById(Long id);
}
```

### DTO (record)
```java
public record CreateOrderRequest(
    @NotBlank String productName,
    @NotNull Long memberId
) {}

public record OrderResponse(Long id, String productName, String memberName) {
    public static OrderResponse from(Order order) {
        return new OrderResponse(order.getId(), order.getProductName(), order.getMember().getName());
    }
}
```

### Service
```java
@Service
@Transactional(readOnly = true)
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final MemberRepository memberRepository;

    @Transactional
    public OrderResponse create(CreateOrderRequest request) {
        Member member = memberRepository.findById(request.memberId())
            .orElseThrow(() -> new MemberNotFoundException(request.memberId()));
        Order order = Order.create(request.productName(), member);
        return OrderResponse.from(orderRepository.save(order));
    }

    public OrderResponse getById(Long id) {
        Order order = orderRepository.findWithMemberById(id)
            .orElseThrow(() -> new OrderNotFoundException(id));
        return OrderResponse.from(order);
    }
}
```

### Controller
```java
@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @PostMapping
    public ResponseEntity<OrderResponse> create(@Valid @RequestBody CreateOrderRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(orderService.create(request));
    }

    @GetMapping("/{id}")
    public ResponseEntity<OrderResponse> getById(@PathVariable Long id) {
        return ResponseEntity.ok(orderService.getById(id));
    }
}
```

### Domain exception + GlobalExceptionHandler
```java
public class OrderNotFoundException extends RuntimeException {
    public OrderNotFoundException(Long id) {
        super("Order not found. id=" + id);
    }
}
```

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(OrderNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(OrderNotFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorResponse(e.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleInvalid(MethodArgumentNotValidException e) {
        String message = e.getBindingResult().getFieldError().getDefaultMessage();
        return ResponseEntity.badRequest().body(new ErrorResponse(message));
    }
}

public record ErrorResponse(String message) {}
```

## Output checklist

After generating code, verify and summarize for the user:
- [ ] Are association fetch strategies set to LAZY?
- [ ] Does the Controller only exchange DTOs, never exposing Entities?
- [ ] Is constructor injection used exclusively (no field injection)?
- [ ] Do write-operation Service methods have `@Transactional` (with the class defaulting to `readOnly = true`)?
- [ ] Does a missing-resource lookup throw a domain exception handled by the GlobalExceptionHandler?

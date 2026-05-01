---
name: hexagonal-java-springboot
description: Guía de arquitectura hexagonal + DDD para Java con Spring Boot 3.x. Estructura de paquetes, naming conventions, patrones de dominio, implementación por layer, testing. Invocar al planificar o revisar servicios Java/Spring.
---

# Hexagonal Architecture + DDD — Java / Spring Boot 3.x

## Estructura de paquetes canónica

```
src/
└── main/
    └── java/com/company/service/
        ├── domain/
        │   ├── model/               ← Aggregate roots, Entities (POJOs puros)
        │   ├── valueobject/         ← Value Objects (Records Java 17+)
        │   ├── repository/          ← Interfaces (ports) — sin Spring
        │   ├── service/             ← Domain Services
        │   └── event/               ← Domain Events
        ├── application/
        │   ├── usecase/             ← Un caso de uso por clase
        │   ├── dto/                 ← Request/Response records
        │   └── port/                ← Driven ports (interfaces de servicios externos)
        ├── infrastructure/
        │   ├── persistence/
        │   │   ├── entity/          ← JPA @Entity (separadas del dominio)
        │   │   ├── repository/      ← Spring Data interfaces + implementaciones de ports
        │   │   └── mapper/          ← Domain ↔ JPA entity (MapStruct)
        │   ├── web/
        │   │   ├── controller/      ← @RestController
        │   │   ├── request/         ← @Valid beans de entrada
        │   │   ├── response/        ← Response records
        │   │   └── exception/       ← @ControllerAdvice + @ExceptionHandler
        │   ├── client/              ← Feign clients / RestClient wrappers
        │   └── messaging/           ← Kafka producers/consumers
        ├── shared/
        │   ├── exception/           ← Domain error hierarchy
        │   └── criteria/            ← Pagination, Specification builders
        └── ServiceApplication.java  ← @SpringBootApplication

src/
└── test/
    └── java/com/company/service/
        ├── unit/
        │   ├── domain/
        │   └── application/
        ├── integration/             ← @SpringBootTest + Testcontainers
        ├── architecture/            ← ArchUnit layer tests
        └── mother/                  ← Object Mothers / builders
```

## Reglas de dependencia

```
Infrastructure → Application → Domain
```

**Domain = Java puro.** Sin `@Component`, `@Service`, `@Repository`, JPA, ni Spring en el dominio.

## Patrones por layer

### Domain — Aggregate Root

```java
// domain/model/Order.java
package com.company.service.domain.model;

import com.company.service.domain.valueobject.Money;
import com.company.service.domain.event.OrderConfirmed;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

public class Order {
    private final UUID id;
    private final UUID customerId;
    private Money total;
    private OrderStatus status;
    private final Instant createdAt;
    private final List<Object> domainEvents = new ArrayList<>();

    // Constructor privado — forzar uso de factory methods
    private Order(UUID id, UUID customerId, Money total, OrderStatus status, Instant createdAt) {
        this.id = id;
        this.customerId = customerId;
        this.total = total;
        this.status = status;
        this.createdAt = createdAt;
    }

    public static Order create(UUID customerId, Money total) {
        if (total.amount() <= 0) {
            throw new InvalidTotalException("Order total must be positive");
        }
        return new Order(UUID.randomUUID(), customerId, total, OrderStatus.PENDING, Instant.now());
    }

    // Reconstruir desde persistencia sin disparar invariantes de creación
    public static Order reconstitute(UUID id, UUID customerId, Money total, OrderStatus status, Instant createdAt) {
        return new Order(id, customerId, total, status, createdAt);
    }

    public void confirm() {
        if (this.status != OrderStatus.PENDING) {
            throw new InvalidStatusTransitionException("Cannot confirm order with status: " + status);
        }
        this.status = OrderStatus.CONFIRMED;
        domainEvents.add(new OrderConfirmed(this.id));
    }

    public List<Object> pullDomainEvents() {
        var events = List.copyOf(domainEvents);
        domainEvents.clear();
        return events;
    }

    // Getters — no setters directos
    public UUID getId()           { return id; }
    public UUID getCustomerId()   { return customerId; }
    public Money getTotal()       { return total; }
    public OrderStatus getStatus(){ return status; }
    public Instant getCreatedAt() { return createdAt; }
}
```

### Domain — Value Object (Record Java 17+)

```java
// domain/valueobject/Money.java
package com.company.service.domain.valueobject;

public record Money(long amount, String currency) {
    // Validación en constructor compacto de record
    public Money {
        if (amount < 0) throw new IllegalArgumentException("Money amount cannot be negative");
        if (currency == null || currency.isBlank()) throw new IllegalArgumentException("Currency required");
    }

    public Money add(Money other) {
        if (!this.currency.equals(other.currency)) {
            throw new IllegalArgumentException("Currency mismatch: " + this.currency + " vs " + other.currency);
        }
        return new Money(this.amount + other.amount, this.currency);
    }
}
// Records son inmutables y con equals/hashCode/toString por defecto
```

### Domain — Repository Port (Interface)

```java
// domain/repository/OrderRepository.java
package com.company.service.domain.repository;

import com.company.service.domain.model.Order;
import java.util.Optional;
import java.util.UUID;

// Port — interface pura, sin Spring Data ni JPA
public interface OrderRepository {
    void save(Order order);
    Optional<Order> findById(UUID id);
    OrderPage findByCriteria(OrderCriteria criteria);
    void delete(UUID id);
}

// Criteria como value object del dominio
public record OrderCriteria(UUID customerId, String status, int page, int pageSize) {}
public record OrderPage(List<Order> items, long total) {}
```

### Domain — Domain Error Hierarchy

```java
// shared/exception/DomainException.java
public abstract class DomainException extends RuntimeException {
    public DomainException(String message) { super(message); }
}

// domain/model/InvalidTotalException.java
public class InvalidTotalException extends DomainException {
    public InvalidTotalException(String message) { super(message); }
}
```

### Application — Use Case

```java
// application/usecase/PlaceOrder.java
package com.company.service.application.usecase;

// Sin anotaciones Spring — POJO puro
public class PlaceOrder {
    private final OrderRepository orders;    // interface del dominio
    private final EventPublisher events;     // port de aplicación

    public PlaceOrder(OrderRepository orders, EventPublisher events) {
        this.orders = orders;
        this.events = events;
    }

    public OrderResponse execute(PlaceOrderRequest request) {
        var total = new Money(request.totalCents(), request.currency());
        var order = Order.create(request.customerId(), total);

        orders.save(order);

        order.pullDomainEvents().forEach(events::publish);

        return new OrderResponse(order.getId(), order.getStatus().name());
    }
}
```

```java
// application/dto/PlaceOrderRequest.java
public record PlaceOrderRequest(UUID customerId, long totalCents, String currency) {}

// application/dto/OrderResponse.java
public record OrderResponse(UUID id, String status) {}
```

### Infrastructure — JPA Entity (separada del dominio)

```java
// infrastructure/persistence/entity/OrderJpaEntity.java
@Entity
@Table(name = "orders")
public class OrderJpaEntity {
    @Id
    private UUID id;

    @Column(nullable = false)
    private UUID customerId;

    @Column(nullable = false)
    private long totalCents;

    @Column(length = 3, nullable = false)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private OrderStatus status;

    @Column(nullable = false)
    private Instant createdAt;

    // Getters + setters para JPA (solo en infraestructura)
}
```

### Infrastructure — Repository Implementation

```java
// infrastructure/persistence/repository/JpaOrderRepository.java
@Component
public class JpaOrderRepository implements OrderRepository {  // implementa el port del dominio
    private final SpringOrderRepository springRepo;
    private final OrderMapper mapper;

    public JpaOrderRepository(SpringOrderRepository springRepo, OrderMapper mapper) {
        this.springRepo = springRepo;
        this.mapper = mapper;
    }

    @Override
    public void save(Order order) {
        springRepo.save(mapper.toJpa(order));
    }

    @Override
    public Optional<Order> findById(UUID id) {
        return springRepo.findById(id).map(mapper::toDomain);
    }
}

// Spring Data para queries (solo en infra)
interface SpringOrderRepository extends JpaRepository<OrderJpaEntity, UUID> {
    List<OrderJpaEntity> findByCustomerIdAndStatus(UUID customerId, OrderStatus status);
}
```

### Infrastructure — MapStruct Mapper

```java
// infrastructure/persistence/mapper/OrderMapper.java
@Mapper(componentModel = "spring")
public interface OrderMapper {
    @Mapping(target = "totalCents", source = "total.amount")
    @Mapping(target = "currency", source = "total.currency")
    OrderJpaEntity toJpa(Order order);

    @Mapping(target = "total", expression = "java(new Money(entity.getTotalCents(), entity.getCurrency()))")
    Order toDomain(OrderJpaEntity entity);
}
```

### Infrastructure — REST Controller

```java
// infrastructure/web/controller/OrderController.java
@RestController
@RequestMapping("/api/v1/orders")
@Validated
public class OrderController {
    private final PlaceOrder placeOrder;

    public OrderController(PlaceOrder placeOrder) {
        this.placeOrder = placeOrder;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public OrderResponse placeOrder(@RequestBody @Valid PlaceOrderRequest request) {
        return placeOrder.execute(request);
    }
}
```

### Infrastructure — Exception Handler

```java
// infrastructure/web/exception/GlobalExceptionHandler.java
@ControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(InvalidTotalException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ProblemDetail handleDomainError(InvalidTotalException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(ConstraintViolationException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
    public ProblemDetail handleValidation(ConstraintViolationException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY, ex.getMessage());
    }
}
```

### Configuration — Spring DI

```java
// application/config/UseCaseConfig.java
@Configuration
public class UseCaseConfig {
    @Bean
    public PlaceOrder placeOrder(OrderRepository orderRepository, EventPublisher eventPublisher) {
        // Use case no tiene @Service — se instancia aquí
        return new PlaceOrder(orderRepository, eventPublisher);
    }
}
```

## Testing

### Object Mother

```java
// test/mother/OrderMother.java
public class OrderMother {
    public static Order valid() {
        return Order.create(UUID.randomUUID(), new Money(10000L, "ARS"));
    }

    public static Order confirmed() {
        Order order = valid();
        order.confirm();
        return order;
    }
}
```

### Unit test (use case con JUnit 5 + Mockito)

```java
// test/unit/application/PlaceOrderTest.java
@ExtendWith(MockitoExtension.class)
class PlaceOrderTest {

    @Mock OrderRepository orders;
    @Mock EventPublisher events;
    @InjectMocks PlaceOrder useCase; // o new PlaceOrder(orders, events)

    @Test
    void shouldCreateAndSaveOrder() {
        // Arrange
        var request = new PlaceOrderRequest(UUID.randomUUID(), 5000L, "ARS");

        // Act
        var response = useCase.execute(request);

        // Assert
        assertThat(response.status()).isEqualTo("PENDING");
        verify(orders).save(any(Order.class));
    }

    @Test
    void shouldThrowWhenTotalIsZero() {
        var request = new PlaceOrderRequest(UUID.randomUUID(), 0L, "ARS");
        assertThatThrownBy(() -> useCase.execute(request))
            .isInstanceOf(InvalidTotalException.class);
    }
}
```

### Integration test (Testcontainers + @DataJpaTest)

```java
@DataJpaTest
@Testcontainers
class JpaOrderRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16")
        .withDatabaseName("testdb");

    @Autowired SpringOrderRepository springRepo;
    @Autowired OrderMapper mapper;

    @Test
    void shouldPersistAndRetrieveOrder() {
        var repo = new JpaOrderRepository(springRepo, mapper);
        var order = OrderMother.valid();

        repo.save(order);
        var found = repo.findById(order.getId());

        assertThat(found).isPresent();
        assertThat(found.get().getStatus()).isEqualTo(OrderStatus.PENDING);
    }
}
```

### Architecture test (ArchUnit)

```java
// test/architecture/LayerDependencyTest.java
@AnalyzeClasses(packages = "com.company.service")
class LayerDependencyTest {

    @ArchTest
    ArchRule domainShouldNotDependOnInfra = noClasses()
        .that().resideInAPackage("..domain..")
        .should().dependOnClassesThat()
        .resideInAPackage("..infrastructure..");

    @ArchTest
    ArchRule domainShouldNotUseSpring = noClasses()
        .that().resideInAPackage("..domain..")
        .should().dependOnClassesThat()
        .resideInAPackage("org.springframework..");
}
```

## Stack recomendado

| Concern | Library |
|---------|---------|
| Framework | Spring Boot 3.x + Spring Web MVC |
| ORM | Spring Data JPA + Hibernate |
| DB driver | PostgreSQL JDBC |
| Mapper | [MapStruct](https://mapstruct.org) — compile-time, sin reflection |
| Validation | Jakarta Validation (`@Valid`, `@NotNull`) |
| Testing unit | JUnit 5 + Mockito |
| Testing integration | [Testcontainers](https://testcontainers.com) + `@DataJpaTest` |
| Architecture test | [ArchUnit](https://www.archunit.org) |
| Migrations | [Flyway](https://flywaydb.org) |
| Observability | Spring Actuator + Micrometer + OpenTelemetry |
| Config | `application.yml` + `@ConfigurationProperties` |

## Reglas de oro — Java / Spring Boot

- **Domain sin `@Component`, `@Service`, `@Repository`** — instanciar en `@Configuration` class
- **Records para Value Objects** (Java 17+) — inmutables y con equals/hashCode gratis
- **`Order.reconstitute()`** separado de `Order.create()`** — reconstituir desde DB no dispara invariantes de creación
- **MapStruct sobre ModelMapper** — mapping compile-time, sin bugs silenciosos en runtime
- **`@Transactional` en use cases** via `@Configuration`, nunca en dominio
- **`ProblemDetail` (RFC 7807)** para error responses — Spring Boot 3.x lo soporta nativo
- **ArchUnit en CI** — tests que fallan si alguien viola layer boundaries
- **Testcontainers para integration tests** — nunca `H2 in-memory` para producción (dialectos distintos)
- **`Optional` de Java** en repository returns — no `null`
- **Flyway sobre Liquibase** — migraciones SQL puras, más predecibles

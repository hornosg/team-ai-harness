---
name: hexagonal-go
description: Guía de arquitectura hexagonal + DDD para Go. Estructura de carpetas, naming conventions, patrones de dominio, implementación por layer, testing. Invocar al planificar o revisar servicios Go.
---

# Hexagonal Architecture + DDD — Go

## Estructura de carpetas canónica

```
service-name/
├── cmd/
│   └── api/
│       └── main.go              ← bootstrap, wire, server start
├── internal/
│   ├── domain/
│   │   ├── model/               ← Aggregate roots, Entities
│   │   ├── valueobject/         ← Value Objects (inmutables)
│   │   ├── repository/          ← Interfaces (ports) — SOLO interfaces
│   │   ├── service/             ← Domain Services (lógica que no cabe en entidad)
│   │   └── event/               ← Domain Events
│   ├── application/
│   │   ├── usecase/             ← Un archivo por use case
│   │   ├── dto/                 ← Request/Response structs
│   │   └── port/                ← Driven ports (interfaces de servicios externos)
│   ├── infrastructure/
│   │   ├── persistence/         ← Repository implementations (pgx, sqlc, gorm)
│   │   ├── http/
│   │   │   ├── handler/         ← HTTP handlers (Chi, Gin, Echo)
│   │   │   ├── middleware/      ← Auth, logging, trace
│   │   │   └── router.go
│   │   ├── client/              ← Clientes de servicios externos
│   │   └── messaging/           ← Publishers/Consumers (Kafka, RabbitMQ)
│   └── shared/
│       ├── apperror/            ← Error types compartidos
│       └── pagination/          ← Criteria, cursors
├── test/
│   ├── mother/                  ← Object Mothers (builders de test data)
│   └── integration/             ← Integration tests con DB real
├── migrations/
└── api-docs/
```

## Reglas de dependencia

```
Infrastructure → Application → Domain
     ↑                ↑           ↑
  depende de      depende de    no depende
  interfaces      interfaces    de nadie
  del dominio     del dominio
```

**Domain es el núcleo puro.** Cero imports de frameworks, DB, o HTTP.

## Patrones por layer

### Domain — Aggregate Root

```go
// internal/domain/model/order.go
package model

import (
    "time"
    "github.com/google/uuid"
    "myservice/internal/domain/valueobject"
    "myservice/internal/domain/event"
)

type Order struct {
    id         uuid.UUID
    customerID uuid.UUID
    total      valueobject.Money
    status     OrderStatus
    items      []OrderItem
    createdAt  time.Time
    events     []event.DomainEvent
}

// Constructor — validación en creación
func NewOrder(customerID uuid.UUID, total valueobject.Money) (*Order, error) {
    if total.Amount() <= 0 {
        return nil, ErrInvalidTotal
    }
    return &Order{
        id:         uuid.New(),
        customerID: customerID,
        total:      total,
        status:     StatusPending,
        createdAt:  time.Now(),
    }, nil
}

// Behavior methods — lógica de negocio en la entidad
func (o *Order) Confirm() error {
    if o.status != StatusPending {
        return ErrOrderAlreadyProcessed
    }
    o.status = StatusConfirmed
    o.events = append(o.events, event.NewOrderConfirmed(o.id))
    return nil
}

// Getters — no setters directos
func (o *Order) ID() uuid.UUID       { return o.id }
func (o *Order) Status() OrderStatus { return o.status }
func (o *Order) Events() []event.DomainEvent { return o.events }

// Domain errors
var (
    ErrInvalidTotal        = errors.New("order: total must be positive")
    ErrOrderAlreadyProcessed = errors.New("order: already processed")
)
```

### Domain — Value Object

```go
// internal/domain/valueobject/money.go
package valueobject

import "errors"

// Value Object: inmutable, comparado por valor
type Money struct {
    amount   int64  // centavos para evitar floats
    currency string
}

func NewMoney(amount int64, currency string) (Money, error) {
    if amount < 0 {
        return Money{}, errors.New("money: amount cannot be negative")
    }
    if currency == "" {
        return Money{}, errors.New("money: currency required")
    }
    return Money{amount: amount, currency: currency}, nil
}

func (m Money) Amount() int64    { return m.amount }
func (m Money) Currency() string { return m.currency }

func (m Money) Add(other Money) (Money, error) {
    if m.currency != other.currency {
        return Money{}, errors.New("money: currency mismatch")
    }
    return Money{amount: m.amount + other.amount, currency: m.currency}, nil
}

// Comparable por valor — no por puntero
func (m Money) Equals(other Money) bool {
    return m.amount == other.amount && m.currency == other.currency
}
```

### Domain — Repository Port (interface)

```go
// internal/domain/repository/order_repository.go
package repository

import (
    "context"
    "github.com/google/uuid"
    "myservice/internal/domain/model"
)

// Port — solo interface, nunca implementación
type OrderRepository interface {
    Save(ctx context.Context, order *model.Order) error
    FindByID(ctx context.Context, id uuid.UUID) (*model.Order, error)
    FindByCriteria(ctx context.Context, criteria OrderCriteria) ([]*model.Order, int64, error)
    Delete(ctx context.Context, id uuid.UUID) error
}

// Criteria para búsquedas complejas — sin SQL en dominio
type OrderCriteria struct {
    CustomerID *uuid.UUID
    Status     *model.OrderStatus
    Page       int
    PageSize   int
}
```

### Application — Use Case

```go
// internal/application/usecase/place_order.go
package usecase

import (
    "context"
    "myservice/internal/application/dto"
    "myservice/internal/domain/model"
    "myservice/internal/domain/repository"
    "myservice/internal/domain/valueobject"
)

// Un use case = una operación de negocio
type PlaceOrder struct {
    orders  repository.OrderRepository  // depende de interface, no implementación
    events  port.EventPublisher
}

func NewPlaceOrder(orders repository.OrderRepository, events port.EventPublisher) *PlaceOrder {
    return &PlaceOrder{orders: orders, events: events}
}

func (uc *PlaceOrder) Execute(ctx context.Context, req dto.PlaceOrderRequest) (dto.OrderResponse, error) {
    total, err := valueobject.NewMoney(req.TotalCents, req.Currency)
    if err != nil {
        return dto.OrderResponse{}, err
    }

    order, err := model.NewOrder(req.CustomerID, total)
    if err != nil {
        return dto.OrderResponse{}, err
    }

    if err := uc.orders.Save(ctx, order); err != nil {
        return dto.OrderResponse{}, err
    }

    // Publicar domain events
    for _, ev := range order.Events() {
        uc.events.Publish(ctx, ev)
    }

    return dto.OrderResponse{ID: order.ID(), Status: string(order.Status())}, nil
}
```

### Infrastructure — Repository Implementation

```go
// internal/infrastructure/persistence/pg_order_repository.go
package persistence

import (
    "context"
    "github.com/jackc/pgx/v5/pgxpool"
    "myservice/internal/domain/model"
    "myservice/internal/domain/repository"
)

// Adapter: implementa el port del dominio
type PgOrderRepository struct {
    db *pgxpool.Pool
}

func NewPgOrderRepository(db *pgxpool.Pool) repository.OrderRepository {
    return &PgOrderRepository{db: db}
}

func (r *PgOrderRepository) Save(ctx context.Context, order *model.Order) error {
    _, err := r.db.Exec(ctx,
        `INSERT INTO orders (id, customer_id, total_cents, currency, status, created_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (id) DO UPDATE SET status = $5`,
        order.ID(), order.CustomerID(), order.Total().Amount(),
        order.Total().Currency(), order.Status(), order.CreatedAt(),
    )
    return err
}
```

### Infrastructure — HTTP Handler

```go
// internal/infrastructure/http/handler/order_handler.go
package handler

import (
    "encoding/json"
    "net/http"
    "myservice/internal/application/dto"
    "myservice/internal/application/usecase"
)

type OrderHandler struct {
    placeOrder *usecase.PlaceOrder
}

func (h *OrderHandler) PlaceOrder(w http.ResponseWriter, r *http.Request) {
    var req dto.PlaceOrderRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
        return
    }

    resp, err := h.placeOrder.Execute(r.Context(), req)
    if err != nil {
        // Mapear domain errors a HTTP status
        writeError(w, err)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(resp)
}
```

## Inyección de dependencias

Usar [Wire](https://github.com/google/wire) o [Fx](https://github.com/uber-go/fx). Manual para proyectos pequeños.

```go
// cmd/api/main.go — wire manual
func main() {
    db := mustConnectDB()

    // Infrastructure
    orderRepo := persistence.NewPgOrderRepository(db)
    eventPub  := messaging.NewKafkaPublisher()

    // Application
    placeOrder := usecase.NewPlaceOrder(orderRepo, eventPub)

    // Infrastructure HTTP
    orderHandler := handler.NewOrderHandler(placeOrder)

    // Router
    r := chi.NewRouter()
    r.Use(middleware.Logger, middleware.TraceID)
    r.Post("/orders", orderHandler.PlaceOrder)

    http.ListenAndServe(":8080", r)
}
```

## Testing

### Object Mother

```go
// test/mother/order_mother.go
package mother

import (
    "github.com/google/uuid"
    "myservice/internal/domain/model"
    "myservice/internal/domain/valueobject"
)

func ValidOrder() *model.Order {
    money, _ := valueobject.NewMoney(10000, "ARS")
    order, _ := model.NewOrder(uuid.New(), money)
    return order
}

func ConfirmedOrder() *model.Order {
    o := ValidOrder()
    o.Confirm()
    return o
}
```

### Unit test (use case)

```go
// internal/application/usecase/place_order_test.go
func TestPlaceOrder_Execute_HappyPath(t *testing.T) {
    // Arrange
    mockRepo := new(mocks.OrderRepository)
    mockPub  := new(mocks.EventPublisher)
    mockRepo.On("Save", mock.Anything, mock.AnythingOfType("*model.Order")).Return(nil)
    mockPub.On("Publish", mock.Anything, mock.Anything).Return(nil)

    uc := usecase.NewPlaceOrder(mockRepo, mockPub)
    req := dto.PlaceOrderRequest{CustomerID: uuid.New(), TotalCents: 5000, Currency: "ARS"}

    // Act
    resp, err := uc.Execute(context.Background(), req)

    // Assert
    assert.NoError(t, err)
    assert.NotEmpty(t, resp.ID)
    mockRepo.AssertExpectations(t)
}
```

## Stack recomendado

| Concern | Library |
|---------|---------|
| HTTP router | [Chi](https://github.com/go-chi/chi) (lightweight) o [Gin](https://github.com/gin-gonic/gin) |
| DB driver | [pgx/v5](https://github.com/jackc/pgx) + [sqlc](https://sqlc.dev) para queries type-safe |
| DI | [Wire](https://github.com/google/wire) o manual para servicios pequeños |
| Mocks | [testify/mock](https://github.com/stretchr/testify) + [mockery](https://github.com/vektra/mockery) |
| Config | [viper](https://github.com/spf13/viper) o `os.Getenv` para 12-factor |
| Validation | [go-playground/validator](https://github.com/go-playground/validator) en DTOs |
| UUID | [google/uuid](https://github.com/google/uuid) |
| Migrations | [golang-migrate](https://github.com/golang-migrate/migrate) |

## Reglas de oro — Go

- **`internal/`** — nada de esta carpeta es importable desde fuera del módulo
- **Interfaces en quien las usa**, no en quien las implementa — el dominio define los ports
- **`context.Context` primer parámetro** en toda función que toca I/O
- **Errores como valores**, no panics — `errors.Is` / `errors.As` para wrapping
- **Structs no exportados** en dominio — exponer solo getters
- **Una transacción por use case** — el use case coordina, no la entidad
- **sqlc sobre ORM** — queries explícitas, type-safe, sin magic
- **`go vet` + `staticcheck` + `golangci-lint`** en CI

---
name: hexagonal-python
description: Guía de arquitectura hexagonal + DDD para Python (FastAPI + SQLAlchemy 2.0 async). Estructura de carpetas, naming conventions, patrones de dominio, implementación por layer, testing. Invocar al planificar o revisar servicios Python.
---

# Hexagonal Architecture + DDD — Python (FastAPI)

## Estructura de carpetas canónica

```
service-name/
├── src/
│   └── service_name/
│       ├── domain/
│       │   ├── model/               ← Aggregate roots, Entities (dataclasses puras)
│       │   ├── value_object/        ← Value Objects inmutables (frozen dataclasses)
│       │   ├── repository/          ← Abstract base classes (ports) — SOLO interfaces
│       │   ├── service/             ← Domain Services
│       │   └── event/               ← Domain Events
│       ├── application/
│       │   ├── use_case/            ← Un archivo por use case
│       │   ├── dto/                 ← Pydantic schemas request/response
│       │   └── port/                ← Driven ports (interfaces de servicios externos)
│       ├── infrastructure/
│       │   ├── persistence/         ← SQLAlchemy repositories
│       │   │   ├── model/           ← ORM models (separados del dominio)
│       │   │   └── repository/      ← Implementaciones concretas
│       │   ├── http/
│       │   │   ├── router/          ← FastAPI routers por dominio
│       │   │   ├── middleware/      ← Auth, logging, tracing
│       │   │   └── dependency.py    ← FastAPI Depends (inyección)
│       │   └── client/              ← HTTP clients externos (httpx)
│       ├── shared/
│       │   ├── error.py             ← Domain error hierarchy
│       │   └── criteria.py          ← Pagination, filters
│       └── main.py                  ← FastAPI app factory
├── tests/
│   ├── unit/
│   ├── integration/
│   └── mother/                      ← Object Mothers / builders
├── migrations/                      ← Alembic
├── pyproject.toml
└── alembic.ini
```

## Reglas de dependencia

```
Infrastructure → Application → Domain
```

**Domain no importa nada de FastAPI, SQLAlchemy, ni Pydantic.** Solo stdlib + dataclasses.

## Patrones por layer

### Domain — Aggregate Root

```python
# src/service_name/domain/model/order.py
from __future__ import annotations
from dataclasses import dataclass, field
from uuid import UUID, uuid4
from datetime import datetime

from service_name.domain.value_object.money import Money
from service_name.domain.event.order_events import OrderConfirmed
from service_name.shared.error import DomainError


class OrderAlreadyProcessedError(DomainError):
    pass


class InvalidTotalError(DomainError):
    pass


@dataclass
class Order:
    id: UUID
    customer_id: UUID
    total: Money
    status: str
    created_at: datetime
    _events: list = field(default_factory=list, repr=False)

    @classmethod
    def create(cls, customer_id: UUID, total: Money) -> Order:
        if total.amount <= 0:
            raise InvalidTotalError("Total must be positive")
        return cls(
            id=uuid4(),
            customer_id=customer_id,
            total=total,
            status="pending",
            created_at=datetime.utcnow(),
        )

    def confirm(self) -> None:
        if self.status != "pending":
            raise OrderAlreadyProcessedError(f"Order {self.id} already processed")
        self.status = "confirmed"
        self._events.append(OrderConfirmed(order_id=self.id))

    def pull_events(self) -> list:
        events, self._events = self._events, []
        return events
```

### Domain — Value Object

```python
# src/service_name/domain/value_object/money.py
from dataclasses import dataclass
from service_name.shared.error import DomainError


class CurrencyMismatchError(DomainError):
    pass


@dataclass(frozen=True)  # frozen = inmutable = comparable por valor
class Money:
    amount: int          # centavos, evitar floats
    currency: str

    def __post_init__(self):
        if self.amount < 0:
            raise ValueError("Money amount cannot be negative")
        if not self.currency:
            raise ValueError("Currency required")

    def add(self, other: "Money") -> "Money":
        if self.currency != other.currency:
            raise CurrencyMismatchError(f"{self.currency} != {other.currency}")
        return Money(amount=self.amount + other.amount, currency=self.currency)
```

### Domain — Repository Port

```python
# src/service_name/domain/repository/order_repository.py
from abc import ABC, abstractmethod
from uuid import UUID
from typing import Optional
from service_name.domain.model.order import Order
from service_name.shared.criteria import Criteria, Page


class OrderRepository(ABC):
    """Port — solo interface, nunca implementación"""

    @abstractmethod
    async def save(self, order: Order) -> None: ...

    @abstractmethod
    async def find_by_id(self, order_id: UUID) -> Optional[Order]: ...

    @abstractmethod
    async def find_by_criteria(self, criteria: Criteria) -> tuple[list[Order], int]: ...

    @abstractmethod
    async def delete(self, order_id: UUID) -> None: ...
```

### Application — Use Case

```python
# src/service_name/application/use_case/place_order.py
from dataclasses import dataclass
from uuid import UUID

from service_name.domain.model.order import Order
from service_name.domain.repository.order_repository import OrderRepository
from service_name.domain.value_object.money import Money
from service_name.application.port.event_publisher import EventPublisher
from service_name.application.dto.order_dto import PlaceOrderRequest, OrderResponse


@dataclass
class PlaceOrder:
    """Un use case = una operación de negocio"""
    orders: OrderRepository    # depende de abstract, no de implementación
    events: EventPublisher

    async def execute(self, req: PlaceOrderRequest) -> OrderResponse:
        total = Money(amount=req.total_cents, currency=req.currency)
        order = Order.create(customer_id=req.customer_id, total=total)

        await self.orders.save(order)

        for event in order.pull_events():
            await self.events.publish(event)

        return OrderResponse(id=order.id, status=order.status)
```

### Application — DTO (Pydantic)

```python
# src/service_name/application/dto/order_dto.py
from pydantic import BaseModel, field_validator
from uuid import UUID


class PlaceOrderRequest(BaseModel):
    customer_id: UUID
    total_cents: int
    currency: str

    @field_validator("total_cents")
    @classmethod
    def must_be_positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("total_cents must be positive")
        return v


class OrderResponse(BaseModel):
    id: UUID
    status: str
```

### Infrastructure — SQLAlchemy ORM Model (separado del dominio)

```python
# src/service_name/infrastructure/persistence/model/order_orm.py
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import String, Integer, DateTime
from uuid import UUID
import datetime


class Base(DeclarativeBase):
    pass


class OrderORM(Base):
    __tablename__ = "orders"

    id: Mapped[UUID] = mapped_column(primary_key=True)
    customer_id: Mapped[UUID] = mapped_column(nullable=False)
    total_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, nullable=False)
```

### Infrastructure — Repository Implementation

```python
# src/service_name/infrastructure/persistence/repository/pg_order_repository.py
from uuid import UUID
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from service_name.domain.model.order import Order
from service_name.domain.repository.order_repository import OrderRepository
from service_name.domain.value_object.money import Money
from service_name.infrastructure.persistence.model.order_orm import OrderORM


class PgOrderRepository(OrderRepository):
    def __init__(self, session: AsyncSession):
        self._session = session

    async def save(self, order: Order) -> None:
        orm = OrderORM(
            id=order.id,
            customer_id=order.customer_id,
            total_cents=order.total.amount,
            currency=order.total.currency,
            status=order.status,
            created_at=order.created_at,
        )
        self._session.add(orm)
        await self._session.flush()

    async def find_by_id(self, order_id: UUID) -> Optional[Order]:
        result = await self._session.execute(select(OrderORM).where(OrderORM.id == order_id))
        orm = result.scalar_one_or_none()
        if not orm:
            return None
        return self._to_domain(orm)

    def _to_domain(self, orm: OrderORM) -> Order:
        return Order(
            id=orm.id,
            customer_id=orm.customer_id,
            total=Money(amount=orm.total_cents, currency=orm.currency),
            status=orm.status,
            created_at=orm.created_at,
        )
```

### Infrastructure — FastAPI Router + DI

```python
# src/service_name/infrastructure/http/router/order_router.py
from fastapi import APIRouter, Depends, status
from service_name.application.use_case.place_order import PlaceOrder
from service_name.application.dto.order_dto import PlaceOrderRequest, OrderResponse
from service_name.infrastructure.http.dependency import get_place_order

router = APIRouter(prefix="/orders", tags=["orders"])


@router.post("/", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def place_order(
    req: PlaceOrderRequest,
    use_case: PlaceOrder = Depends(get_place_order),
) -> OrderResponse:
    return await use_case.execute(req)
```

```python
# src/service_name/infrastructure/http/dependency.py
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from service_name.infrastructure.persistence.db import get_session
from service_name.infrastructure.persistence.repository.pg_order_repository import PgOrderRepository
from service_name.application.use_case.place_order import PlaceOrder


def get_place_order(session: AsyncSession = Depends(get_session)) -> PlaceOrder:
    repo = PgOrderRepository(session)
    return PlaceOrder(orders=repo, events=...)
```

## Testing

### Object Mother

```python
# tests/mother/order_mother.py
from uuid import uuid4
from service_name.domain.model.order import Order
from service_name.domain.value_object.money import Money


class OrderMother:
    @staticmethod
    def valid() -> Order:
        return Order.create(customer_id=uuid4(), total=Money(10000, "ARS"))

    @staticmethod
    def confirmed() -> Order:
        order = OrderMother.valid()
        order.confirm()
        return order
```

### Unit test (use case)

```python
# tests/unit/application/test_place_order.py
import pytest
from unittest.mock import AsyncMock
from service_name.application.use_case.place_order import PlaceOrder
from service_name.application.dto.order_dto import PlaceOrderRequest
from uuid import uuid4


@pytest.mark.asyncio
async def test_place_order_returns_created_order():
    # Arrange
    mock_repo = AsyncMock()
    mock_events = AsyncMock()
    use_case = PlaceOrder(orders=mock_repo, events=mock_events)
    req = PlaceOrderRequest(customer_id=uuid4(), total_cents=5000, currency="ARS")

    # Act
    resp = await use_case.execute(req)

    # Assert
    assert resp.status == "pending"
    mock_repo.save.assert_called_once()
```

## Stack recomendado

| Concern | Library |
|---------|---------|
| HTTP framework | [FastAPI](https://fastapi.tiangolo.com) |
| Validation / DTOs | [Pydantic v2](https://docs.pydantic.dev/latest/) |
| ORM (infra) | [SQLAlchemy 2.0 async](https://docs.sqlalchemy.org/en/20/) |
| DB driver | [asyncpg](https://github.com/MagicStack/asyncpg) (PostgreSQL) |
| Migrations | [Alembic](https://alembic.sqlalchemy.org) |
| Testing | [pytest](https://pytest.org) + [pytest-asyncio](https://github.com/pytest-dev/pytest-asyncio) |
| Config | [pydantic-settings](https://docs.pydantic.dev/latest/concepts/pydantic_settings/) |
| HTTP client | [httpx](https://www.python-httpx.org) (async) |

## Reglas de oro — Python

- **Domain = stdlib + dataclasses únicamente** — cero imports de FastAPI, SQLAlchemy, Pydantic
- **ORM models separados de domain models** — mapear explícitamente en el repo (no heredar de Base en dominio)
- **`frozen=True`** en todos los Value Objects — inmutabilidad garantizada por Python
- **`async/await` en toda la infra** — no bloquear el event loop
- **`ABC + @abstractmethod`** para ports — falla en runtime si no se implementa
- **Un `AsyncSession` por request** — FastAPI Depends maneja el ciclo de vida
- **Alembic para migraciones** — nunca `create_all()` en producción
- **`pytest.mark.asyncio`** + base de datos real en integration tests

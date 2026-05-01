---
name: hexagonal-node
description: Guía de arquitectura hexagonal + DDD para Node.js con TypeScript (NestJS o Express). Estructura de carpetas, naming conventions, patrones de dominio, implementación por layer, testing. Invocar al planificar o revisar servicios Node.
---

# Hexagonal Architecture + DDD — Node.js (TypeScript)

> Two paths: **NestJS** (modules, decorators, DI built-in) para servicios complejos o microservicios con team grande. **Express/Fastify + manual** para microservicios ligeros. La arquitectura de dominio es idéntica en ambos.

## Estructura de carpetas canónica

```
src/
├── domain/
│   ├── model/               ← Aggregate roots, Entities (clases puras TypeScript)
│   ├── value-object/        ← Value Objects inmutables
│   ├── repository/          ← Interfaces (ports)
│   ├── service/             ← Domain Services
│   └── event/               ← Domain Events
├── application/
│   ├── use-case/            ← Un archivo por use case
│   ├── dto/                 ← Zod schemas o clases validadas
│   └── port/                ← Driven ports (interfaces de servicios externos)
├── infrastructure/
│   ├── persistence/
│   │   ├── typeorm/         ← Entities ORM + repositorios TypeORM
│   │   └── prisma/          ← Alternativa: Prisma client wrappers
│   ├── http/
│   │   ├── controller/      ← Controllers (NestJS) o route handlers (Express)
│   │   ├── middleware/      ← Auth, logging, tracing
│   │   └── dto/             ← Request/response validation (class-validator o Zod)
│   └── client/              ← HTTP clients externos (axios, got)
├── shared/
│   ├── error.ts             ← Domain error hierarchy
│   └── criteria.ts          ← Pagination, filters
├── main.ts                  ← Bootstrap
└── app.module.ts            ← NestJS module root (o app.ts para Express)

test/
├── unit/
├── integration/
└── mother/                  ← Object Mothers
```

## Reglas de dependencia

```
Infrastructure → Application → Domain
```

**Domain = TypeScript puro.** Cero imports de NestJS, TypeORM, Prisma, Express.

## Patrones por layer

### Domain — Aggregate Root

```typescript
// src/domain/model/order.ts
import { randomUUID } from 'crypto'
import { Money } from '../value-object/money'
import { DomainEvent } from '../event/domain-event'
import { OrderConfirmed } from '../event/order-confirmed'

export type OrderStatus = 'pending' | 'confirmed' | 'cancelled'

export class Order {
  private readonly _events: DomainEvent[] = []

  private constructor(
    private readonly _id: string,
    private readonly _customerId: string,
    private _total: Money,
    private _status: OrderStatus,
    private readonly _createdAt: Date,
  ) {}

  static create(customerId: string, total: Money): Order {
    if (total.amount <= 0) throw new Error('Order: total must be positive')
    return new Order(randomUUID(), customerId, total, 'pending', new Date())
  }

  confirm(): void {
    if (this._status !== 'pending') throw new InvalidStatusTransitionError(this._status)
    this._status = 'confirmed'
    this._events.push(new OrderConfirmed(this._id))
  }

  pullEvents(): DomainEvent[] {
    return this._events.splice(0)
  }

  get id(): string          { return this._id }
  get customerId(): string  { return this._customerId }
  get total(): Money        { return this._total }
  get status(): OrderStatus { return this._status }
  get createdAt(): Date     { return this._createdAt }
}

export class InvalidStatusTransitionError extends Error {
  constructor(status: OrderStatus) {
    super(`Order: invalid transition from ${status}`)
  }
}
```

### Domain — Value Object

```typescript
// src/domain/value-object/money.ts
export class Money {
  private constructor(
    readonly amount: number,   // centavos, nunca floats
    readonly currency: string,
  ) {}

  static of(amount: number, currency: string): Money {
    if (amount < 0) throw new Error('Money: amount cannot be negative')
    if (!currency) throw new Error('Money: currency required')
    return new Money(amount, currency)
  }

  add(other: Money): Money {
    if (this.currency !== other.currency) {
      throw new Error(`Money: currency mismatch ${this.currency} vs ${other.currency}`)
    }
    return Money.of(this.amount + other.amount, this.currency)
  }

  equals(other: Money): boolean {
    return this.amount === other.amount && this.currency === other.currency
  }
}
```

### Domain — Repository Port

```typescript
// src/domain/repository/order-repository.ts
import { Order } from '../model/order'

export interface OrderCriteria {
  customerId?: string
  status?: string
  page?: number
  pageSize?: number
}

// Port — interface pura, nunca implementación en dominio
export interface OrderRepository {
  save(order: Order): Promise<void>
  findById(id: string): Promise<Order | null>
  findByCriteria(criteria: OrderCriteria): Promise<{ items: Order[]; total: number }>
  delete(id: string): Promise<void>
}
```

### Application — Use Case

```typescript
// src/application/use-case/place-order.ts
import { Order } from '../../domain/model/order'
import { Money } from '../../domain/value-object/money'
import { OrderRepository } from '../../domain/repository/order-repository'
import { EventPublisher } from '../port/event-publisher'
import { PlaceOrderRequest, OrderResponse } from '../dto/order-dto'

export class PlaceOrder {
  constructor(
    private readonly orders: OrderRepository,  // interface, no implementación
    private readonly events: EventPublisher,
  ) {}

  async execute(req: PlaceOrderRequest): Promise<OrderResponse> {
    const total = Money.of(req.totalCents, req.currency)
    const order = Order.create(req.customerId, total)

    await this.orders.save(order)

    for (const event of order.pullEvents()) {
      await this.events.publish(event)
    }

    return { id: order.id, status: order.status }
  }
}
```

### Application — DTO con Zod

```typescript
// src/application/dto/order-dto.ts
import { z } from 'zod'

export const PlaceOrderSchema = z.object({
  customerId: z.string().uuid(),
  totalCents: z.number().int().positive(),
  currency: z.string().length(3),
})

export type PlaceOrderRequest = z.infer<typeof PlaceOrderSchema>

export interface OrderResponse {
  id: string
  status: string
}
```

### Infrastructure — TypeORM Entity (separada del dominio)

```typescript
// src/infrastructure/persistence/typeorm/order.entity.ts
import { Entity, Column, PrimaryColumn, CreateDateColumn } from 'typeorm'

@Entity('orders')
export class OrderEntity {
  @PrimaryColumn('uuid')
  id!: string

  @Column('uuid')
  customerId!: string

  @Column('int')
  totalCents!: number

  @Column('varchar', { length: 3 })
  currency!: string

  @Column('varchar', { length: 20 })
  status!: string

  @CreateDateColumn()
  createdAt!: Date
}
```

### Infrastructure — Repository Implementation

```typescript
// src/infrastructure/persistence/typeorm/pg-order-repository.ts
import { Repository } from 'typeorm'
import { Order } from '../../../domain/model/order'
import { Money } from '../../../domain/value-object/money'
import { OrderRepository } from '../../../domain/repository/order-repository'
import { OrderEntity } from './order.entity'

export class PgOrderRepository implements OrderRepository {
  constructor(private readonly repo: Repository<OrderEntity>) {}

  async save(order: Order): Promise<void> {
    await this.repo.save({
      id: order.id,
      customerId: order.customerId,
      totalCents: order.total.amount,
      currency: order.total.currency,
      status: order.status,
      createdAt: order.createdAt,
    })
  }

  async findById(id: string): Promise<Order | null> {
    const entity = await this.repo.findOne({ where: { id } })
    return entity ? this.toDomain(entity) : null
  }

  private toDomain(e: OrderEntity): Order {
    // Reconstruir aggregate — factory separada del constructor público
    return Order.reconstitute({
      id: e.id,
      customerId: e.customerId,
      total: Money.of(e.totalCents, e.currency),
      status: e.status as any,
      createdAt: e.createdAt,
    })
  }
}
```

### Infrastructure — NestJS Controller

```typescript
// src/infrastructure/http/controller/order.controller.ts
import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common'
import { PlaceOrder } from '../../../application/use-case/place-order'
import { PlaceOrderSchema } from '../../../application/dto/order-dto'
import { ZodValidationPipe } from '../middleware/zod-validation.pipe'

@Controller('orders')
export class OrderController {
  constructor(private readonly placeOrder: PlaceOrder) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async create(@Body(new ZodValidationPipe(PlaceOrderSchema)) body: any) {
    return this.placeOrder.execute(body)
  }
}
```

### NestJS Module (DI)

```typescript
// src/infrastructure/order.module.ts
import { Module } from '@nestjs/common'
import { TypeOrmModule } from '@nestjs/typeorm'
import { OrderEntity } from './persistence/typeorm/order.entity'
import { PgOrderRepository } from './persistence/typeorm/pg-order-repository'
import { PlaceOrder } from '../application/use-case/place-order'
import { OrderController } from './http/controller/order.controller'

@Module({
  imports: [TypeOrmModule.forFeature([OrderEntity])],
  controllers: [OrderController],
  providers: [
    {
      provide: 'OrderRepository',
      useClass: PgOrderRepository,
    },
    {
      provide: PlaceOrder,
      useFactory: (repo: PgOrderRepository) => new PlaceOrder(repo, /* events */),
      inject: ['OrderRepository'],
    },
  ],
})
export class OrderModule {}
```

## Testing

### Object Mother

```typescript
// test/mother/order.mother.ts
import { Order } from '../../src/domain/model/order'
import { Money } from '../../src/domain/value-object/money'

export class OrderMother {
  static valid(): Order {
    return Order.create('customer-1', Money.of(10000, 'ARS'))
  }
  static confirmed(): Order {
    const o = this.valid()
    o.confirm()
    return o
  }
}
```

### Unit test (use case con Jest)

```typescript
// test/unit/application/place-order.test.ts
import { PlaceOrder } from '../../../src/application/use-case/place-order'
import { OrderMother } from '../../mother/order.mother'

describe('PlaceOrder', () => {
  let useCase: PlaceOrder
  let mockRepo: jest.Mocked<OrderRepository>
  let mockEvents: jest.Mocked<EventPublisher>

  beforeEach(() => {
    mockRepo = { save: jest.fn(), findById: jest.fn(), findByCriteria: jest.fn(), delete: jest.fn() }
    mockEvents = { publish: jest.fn() }
    useCase = new PlaceOrder(mockRepo, mockEvents)
  })

  it('creates and saves an order', async () => {
    // Arrange
    mockRepo.save.mockResolvedValue(undefined)
    mockEvents.publish.mockResolvedValue(undefined)

    // Act
    const result = await useCase.execute({ customerId: 'c-1', totalCents: 5000, currency: 'ARS' })

    // Assert
    expect(result.status).toBe('pending')
    expect(mockRepo.save).toHaveBeenCalledTimes(1)
  })
})
```

## Stack recomendado

| Concern | Library |
|---------|---------|
| Framework | [NestJS](https://nestjs.com) (complejo) o [Fastify](https://fastify.dev) (ligero) |
| Validation | [Zod](https://zod.dev) (runtime-safe) o `class-validator` (NestJS nativo) |
| ORM | [TypeORM](https://typeorm.io) o [Prisma](https://prisma.io) |
| DB driver | [pg](https://node-postgres.com) o Prisma client |
| Testing | [Jest](https://jestjs.io) + [ts-jest](https://kulshekhar.github.io/ts-jest/) |
| Config | [@nestjs/config](https://docs.nestjs.com/techniques/configuration) + `.env` |
| HTTP client | [axios](https://axios-http.com) o [got](https://github.com/sindresorhus/got) |
| UUID | `crypto.randomUUID()` (Node 16.7+, built-in) |
| Migrations | TypeORM migrations o `prisma migrate` |

## Reglas de oro — Node.js / TypeScript

- **`strict: true`** en `tsconfig.json` — sin `any` implícito
- **Domain = TypeScript puro** — cero imports de NestJS, TypeORM, Express
- **Inversión de dependencias explícita** — use cases reciben interfaces en constructor
- **ORM entities separadas de domain entities** — mapear en el repositorio
- **`Order.reconstitute()`** para reconstruir aggregates desde DB — sin bypass de invariantes
- **Zod para validación de entrada** — en el borde (controller/HTTP), no en dominio
- **Barrel exports (`index.ts`)** por capa — simplifica imports
- **Jest + `--testPathPattern`** para correr unit tests separado de integration
- **`eslint` + `@typescript-eslint`** en CI — no lint warnings en merge

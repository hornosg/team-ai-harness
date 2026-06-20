---
name: event-driven
description: Guía e implementación del patrón de eventos de dominio en el ecosistema mercado-cercano: EventBus PostgreSQL-backed, adapter pattern (EventPublisherAdapter), naming de eventos, consumidores idempotentes, y consideraciones de outbox. También cubre la verificación de que los eventos se publican correctamente post-command y no contaminan el dominio. Triggers: "eventos de dominio", "domain events", "publicar evento", "EventBus", "event-driven", "event publisher", "tenant.settings.updated", "consumidor idempotente", "outbox pattern", "publicación post-command".
---

# Event-Driven — Domain Events con EventBus PostgreSQL

Patrón del ecosistema mercado-cercano para publicar y consumir eventos de dominio entre servicios. Basado en los ADRs `tenant-service/ADR-002` (separación de DBs) y `tenant-service/ADR-003` (domain events vía EventBus).

## Principio base

El comando (write) sucede primero, exitosamente. Solo al finalizar con éxito, se publica el evento. **La publicación es best-effort**: si el servicio falla entre el commit y la publicación, el evento se pierde. Se acepta como trade-off consciente (ver ADR-002). Para consistencia fuerte, usar Transactional Outbox (no implementado aún en el ecosistema).

---

## 1. Naming de eventos

Formato: `<contexto>.<entidad>.<acción>` — todo en minúsculas con puntos.

| Contexto | Entidad | Acción | Evento completo |
|----------|---------|--------|-----------------|
| `tenant` | `settings` | `updated` | `tenant.settings.updated` |
| `tenant` | `point_of_sale` | `created` | `tenant.point_of_sale.created` |
| `sales` | `order` | `created` | `sales.order.created` |
| `stock` | `availability` | `depleted` | `stock.availability.depleted` |
| `pim` | `product` | `published` | `pim.product.published` |

**Reglas**:
- El contexto = el bounded context que publica (no el que consume).
- La acción en pasado: `created`, `updated`, `deleted`, `published`, `depleted`.
- Sin abreviaturas: `point_of_sale`, no `pos`.

---

## 2. Puerto de dominio (EventPublisher interface)

El dominio **nunca** importa el EventBus concreto. Define una interfaz (puerto driven) que la infraestructura implementa.

```go
// domain/port/event_publisher.go (o application/port/)
package port

import "context"

type EventPublisher interface {
    Publish(ctx context.Context, eventType string, payload interface{}) error
}
```

El use case depende de la interfaz, nunca del adaptador:

```go
// application/usecase/update_tenant_settings.go
type UpdateTenantSettingsUseCase struct {
    repo      repository.TenantRepository
    publisher port.EventPublisher  // ← interfaz, no implementación
}

func (uc *UpdateTenantSettingsUseCase) Execute(ctx context.Context, req dto.UpdateSettingsRequest) error {
    tenant, err := uc.repo.FindByID(ctx, req.TenantID)
    if err != nil {
        return err
    }

    if err := tenant.UpdateSettings(req.Settings); err != nil {
        return err
    }

    if err := uc.repo.Save(ctx, tenant); err != nil {
        return err
    }

    // Post-command exitoso: publicar evento (best-effort)
    if err := uc.publisher.Publish(ctx, "tenant.settings.updated", tenant.Settings()); err != nil {
        // No retornar el error — la escritura ya fue exitosa
        // Solo loguear el warning
        log.Printf("WARN: failed to publish tenant.settings.updated: %v", err)
    }

    return nil
}
```

---

## 3. EventPublisherAdapter (infraestructura)

```go
// infrastructure/messaging/event_publisher_adapter.go
package messaging

import (
    "context"
    "encoding/json"
    "fmt"
    "time"

    "github.com/google/uuid"
    "database/sql"
)

type EventPublisherAdapter struct {
    db *sql.DB
}

func NewEventPublisherAdapter(eventbusDB *sql.DB) *EventPublisherAdapter {
    return &EventPublisherAdapter{db: eventbusDB}
}

func (a *EventPublisherAdapter) Publish(ctx context.Context, eventType string, payload interface{}) error {
    data, err := json.Marshal(payload)
    if err != nil {
        return fmt.Errorf("marshal payload: %w", err)
    }

    _, err = a.db.ExecContext(ctx,
        `INSERT INTO events (id, type, payload, created_at)
         VALUES ($1, $2, $3, $4)`,
        uuid.New(), eventType, data, time.Now().UTC(),
    )
    return err
}
```

El `EventPublisherAdapter` implementa `port.EventPublisher`. Se inyecta en el use case en `main.go` (wiring).

---

## 4. Esquema de la tabla `events` en eventbus

```sql
-- migrations/001_create_events.sql (en la DB eventbus)
CREATE TABLE IF NOT EXISTS events (
    id          uuid        PRIMARY KEY,
    type        text        NOT NULL,
    payload     jsonb       NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    processed   boolean     NOT NULL DEFAULT false,
    processed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_events_type ON events (type);
CREATE INDEX IF NOT EXISTS idx_events_processed ON events (processed) WHERE NOT processed;
```

---

## 5. Wiring en main.go

```go
// cmd/api/main.go
tenantDB  := mustConnect(postgres.Config{..., DBName: "tenant_db"})
eventbusDB := mustConnect(postgres.Config{..., DBName: "eventbus"})

publisher := messaging.NewEventPublisherAdapter(eventbusDB)
updateUC  := usecase.NewUpdateTenantSettingsUseCase(tenantRepo, publisher)
```

Los dos `*sql.DB` son pools independientes — nunca reutilizar el mismo `*sql.DB` para `tenant_db` y `eventbus`.

---

## 6. Consumidores idempotentes

Un consumidor que lee de la tabla `events` debe ser idempotente: procesar el mismo evento dos veces no debe tener efectos secundarios diferentes a procesarlo una vez.

Patrón de procesamiento:

```go
// Marcar como procesado ANTES de ejecutar la acción downstream
// (at-most-once; apropiado cuando la acción es cara y el replay no es critico)
_, err = db.ExecContext(ctx,
    `UPDATE events SET processed = true, processed_at = now() WHERE id = $1 AND NOT processed`,
    event.ID,
)
if err != nil || rowsAffected == 0 {
    return // ya fue procesado por otra instancia o falló el lock
}
// Ahora ejecutar la acción
```

Para at-least-once (más confiable): ejecutar la acción primero y marcar al final. La acción debe ser idempotente o usar un identificador de idempotencia.

---

## 7. Verificación — checklist

Al auditar un servicio que publica eventos, verificar:

| # | Check | Severidad si falla |
|---|-------|-------------------|
| 1 | La publicación ocurre **después** del commit a la DB principal, no antes | HIGH |
| 2 | El use case depende de `port.EventPublisher` (interfaz), no del adapter concreto | HIGH |
| 3 | El error de publicación se **loguea** pero no cancela el comando | MEDIUM |
| 4 | El `EventPublisherAdapter` usa el `*sql.DB` de `eventbus`, no de la DB principal | HIGH |
| 5 | El nombre del evento sigue el formato `<contexto>.<entidad>.<acción>` | MEDIUM |
| 6 | Los consumidores son idempotentes (doble procesamiento no causa efectos dobles) | HIGH |
| 7 | La tabla `events` tiene índice en `(processed)` para polling eficiente | LOW |

Grep de diagnóstico rápido:

```bash
# ¿El dominio o la aplicación importan directamente el paquete de eventbus?
grep -rn '".*eventbus\|eventbus.*"' --include="*.go" \
  $(find . -path "*/domain/*" -o -path "*/application/*") 2>/dev/null | grep -v "_test.go"
# → Cualquier resultado = HIGH (fuga de infraestructura en capas de dominio/aplicación)

# ¿El evento se publica antes del return nil del use case?
grep -B5 "publisher.Publish\|Publisher.Publish" --include="*.go" -rn . | grep -v "_test.go"
# → Verificar manualmente que aparece después del repo.Save()
```

---

## 8. Trade-off documentado: no-atomicidad (ADR-002)

La escritura en `tenant_db` y la publicación en `eventbus` **no son atómicas**. Si el proceso se cae entre el `repo.Save()` y el `publisher.Publish()`, el evento se pierde.

**Cuándo esto es aceptable** (estado actual del ecosistema): cuando los consumidores pueden tolerar perder un evento ocasional o pueden sincronizar estado por polling.

**Cuándo NO es aceptable**: flujos de cobro, auditoría regulatoria, o cualquier caso donde la ausencia del evento tiene consecuencias financieras o legales. En esos casos, implementar Transactional Outbox (pendiente en backlog del ecosistema).

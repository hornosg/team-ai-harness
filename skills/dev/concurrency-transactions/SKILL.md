---
name: concurrency-transactions
description: Auditoría de atomicidad y concurrencia en servicios Go con PostgreSQL. Verifica que las operaciones de stock/ventas usen SELECT FOR UPDATE en una sola transacción, que la lógica de validación esté en Go (no en triggers) y el aislamiento en DB, y que la compensación sea explícita sin UPSERT defensivo. Triggers: "auditá la atomicidad", "verificá la concurrencia", "audit concurrency", "race condition en stock", "SELECT FOR UPDATE", "compensación de venta", "sobreventa", "check transactions", "ProcessSale", "ProcessSaleAtomic".
---

# Concurrency & Transactions Audit

Audita que las operaciones de escritura en el ecosistema mercado-cercano sean atómicas bajo concurrencia — sin sobreventa, sin filas fantasma, sin lógica de negocio en triggers.

Pipeline: discovery → check-then-act races → transacciones y locks → compensación → UPSERT defensivo → tabla de hallazgos → veredicto.

## Severidades

| Nivel | Criterio | Veredicto |
|-------|----------|-----------|
| **CRITICAL** | Operación de validación + escritura separadas sin lock — race condition garantizada bajo concurrencia | NO-GO obligatorio |
| **HIGH** | Transacción sin `FOR UPDATE`, lógica de negocio en trigger, UPSERT defensivo que crea filas fantasma | NO-GO; justificación explícita si se fuerza |
| **MEDIUM** | Compensación sin registro de auditoría, falta de rollback explícito en flujo multi-ítem | GO con advertencia |
| **LOW** | Métodos deprecados no eliminados, lock-contention no documentado | GO |

---

## Fase 0 — Discovery

```bash
# Localizar repositorios de stock y ventas
find . -name "*.go" | xargs grep -l "ProcessSale\|CheckAvailability\|stock_availability\|FOR UPDATE" 2>/dev/null

# Ver el esquema de stock
find . -name "*.sql" | xargs grep -l "stock_availability\|stock_movement" 2>/dev/null | head -5
```

Construir mapa de operaciones:

| Operación | Archivo | ¿Tiene transacción? | ¿Usa FOR UPDATE? |
|-----------|---------|-------------------|-----------------|
| `ProcessSaleAtomic` | ... | ... | ... |
| `CheckAvailability` | ... | ... | ... |
| `ProcessSale` | ... | ... | ... |

---

## Fase 1 — Detección de operaciones check-then-act separadas (CRITICAL)

El patrón de race condition clásico del ecosistema: validar disponibilidad y descontar stock como dos operaciones independientes.

```bash
# Buscar el par peligroso: CheckAvailability + ProcessSale en el mismo flujo
grep -rn "CheckAvailability\|ProcessSale" --include="*.go" . | grep -v "_test.go" | grep -v "ProcessSaleAtomic"
```

**CRITICAL si**: en el mismo use case o handler aparecen `CheckAvailability` (o equivalente: `GetAvailability`, `ValidateStock`) seguido de `ProcessSale` (o `DiscountStock`, `RegisterMovement`) **sin** envolverse en una transacción con `SELECT FOR UPDATE`.

Patrón NO correcto:
```go
// ❌ CRITICAL — race condition garantizada
avail, _ := repo.CheckAvailability(ctx, skuID)
if avail < qty { return ErrInsufficientStock }
repo.ProcessSale(ctx, skuID, qty)  // otra goroutine pudo vender entre estas dos líneas
```

Patrón correcto (ADR-001 de sales y stock):
```go
// ✓ Operación atómica — validación + descuento en una sola transacción con FOR UPDATE
err = repo.ProcessSaleAtomic(ctx, skuID, qty)
```

---

## Fase 2 — Verificación de transacciones y locks row-level

### 2a. SELECT FOR UPDATE en la operación atómica

```bash
grep -rn "FOR UPDATE\|BeginTx\|sql.TxOptions" --include="*.go" . | grep -v "_test.go"
```

Para cada operación que muta stock:
- ¿La query SQL usa `SELECT ... FOR UPDATE`? Si no → HIGH.
- ¿La lectura y la escritura están dentro de la misma `tx`? Si se hace `tx.QueryRow` + `tx.Exec` sin que ambos usen la misma transacción → CRITICAL.
- ¿El `BeginTx` tiene nivel de aislamiento adecuado? `sql.LevelSerializable` es más fuerte pero `LevelReadCommitted` con `FOR UPDATE` es el patrón del ecosistema.

Patrón correcto en el repositorio:
```go
// infrastructure/persistence/stock_repository.go
func (r *StockRepository) ProcessSaleAtomic(ctx context.Context, skuID uuid.UUID, qty int) error {
    tx, err := r.db.BeginTx(ctx, nil)
    if err != nil {
        return fmt.Errorf("beginTx: %w", err)
    }
    defer tx.Rollback() // no-op si ya se hizo Commit

    var available int
    err = tx.QueryRowContext(ctx,
        `SELECT quantity FROM stock_availability WHERE sku_id = $1 FOR UPDATE`,
        skuID,
    ).Scan(&available)
    if err != nil {
        return fmt.Errorf("lockRow: %w", err)
    }

    if available < qty {
        return domain.ErrInsufficientStock
    }

    _, err = tx.ExecContext(ctx,
        `UPDATE stock_availability SET quantity = quantity - $1 WHERE sku_id = $2`,
        qty, skuID,
    )
    if err != nil {
        return fmt.Errorf("updateStock: %w", err)
    }

    return tx.Commit()
}
```

### 2b. Lógica de negocio en triggers (HIGH)

```bash
find . -name "*.sql" | xargs grep -l "CREATE.*TRIGGER\|CREATE.*FUNCTION" 2>/dev/null
```

Para cada trigger encontrado, verificar que **solo** recalcula agregados y **no** valida reglas de negocio (cantidad disponible, límites, permisos).

Patrón correcto (stock-service ADR-001): el trigger recalcula el total de stock agregado, pero la validación de "¿hay suficiente?" ocurre en Go dentro de la transacción.

**HIGH si**: el trigger contiene `IF NEW.quantity < 0 THEN RAISE...` o similar — mezcla persistencia con lógica de negocio, no testeable en Go.

---

## Fase 3 — Verificación de compensación

El ecosistema usa compensación explícita, no saga automática.

```bash
grep -rn "compensate\|Compensate\|rollback.*sale\|RollbackSale" --include="*.go" . | grep -v "_test.go"
```

Para cada operación que puede fallar parcialmente (ej. venta multi-ítem):
- ¿Existe un endpoint / use case de compensación? Si no → HIGH cuando la operación es multi-ítem.
- ¿Se invoca la compensación en el handler/use case ante fallo parcial? Si no → HIGH.
- ¿Se registra la compensación en un log de auditoría? Si no → MEDIUM.

Patrón del ecosistema (sales-service ADR-001):
- Compensación: `POST /api/v1/compensate-sale` (stock-service)
- Disparada por sales-service ante fallo en la creación de la orden
- Los métodos `CheckAvailability` + `ProcessSale` originales quedan **deprecated** (no eliminados por compatibilidad durante transición) — su presencia es LOW, no CRITICAL, si `ProcessSaleAtomic` existe y se usa.

---

## Fase 4 — UPSERT defensivo (anti-patrón)

```bash
grep -rn "ON CONFLICT\|INSERT.*ON CONFLICT\|UPSERT" --include="*.sql" --include="*.go" . 2>/dev/null | grep -v "_test"
```

**HIGH si**: se usa `INSERT ... ON CONFLICT DO NOTHING` o `ON CONFLICT DO UPDATE` para garantizar la existencia de una fila de stock antes de operar sobre ella. Esto crea **filas fantasma** (stock con cantidad 0 sin movimiento real que las justifique).

Decisión del ecosistema (stock-service ADR-001): no usar UPSERT defensivo. Si la fila de `stock_availability` no existe, es un error de datos, no un caso a manejar silenciosamente.

---

## Tabla de hallazgos

```
| # | Severity | Fase | Archivo              | Problema                                      | Fix sugerido                                    |
|---|----------|------|----------------------|-----------------------------------------------|-------------------------------------------------|
| 1 | CRITICAL | 1    | sale_usecase.go:45   | CheckAvailability + ProcessSale separados     | Reemplazar por ProcessSaleAtomic con FOR UPDATE |
| 2 | HIGH     | 2a   | stock_repo.go:78     | UPDATE stock sin FOR UPDATE en la misma tx    | Agregar SELECT...FOR UPDATE dentro de BeginTx   |
| 3 | HIGH     | 2b   | 004_triggers.sql:12  | Trigger valida cantidad disponible            | Mover validación a Go; trigger solo recalcula   |
| 4 | HIGH     | 3    | order_handler.go:90  | Fallo parcial sin llamar compensación         | Agregar llamada a compensate-sale en defer/err  |
| 5 | HIGH     | 4    | stock_repo.go:120    | UPSERT defensivo crea filas fantasma          | Eliminar ON CONFLICT; fallar si la fila no existe|
| 6 | MEDIUM   | 3    | compensate_uc.go     | Compensación sin log de auditoría             | Registrar compensación en tabla de auditoría   |
| 7 | LOW      | 1    | stock_repo.go:200    | CheckAvailability + ProcessSale no eliminados | Marcar como deprecated; planificar limpieza     |
```

---

## Veredicto

**NO-GO** si hay CRITICAL o HIGH sin justificación explícita:
```
❌ NO-GO — resolver antes de mergear:
  1. [acción concreta]
```

**GO con advertencias** si solo MEDIUM/LOW:
```
✅ GO — N advertencia(s) para follow-up:
  1. [descripción]
```

**GO limpio**:
```
✅ GO
```

---
name: postgres-data-modeling
description: Guía de modelado relacional en PostgreSQL para el ecosistema mercado-cercano: JSONB con índices GIN, pgvector, migraciones evolutivas, snapshots inmutables, multi-DB con pools separados. Invocar al diseñar o revisar esquemas de tablas, agregar columnas JSONB, escribir migraciones, separar bases de datos dentro de la misma instancia PostgreSQL, o integrar pgvector. Triggers: "modelá la tabla", "design the schema", "migración evolutiva", "JSONB vs columnas", "snapshot inmutable", "pools de conexión", "agregar pgvector", "índice GIN".
---

# PostgreSQL Data Modeling — mercado-cercano

Stack del ecosistema: **PostgreSQL 15** (`pgvector` disponible en `lab-postgres`), raw SQL con `lib/pq` (sin ORM — convención del monorepo).

## Principio base

El modelo de datos refleja el dominio, no la conveniencia del driver. Las decisiones de esquema van a migraciones versionadas; nunca se altera el schema desde código de aplicación en runtime.

---

## 1. Cuándo JSONB vs columnas tipadas

| Criterio | Columnas tipadas | JSONB |
|----------|-----------------|-------|
| Los campos son conocidos y estables | ✓ | — |
| Se necesita filtrar/ordenar por el campo | ✓ | Solo con índice GIN (less expressive) |
| El esquema varía por tenant / tipo de entidad | — | ✓ |
| Se necesita preservar un objeto completo en el tiempo (snapshot) | — | ✓ |
| Atributos dinámicos definidos por el usuario (ej. atributos de producto en PIM) | — | ✓ |

**Regla del monorepo**: JSONB para atributos dinámicos y snapshots; columnas tipadas para todo dato que se filtra, ordena o join. No mezclar: si un campo JSONB pasa a ser consultado frecuentemente, migrar a columna tipada.

---

## 2. Índices GIN para columnas JSONB

```sql
-- Índice GIN estándar — soporta @>, ?, ?|, ?& sobre jsonb
CREATE INDEX idx_order_items_product_snapshot
  ON order_items USING GIN (product_snapshot);

CREATE INDEX idx_order_items_variant_snapshot
  ON order_items USING GIN (variant_snapshot);
```

- Usar `USING GIN` siempre que se vaya a consultar dentro del JSONB.
- Para path específico frecuente: `USING GIN ((col->'campo'))` o columna generada.
- El índice GIN agrega ~20–40% de overhead en writes — aplicar solo donde hay búsqueda real.

Consulta sobre snapshot (ejemplo real sales-service):
```sql
-- Buscar órdenes por nombre de producto en el snapshot
SELECT id, created_at
FROM order_items
WHERE product_snapshot @> '{"name": "Yerba Amanda 500g"}';
```

---

## 3. Migraciones evolutivas

### Patrón de nomenclatura (ya usado en sales-service)

```
migrations/
├── 001_create_orders.sql
├── 002_create_order_items.sql
├── 003_add_snapshots_to_order_items.sql   ← siempre aditivo
├── 004_add_stock_movements.sql
└── ...
```

**Reglas**:
- Numeración secuencial con ceros a la izquierda (`NNN_descripcion.sql`).
- Solo migraciones aditivas: `ADD COLUMN`, `CREATE INDEX`, `CREATE TABLE`.
- Las columnas nuevas sin default que puedan tener filas preexistentes deben usar `DEFAULT NULL` o agregar un `DEFAULT` explícito.
- Nunca `DROP COLUMN`, `DROP TABLE`, `TRUNCATE` sin una migración de limpieza separada y planificada.
- Cada migración incluye rollback como comentario o migración `NNN_rollback_descripcion.sql` separada.

### Ejemplo real — migración de snapshots (sales-service `003_add_snapshots_to_order_items.sql`)

```sql
-- UP: agrega snapshots inmutables a order_items
ALTER TABLE order_items
  ADD COLUMN IF NOT EXISTS product_snapshot JSONB,
  ADD COLUMN IF NOT EXISTS variant_snapshot JSONB;

CREATE INDEX IF NOT EXISTS idx_order_items_product_snapshot
  ON order_items USING GIN (product_snapshot);

CREATE INDEX IF NOT EXISTS idx_order_items_variant_snapshot
  ON order_items USING GIN (variant_snapshot);

-- ROLLBACK (ejecutar manualmente si se necesita revertir)
-- ALTER TABLE order_items DROP COLUMN IF EXISTS product_snapshot;
-- ALTER TABLE order_items DROP COLUMN IF EXISTS variant_snapshot;
-- DROP INDEX IF EXISTS idx_order_items_product_snapshot;
-- DROP INDEX IF EXISTS idx_order_items_variant_snapshot;
```

`ADD COLUMN IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS`: idempotentes ante re-ejecución en distintos entornos.

---

## 4. Snapshots inmutables

Patrón aplicado en `sales-service`: al crear una orden, cada `order_item` captura un snapshot JSON del producto y la variante tal como estaban en PIM en ese momento.

### Constructor en Go (capa application/usecase)

```go
// application/usecase/create_order.go
func (uc *CreateOrderUseCase) Execute(ctx context.Context, req dto.CreateOrderRequest) (*dto.OrderResponse, error) {
    items := make([]model.OrderItem, 0, len(req.Items))
    for _, it := range req.Items {
        product, variant, err := uc.pimClient.GetVariantWithProduct(ctx, it.VariantID)
        if err != nil {
            return nil, fmt.Errorf("fetchSnapshot: %w", err)
        }
        item, err := model.NewOrderItemWithSnapshots(it.VariantID, it.Qty, product, variant)
        if err != nil {
            return nil, err
        }
        items = append(items, item)
    }
    // ...persist order + items
}
```

### Entidad en Go (capa domain/model)

```go
// domain/model/order_item.go
type OrderItem struct {
    id              uuid.UUID
    variantID       uuid.UUID
    quantity        int
    productSnapshot json.RawMessage  // inmutable desde creación
    variantSnapshot json.RawMessage  // inmutable desde creación
}

func NewOrderItemWithSnapshots(
    variantID uuid.UUID,
    qty int,
    product ProductSnapshot,
    variant VariantSnapshot,
) (OrderItem, error) {
    if qty <= 0 {
        return OrderItem{}, errors.New("quantity must be positive")
    }
    ps, _ := json.Marshal(product)
    vs, _ := json.Marshal(variant)
    return OrderItem{
        id:              uuid.New(),
        variantID:       variantID,
        quantity:        qty,
        productSnapshot: ps,
        variantSnapshot: vs,
    }, nil
}
```

**Invariante**: una vez creado el `OrderItem`, los snapshots no se actualizan. Cualquier cambio posterior en PIM no afecta órdenes existentes.

---

## 5. pgvector

Disponible en `lab-postgres` (imagen `pgvector/pgvector:pg15`). Para servicios que necesiten embeddings semánticos.

### Habilitación y esquema

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE product_embeddings (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  uuid NOT NULL REFERENCES products(id),
    model_name  text NOT NULL,         -- ej. "text-embedding-3-small"
    embedding   vector(1536),          -- dimensión según modelo
    created_at  timestamptz DEFAULT now()
);

-- Índice HNSW para búsqueda ANN (approximate nearest neighbor)
CREATE INDEX ON product_embeddings
  USING hnsw (embedding vector_cosine_ops);
```

### Consulta de similitud

```sql
-- Top 5 productos similares a un embedding dado
SELECT p.id, p.name, 1 - (pe.embedding <=> $1::vector) AS similarity
FROM product_embeddings pe
JOIN products p ON p.id = pe.product_id
WHERE pe.model_name = $2
ORDER BY pe.embedding <=> $1::vector
LIMIT 5;
```

En Go (con `lib/pq`, sin driver nativo de pgvector):

```go
// Convertir []float32 a formato literal de pgvector: '[0.1,0.2,...]'
func Float32SliceToPgVector(v []float32) string {
    s := make([]string, len(v))
    for i, f := range v {
        s[i] = strconv.FormatFloat(float64(f), 'f', -1, 32)
    }
    return "[" + strings.Join(s, ",") + "]"
}

// Uso en query
vec := Float32SliceToPgVector(embedding)
rows, err := db.QueryContext(ctx,
    `SELECT product_id, 1 - (embedding <=> $1::vector) FROM product_embeddings ORDER BY embedding <=> $1::vector LIMIT 5`,
    vec)
```

---

## 6. Multi-DB y pools de conexión separados

Patrón aplicado en `tenant-service` (ADR-002): dos bases de datos en la misma instancia PostgreSQL con pools independientes.

```
lab-postgres
├── tenant_db      ← datos de dominio del tenant
└── eventbus       ← eventos de dominio publicados
```

### Wiring en main.go (con go-shared v0.7.0)

```go
import "github.com/hornosg/go-shared/infrastructure/postgres"

// tenant_db
tenantDB, err := connectWithRetry(postgres.Config{
    Host:     cfg.DBHost,
    Port:     cfg.DBPort,
    User:     cfg.DBUser,
    Password: cfg.DBPassword,
    DBName:   "tenant_db",
    SSLMode:  "disable",
})
postgres.StartPoolMonitor(ctx, tenantDB, postgres.MonitorOptions{Service: "tenant-service", DBName: "tenant_db"})

// eventbus (pool separado)
eventbusDB, err := connectWithRetry(postgres.Config{
    Host:     cfg.DBHost,
    Port:     cfg.DBPort,
    User:     cfg.EventBusUser,
    Password: cfg.EventBusPassword,
    DBName:   "eventbus",
    SSLMode:  "disable",
})
postgres.StartPoolMonitor(ctx, eventbusDB, postgres.MonitorOptions{Service: "tenant-service", DBName: "eventbus"})
```

**Trade-off documentado (ADR-002)**: no hay atomicidad entre la escritura en `tenant_db` y la publicación en `eventbus`. Se acepta como comportamiento best-effort: si el servicio falla entre ambas operaciones, el evento se pierde. Para consistencia fuerte, usar Transactional Outbox (no implementado aún — ver backlog).

---

## 7. Reglas de oro

1. **Sin ORM**: `database/sql` + `lib/pq`, raw SQL. Las queries van en los repository adapters, nunca en el dominio.
2. **Migraciones solo aditivas**: nunca destruir datos sin migraciones de limpieza planificadas y separadas.
3. **`IF NOT EXISTS` en migraciones**: idempotencia ante re-ejecución en distintos entornos del lab.
4. **GIN cuando buscás en JSONB**: sin índice, la consulta hace seq scan sobre la columna completa.
5. **Snapshots son inmutables**: si necesitás actualizar un snapshot, es un diseño diferente (versioning o nuevo registro).
6. **Pools separados por DB**: no reutilizar el mismo `*sql.DB` entre bases de datos distintas.
7. **`go-shared/infrastructure/postgres`**: usar `postgres.Connect()` y `postgres.StartPoolMonitor()` en todos los servicios — convención del monorepo desde v0.7.0.

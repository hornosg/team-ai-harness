---
name: inter-service-contracts
description: Auditoría de contratos entre servicios del ecosistema mercado-cercano: compatibilidad de DTOs (paginación items vs campos legacy), deserialización tolerante con prioridad documentada, reglas de composición BFF (qué puede y no puede hacer un BFF), rutas vía Kong. Triggers: "auditá los contratos", "audit inter-service contracts", "compatibilidad de DTOs", "paginación items vs roles", "BFF composition rules", "catalog-bff", "deserialización tolerante", "contrato entre servicios", "consumer contract".
---

# Inter-Service Contracts Audit

Audita que los servicios del ecosistema respeten los contratos de comunicación: DTOs compatibles, deserialización tolerante, BFF sin lógica de negocio, y rutas correctamente declaradas en Kong.

Pipeline: discovery → contratos de DTOs → reglas BFF → rutas Kong → tabla de hallazgos → veredicto.

## Severidades

| Nivel | Criterio | Veredicto |
|-------|----------|-----------|
| **CRITICAL** | Cliente HTTP rompe silenciosamente ante cambio de campo del servidor (zero-value sin error) | NO-GO obligatorio |
| **HIGH** | BFF persiste datos, valida reglas de negocio, o hace writes a dominios core; cliente sin retry/fallback ante fallo de dependencia | NO-GO; justificación si se fuerza |
| **MEDIUM** | Nombre del campo prioritario no documentado en comentario; BFF supera señales de alarma (>5 servicios, >1000 LOC); falta circuit breaker | GO con advertencia |
| **LOW** | Campo legacy no eliminado pero ya documentado como candidato a limpiar; nomenclatura de servicio inconsistente | GO |

---

## Fase 0 — Discovery

```bash
# Clientes HTTP entre servicios
find . -name "*.go" | xargs grep -l "http.Client\|http.NewRequest\|json.Unmarshal\|json.Decode" 2>/dev/null | \
  grep -iE "client|adapter|external" | grep -v "_test.go"

# Identificar BFFs
find . -name "*.go" | xargs grep -l "PIMClient\|StockClient\|IAMClient\|TenantClient" 2>/dev/null | grep -v "_test.go"

# Ver configuración de Kong
find . -name "kong.yml" -o -name "kong.yaml" 2>/dev/null | head -3
```

Construir mapa de dependencias:

| Consumidor | Proveedor | Campo clave | Endpoint |
|------------|-----------|-------------|----------|
| onboarding-service | iam-service | `items` / `roles` | `GET /api/v1/roles` |
| catalog-bff | pim-service | `items` | `GET /api/v1/products/:id` |
| catalog-bff | stock-service | `availability` | `GET /api/v1/availability/:sku` |

---

## Fase 1 — Compatibilidad de DTOs

### 1a. Paginación estándar del ecosistema

El IAM service y todos los servicios del monorepo usan paginación estándar con el campo `items`:

```json
{
  "items": [...],
  "total": 42,
  "page": 1,
  "page_size": 10
}
```

**CRITICAL si**: un cliente deserializa un array en un campo diferente (`roles`, `data`, `results`) sin tener un fallback al campo `items`, y el servidor ya migró.

Patrón correcto — deserialización tolerante con prioridad documentada (onboarding-service ADR-002):

```go
// infrastructure/client/iam_client.go
var result struct {
    Items []*port.RoleResponse `json:"items"` // formato monorepo (paginación estándar) — PRIORIDAD
    Roles []*port.RoleResponse `json:"roles"` // backward compatibility (repo original)
}
if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
    return nil, fmt.Errorf("decode roles response: %w", err)
}

// Priorizar items sobre roles
roles := result.Items
if len(roles) == 0 && len(result.Roles) > 0 {
    roles = result.Roles
}
```

**Regla**: el comentario inline explica qué campo tiene prioridad y por qué. Sin comentario + campo ambiguo → MEDIUM.

### 1b. Campos requeridos vs opcionales

```bash
# Buscar structs de respuesta en clientes HTTP
grep -rn "json:\"" --include="*.go" \
  $(find . -path "*/client/*" -o -path "*/port/*") 2>/dev/null | grep -v "_test.go" | head -30
```

Para cada struct de respuesta en un cliente HTTP:
- ¿Hay campos que el servidor puede omitir y el cliente los asume como no-nulos? → HIGH.
- ¿El cliente chequea si el array resultante está vacío después de decodificar? Si espera al menos un elemento y no lo verifica → CRITICAL (zero-value silencioso).

---

## Fase 2 — Reglas del patrón BFF

Aplica a `catalog-bff-service` y cualquier futuro BFF en el ecosistema (ADR-001).

### Permitido en un BFF

- Llamar a múltiples servicios y mergear respuestas.
- Transformaciones simples de mapeo (renombrar campos, aplanar estructuras).
- Cache de lecturas en memoria con TTL.
- Retry y circuit breaker.
- Logging y métricas.
- Autenticación / extracción del JWT para propagar headers.

### CRITICAL / HIGH si el BFF hace

```bash
# ¿El BFF tiene migrations/ o hace INSERT/UPDATE/DELETE?
find . -path "*/catalog-bff*" -name "*.sql" 2>/dev/null
grep -rn "INSERT\|UPDATE\|DELETE\|db.Exec" \
  $(find . -path "*/catalog-bff*" -name "*.go") 2>/dev/null | grep -v "_test.go"
```

| Violación | Severidad |
|-----------|-----------|
| BFF persiste datos (tiene DB propia con writes de dominio) | CRITICAL |
| BFF valida reglas de negocio (`if stock < minimo { return error }`) | HIGH |
| BFF hace writes a dominios core (POST/PUT/DELETE a PIM, Stock, etc.) | HIGH |
| BFF supera ~1000 LOC (señal de God Service) | MEDIUM |
| BFF llama a más de 5 servicios | MEDIUM |
| Lógica de merge se volvió compleja (transformaciones condicionales > 50 LOC) | MEDIUM |

### Señales de alarma para refactorizar

```bash
# Contar LOC del BFF (excluyendo tests y vendor)
find . -path "*/catalog-bff*" -name "*.go" ! -name "*_test.go" | xargs wc -l 2>/dev/null | tail -1

# Ver cuántos servicios externos llama
grep -rn "http.NewRequest\|http.Get\|Client.Do" \
  $(find . -path "*/catalog-bff*" -name "*.go") 2>/dev/null | grep -v "_test.go" | \
  grep -oE '"(http|https)://[^"]*"' | sort -u
```

---

## Fase 3 — Rutas vía Kong

Todos los servicios del ecosistema exponen sus rutas a través de `lab-kong`. Los clientes entre servicios deben usar nombres de contenedor directamente (red `lab-network`) en el lab, o pasar por Kong en producción.

```bash
# Ver configuración de Kong
cat infra/kong/kong.yml 2>/dev/null || find . -name "kong.yml" | xargs cat 2>/dev/null | head -80
```

Para cada cliente HTTP interno:
- ¿Usa el nombre de host correcto del contenedor? (ej. `mc-pim-service:8090`, no `localhost:8090`) → HIGH si usa localhost en Docker.
- ¿Las rutas declaradas en `kong.yml` coinciden con las que usa el cliente? → CRITICAL si hay mismatch.
- ¿Los servicios del BFF están declarados como `upstream` separados? → LOW si no (impide circuit breaking per-upstream).

Convención de nombres en `lab-network`:

| Servicio | Host interno | Puerto |
|----------|-------------|--------|
| IAM | `mc-iam-service` | `8080` |
| PIM | `mc-pim-service` | `8090` |
| Stock | `mc-stock-service` | `8100` |
| Sales | `mc-sales-service` | `8120` |
| Tenant | `mc-tenant-service` | `8120` |
| Kong proxy | `lab-kong` | `8000` |

---

## Fase 4 — Nomenclatura de servicios

```bash
# Verificar que "catalog" se usa consistentemente (no "product-read", "storefront", etc.)
grep -rn "product.read.service\|storefront.service\|catalog.query" --include="*.go" --include="*.yml" . 2>/dev/null
```

La decisión del ecosistema (ADR-001): el servicio de composición se llama `catalog-bff-service` — "catalog" (lo que se puede vender/mostrar), no "product" (ya usado por PIM). Inconsistencias en nombres de rutas, variables de entorno o servicios de Kong → LOW.

---

## Tabla de hallazgos

```
| # | Severity | Fase | Archivo / Recurso          | Problema                                         | Fix sugerido                                              |
|---|----------|------|----------------------------|-------------------------------------------------|-----------------------------------------------------------|
| 1 | CRITICAL | 1a   | iam_client.go:34           | Solo deserializa `roles`, sin fallback a `items` | Agregar struct con ambos campos; priorizar items           |
| 2 | HIGH     | 2    | catalog-bff/handler.go:88  | BFF hace POST a PIM (write a dominio core)       | Mover la escritura al servicio core correspondiente        |
| 3 | HIGH     | 3    | iam_client.go:12           | URL hardcodeada a localhost:8080 en Docker       | Usar variable de entorno IAM_SERVICE_URL con nombre de host |
| 4 | MEDIUM   | 1b   | pim_client.go:45           | Campo prioritario sin comentario explicativo     | Agregar comentario: // formato monorepo — PRIORIDAD         |
| 5 | MEDIUM   | 2    | catalog-bff/             | BFF supera 1200 LOC — señal de God Service       | Revisar si hay lógica de negocio infiltrada para extraer   |
| 6 | LOW      | 1a   | iam_client.go:37           | Campo `roles` candidato a limpiar                | Eliminar cuando IAM legacy sea dado de baja                |
```

---

## Veredicto

**NO-GO** si hay CRITICAL o HIGH:
```
❌ NO-GO — contratos rotos o BFF con responsabilidades indebidas:
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

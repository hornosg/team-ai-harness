# API Standards (Always-On)

> Estándares de diseño de APIs del proyecto. Referenciar desde PROJECT.md RULE-XX.

## Formato de respuesta

> Elegir y documentar el formato estándar del proyecto.

### Opción A: Envelope estándar

```json
// Éxito
{
  "data": { ... },
  "meta": {
    "timestamp": "2026-04-30T12:00:00Z",
    "version": "1.0"
  }
}

// Error
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "El recurso solicitado no existe",
    "details": { ... }
  }
}
```

### Opción B: REST puro (sin envelope)

- 200 OK con body directo para éxito
- 4XX/5XX con RFC 7807 Problem Details para errores

```json
{
  "type": "https://api.example.com/errors/not-found",
  "title": "Resource not found",
  "status": 404,
  "detail": "El recurso con ID 123 no existe"
}
```

---

## Versionado

```
/api/v1/[recurso]
/api/v2/[recurso]
```

**Regla:** Las versiones se deprecan con al menos 2 meses de antelación y header `Deprecation`.

---

## Naming conventions

- Sustantivos en plural para colecciones: `/orders`, `/users`, `/products`
- Kebab-case en URLs: `/order-items`, no `/orderItems`
- camelCase en JSON bodies
- SCREAMING_SNAKE_CASE para códigos de error: `PAYMENT_FAILED`

---

## Paginación

```json
// Request
GET /api/v1/products?page=1&limit=20&sort=createdAt:desc

// Response
{
  "data": [...],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 150,
    "pages": 8
  }
}
```

---

## Autenticación

```
Authorization: Bearer <JWT>
```

- Access token: [duración — ej: 15 minutos]
- Refresh token: [duración — ej: 7 días]
- Rotation: refresh token se invalida en cada uso

[Si multitenant: `X-Tenant-ID: <uuid>` — requerido en todo request autenticado]

---

## [AGREGAR estándares específicos del proyecto]

---
name: kong
description: Patrones de API Gateway con Kong. Routing declarativo (decK), plugins (auth, rate limiting, CORS, observabilidad), modo DB-less, y convenciones de seguridad. Invocar al diseñar, revisar o modificar la capa de gateway, o cuando todo el tráfico debe pasar por Kong.
triggers:
  - "kong"
  - "api gateway"
  - "configurar el gateway"
  - "rate limiting"
  - "deck"
  - "plugin de kong"
---

# Kong API Gateway — Patrones y Convenciones

> El gateway es el borde del sistema: todo lo que entra pasa por acá. Cada decisión de Kong tiene impacto de seguridad y disponibilidad. Cambios que tocan auth, rate limiting o routing de servicios de pago → **L4** (ver `config/ceremony-levels.yaml`).

## Principio rector

Kong **enruta y aplica políticas transversales** (auth, rate limiting, CORS, observabilidad). **No contiene lógica de negocio.** Si una decisión depende del dominio, va en el servicio, no en el gateway.

## Modo de operación: declarativo (DB-less) por defecto

Preferí **DB-less + config declarativa** versionada en git sobre el modo con base de datos:

- Config reproducible, auditable y revisable en PR.
- Sin estado oculto en una DB de Kong.
- Deploy = aplicar un YAML. Rollback = aplicar el YAML anterior.

Gestioná la config con **decK** (declarative configuration for Kong):

```bash
deck gantry dump   --kong-addr http://localhost:8001 -o kong.yaml   # exportar estado actual
deck gantry diff   --kong-addr http://localhost:8001 -s kong.yaml   # ver qué cambiaría (revisar SIEMPRE antes de sync)
deck gantry sync   --kong-addr http://localhost:8001 -s kong.yaml   # aplicar
```

> Regla: `deck diff` antes de cada `deck sync`. Nunca aplicar a ciegas en producción.

## Estructura canónica de `kong.yaml`

```yaml
_format_version: "3.0"
_transform: true

services:
  - name: orders-service              # un service por microservicio upstream
    url: http://orders:8080
    retries: 5
    connect_timeout: 5000
    read_timeout: 60000
    routes:
      - name: orders-route
        paths: ["/api/v1/orders"]
        strip_path: false             # el servicio espera el path completo
        methods: ["GET", "POST", "PATCH"]
    plugins:
      - name: rate-limiting
        config: { minute: 120, policy: redis }
      - name: jwt                      # auth a nivel de route/service

consumers:
  - username: mobile-app
    jwt_secrets:
      - key: mobile-app-iss

plugins:                               # plugins globales (todas las requests)
  - name: cors
  - name: prometheus                   # expone métricas para tu stack
    config: { status_code_metrics: true, latency_metrics: true }
  - name: correlation-id
    config: { header_name: X-Request-Id, generator: uuid, echo_downstream: true }
```

## Plugins esenciales por categoría

| Categoría | Plugin | Cuándo |
|-----------|--------|--------|
| **Auth** | `jwt`, `oauth2`, `key-auth` | Toda ruta no pública. JWT para apps/SPAs, key-auth para servicio-a-servicio |
| **Rate limiting** | `rate-limiting` (policy `redis` en multi-nodo), `rate-limiting-advanced` | Proteger upstreams; siempre con `policy: redis` si hay más de un nodo Kong |
| **Tráfico** | `request-size-limiting`, `proxy-cache`, `request-transformer` | Defensa básica + cache de respuestas idempotentes |
| **CORS** | `cors` | SPAs/clientes web — allowlist explícita de origins, nunca `*` con credenciales |
| **Observabilidad** | `prometheus`, `correlation-id`, `opentelemetry`, `http-log`/`tcp-log` | Métricas a Prometheus, trace iniciado/propagado (W3C), logs a Loki |
| **Seguridad** | `bot-detection`, `ip-restriction`, `acl` | Endpoints sensibles / admin |

## Reglas de seguridad (no negociables)

- **Admin API (`:8001`) nunca expuesta a internet.** Bind a loopback o red interna; protegida por firewall/red privada de DO.
- **Auth en el gateway no reemplaza auth en el servicio.** El servicio valida autorización de dominio (qué puede hacer este usuario); el gateway valida autenticación (quién es).
- **Secrets fuera del YAML.** Usar variables de entorno / Kong vault references (`{vault://...}`), nunca secretos en texto plano commiteados.
- **Rate limiting con `policy: redis`** en cualquier deploy multi-nodo — `policy: local` permite saltarse el límite balanceando entre nodos.
- **`correlation-id` global** para poder correlacionar una request a través de gateway → servicios → logs (Loki) → traces.

## Routing: convenciones

- Versioná en el path: `/api/v1/...`. Breaking change → `/api/v2/...`, nunca romper v1 en caliente.
- `strip_path` explícito y consistente con lo que el upstream espera.
- Un `service` por microservicio upstream; múltiples `routes` por service si hace falta.
- Health checks activos + pasivos (circuit breaking) en upstreams críticos.

## Checklist de review de cambios en Kong

1. ¿`deck diff` revisado y adjunto al PR?
2. ¿El cambio toca auth, rate limiting o un servicio de pago? → escalar a L4 (@security obligatorio).
3. ¿Admin API sigue sin estar expuesta?
4. ¿Secrets por vault/env, no en el YAML?
5. ¿Rate limiting con `policy: redis` si hay multi-nodo?
6. ¿`correlation-id` y `prometheus` siguen activos globalmente?
7. ¿CORS con allowlist explícita?
8. ¿Rollback claro (YAML anterior versionado)?

## Integración con el resto del stack

- **Prometheus**: el plugin `prometheus` expone `/metrics` en el puerto de status (`:8100`). Scrapealo (ver skill `prometheus`).
- **Loki**: enviá access logs estructurados (JSON) vía `http-log` a un collector que los empuje a Loki, o stdout → Promtail/Alloy (ver skill `loki`).
- **Grafana**: dashboard de Kong (latencia p50/p95/p99 por route, tasa de 5xx, rate-limit rejections) — ver skill `grafana`.
- **Tracing**: el plugin `opentelemetry` inicia el trace en el borde y propaga `traceparent` (W3C) a los upstreams — ver skill `tracing`.

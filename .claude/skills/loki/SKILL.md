---
name: loki
description: Logging estructurado y agregación con Loki. Logs JSON, estrategia de labels (baja cardinalidad), LogQL para queries, pipeline de ingestión (Promtail/Alloy), retención y correlación con métricas. Invocar al diseñar logging, escribir queries LogQL o revisar la capa de logs.
triggers:
  - "loki"
  - "logql"
  - "logs"
  - "logging"
  - "promtail"
  - "agregación de logs"
---

# Loki — Logging Estructurado y Agregación

> Loki indexa **labels**, no el contenido del log. Esa es la decisión central: pocos labels de baja cardinalidad + logs estructurados que se filtran en query time. Tratar a Loki como Elasticsearch (indexar todo) lo rompe.

## Regla #1: logs estructurados (JSON)

Todo servicio loguea en **JSON a stdout**. Nada de strings concatenados.

```json
{"ts":"2026-06-09T12:00:00Z","level":"error","service":"orders","correlation_id":"abc-123","msg":"failed to charge","order_id":"...","err":"timeout"}
```

- `level`, `service`, `ts`, `msg` siempre presentes.
- `correlation_id` propagado desde Kong (header `X-Request-Id`) — permite seguir una request de punta a punta.
- **Nunca** loguear PII ni secretos: emails, documentos, números de tarjeta, tokens, passwords (ver `rules/security.md`, RULE-03). El logger debe redactar campos sensibles.

## Regla #2: labels de baja cardinalidad

Los labels son el índice de Loki. Cada combinación de valores = un stream. Alta cardinalidad = Loki lento y caro.

| Buen label (bajo, acotado) | Mal label (alta cardinalidad) |
|----------------------------|-------------------------------|
| `service`, `env`, `level` | `user_id`, `correlation_id`, `order_id` |
| `namespace`, `pod` (acotado) | `path` con IDs, `ip`, `email` |

> `correlation_id` va **en el cuerpo del log JSON**, no como label. Lo filtrás en query time con LogQL.

## Pipeline de ingestión

stdout del servicio → agente collector → Loki:

- **Grafana Alloy** (recomendado, sucesor de Promtail) o **Promtail** corren como agente, leen stdout/archivos, agregan labels mínimos y empujan a Loki.
- En Digital Ocean: si usás App Platform, capturá stdout; si usás Droplets con Docker, Alloy/Promtail con el driver de logs de Docker o leyendo `/var/log`.
- Kong: access logs en JSON vía `http-log` o stdout → mismo pipeline.

Labels que agrega el collector: `service`, `env`, `namespace`. El parsing del JSON se hace en stage de pipeline o en query time.

## LogQL: queries que vas a usar

```logql
# Errores de un servicio en la última hora
{service="orders", level="error"}

# Seguir una request completa por correlation_id (filtro de contenido)
{env="prod"} | json | correlation_id="abc-123"

# Tasa de errores por servicio (LogQL métrico)
sum(rate({level="error"}[5m])) by (service)

# Top de mensajes de error
topk(10, sum by (msg) (count_over_time({level="error"}[1h] | json)))

# Filtro de texto + parseo JSON + filtro de campo
{service="orders"} |= "charge" | json | err != ""
```

Patrón: **selector de stream `{}` primero (usa el índice) → luego filtros `|=`/`json`/`|`** (procesan el contenido). Cuanto más acote el selector, más rápida la query.

## Retención y costos

- Definí retención por entorno: prod más largo (ej. 30d), staging corto (ej. 7d).
- Loki con storage de objetos (Spaces de Digital Ocean / S3-compatible) escala barato; evitá disco local para volúmenes serios.
- Logs de debug ruidosos: bajá el nivel en prod (`info`+) y subí a `debug` puntualmente. No retengas debug 30 días.

## Correlación con el resto del stack

El oro está en saltar **métrica → log → causa**:

1. Spike de 5xx en Grafana (Prometheus).
2. Click → data link a Loki filtrando `{service="X", level="error"}` en la misma ventana de tiempo.
3. Tomás un `correlation_id` del log y reconstruís toda la request (gateway + servicios).

Esto requiere: `correlation-id` consistente desde Kong, labels `service`/`env` coherentes entre métricas y logs, y JSON estructurado.

## Checklist de logging listo

1. ¿Logs en JSON a stdout, con `level`/`service`/`ts`/`msg`?
2. ¿`correlation_id` en el cuerpo (no como label)?
3. ¿Cero PII/secretos en logs (redacción activa)?
4. ¿Labels de baja cardinalidad solamente?
5. ¿Retención definida por entorno?
6. ¿Storage de objetos para volúmenes de prod?

## Integración

- **Grafana** consume Loki como datasource (ver skill `grafana`).
- **Prometheus** + Loki + Grafana = stack completo (ver skill `observability-stack`).
- Dueño operativo: agente `dev-monitoreo`. Logging en código: `dev-senior-backend`.

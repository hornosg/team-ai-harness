---
name: prometheus
description: Instrumentación de métricas y alerting con Prometheus. Convenciones de naming, los cuatro golden signals, RED/USE, PromQL para queries y alertas, recording rules. Invocar al instrumentar servicios Go/Python, definir alertas, o revisar métricas.
triggers:
  - "prometheus"
  - "promql"
  - "métricas"
  - "alerta"
  - "alerting"
  - "instrumentar"
  - "golden signals"
---

# Prometheus — Métricas y Alerting

> Las métricas responden "¿está sano el sistema?". Instrumentá con intención: cada métrica debe poder usarse en un dashboard o una alerta. Métricas que nadie mira son deuda.

## Qué medir: golden signals + RED/USE

Empezá por los **cuatro golden signals** en cada servicio:

| Signal | Qué | Métrica típica |
|--------|-----|----------------|
| **Latency** | Tiempo de respuesta (separar éxito de error) | `http_request_duration_seconds` (histogram) |
| **Traffic** | Demanda sobre el sistema | `http_requests_total` (counter) |
| **Errors** | Tasa de fallos | `http_requests_total{code=~"5.."}` |
| **Saturation** | Qué tan lleno está | uso de CPU/mem/conexiones de pool |

- **RED** (para servicios request-driven): **R**ate, **E**rrors, **D**uration → mapea a los signals.
- **USE** (para recursos): **U**tilization, **S**aturation, **E**rrors → CPU, memoria, disco, pool de DB.

## Convenciones de naming (estrictas)

- `snake_case`, con sufijo de unidad: `_seconds`, `_bytes`, `_total` (counters), `_ratio`.
- Nombre = `<namespace>_<subsystem>_<unidad>`: `orders_http_request_duration_seconds`.
- Counters siempre terminan en `_total`.
- **Cuidado con la cardinalidad**: nunca uses como label algo de alta cardinalidad (user_id, request_id, email, path con IDs). Cada combinación de labels = una serie temporal en memoria. Esto tumba Prometheus.
  - Bien: `route="/api/v1/orders/:id"`, `method`, `status_code`.
  - Mal: `path="/api/v1/orders/abc-123-def"`, `user="..."`.

## Tipos de métrica

| Tipo | Uso | Ejemplo |
|------|-----|---------|
| Counter | Sólo sube (requests, errores) | `requests_total` |
| Gauge | Sube y baja (en vuelo, temperatura) | `inflight_requests`, `queue_depth` |
| Histogram | Distribución (latencias, tamaños) | `request_duration_seconds` → permite p50/p95/p99 |
| Summary | Cuantiles precalculados (raro; preferí histogram) | — |

> Para latencias usá **histogram**, no summary: los histograms se pueden agregar entre instancias; los summaries no.

## Instrumentación

**Go** (cliente oficial `prometheus/client_golang`):
```go
var reqDuration = prometheus.NewHistogramVec(
  prometheus.HistogramOpts{
    Name:    "http_request_duration_seconds",
    Buckets: prometheus.DefBuckets, // ajustar a tu SLO
  }, []string{"route", "method", "status_code"})
// exponer /metrics con promhttp.Handler()
```

**Python** (`prometheus_client`, integra con FastAPI):
```python
from prometheus_client import Histogram
REQ = Histogram("http_request_duration_seconds", "...", ["route","method","status_code"])
# exponer /metrics con make_asgi_app()
```

**Kong**: el plugin `prometheus` ya expone métricas del gateway — sólo hay que scrapearlas.

## PromQL: queries que vas a usar siempre

```promql
# Tasa de requests por segundo (últimos 5m)
sum(rate(http_requests_total[5m])) by (route)

# Error rate (% de 5xx)
sum(rate(http_requests_total{status_code=~"5.."}[5m]))
  / sum(rate(http_requests_total[5m]))

# Latencia p95 desde un histogram
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, route))

# Saturación de pool de conexiones DB
db_connections_in_use / db_connections_max
```

## Alerting: reglas que importan

Alertá sobre **síntomas que el usuario siente**, no sobre causas internas. Toda alerta debe ser accionable.

```yaml
groups:
  - name: slo-alerts
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service)
            / sum(rate(http_requests_total[5m])) by (service) > 0.02
        for: 5m
        labels: { severity: page }
        annotations:
          summary: "{{ $labels.service }}: error rate > 2% (5m)"
          runbook: "https://.../runbooks/high-error-rate"

      - alert: HighLatencyP95
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)) > 0.5
        for: 10m
        labels: { severity: ticket }
```

**Reglas de oro del alerting:**
- Cada alerta `severity: page` debe justificar despertar a alguien. Si no, es `ticket` o `warning`.
- Toda alerta lleva `runbook` en las annotations.
- Usá `for:` para evitar flapping.
- Preferí **alertas basadas en SLO / error budget burn rate** sobre umbrales estáticos arbitrarios.

## Recording rules

Precalculá queries caras/repetidas para dashboards rápidos:
```yaml
- record: service:request_error_rate:ratio5m
  expr: sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service)
        / sum(rate(http_requests_total[5m])) by (service)
```

## Integración con el stack

- **Kong** expone métricas vía plugin `prometheus` → agregá un scrape job.
- **Grafana** consume Prometheus como datasource (ver skill `grafana`).
- **Alertmanager** rutea las alertas (Slack, PagerDuty, email).
- Dueño operativo: agente `dev-monitoreo`. Instrumentación en código: `dev-senior-backend`.

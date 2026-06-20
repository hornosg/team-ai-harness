---
name: tracing
description: Tracing distribuido con OpenTelemetry y Grafana Tempo. Instrumentación de servicios Go (Gin) y Python (FastAPI), propagación de contexto desde Kong, spans con atributos, y correlación trace↔logs↔métricas. Tercer pilar de observabilidad. Invocar al instrumentar tracing, diagnosticar latencia entre servicios o cerrar el loop de observabilidad.
triggers:
  - "tracing"
  - "trace"
  - "opentelemetry"
  - "otel"
  - "tempo"
  - "span"
  - "latencia entre servicios"
  - "distributed tracing"
---

# Tracing Distribuido — OpenTelemetry + Tempo

> El tercer pilar. Métricas dicen *que* algo está lento; logs dicen *qué* pasó en un caso; **traces dicen dónde se fue el tiempo** a través de gateway y servicios. Sin tracing, diagnosticar latencia en un sistema distribuido es adivinar.

## Decisión de stack

- **Instrumentación:** OpenTelemetry (OTel) SDK — estándar vendor-neutral. Nunca instrumentes contra un backend propietario.
- **Backend:** **Grafana Tempo** — se integra nativo con tu Grafana (mismo panel que Prometheus/Loki) y guarda traces en object storage (Spaces de DO, barato). Alternativa: Jaeger si ya lo tenés.
- **Export:** OTLP (gRPC o HTTP) → OTel Collector → Tempo. El Collector desacopla los servicios del backend (podés cambiar Tempo por otro sin tocar código).

```
Servicio (OTel SDK) ──OTLP──▶ OTel Collector ──▶ Tempo ──▶ Grafana (Explore + trace view)
```

## El hilo conductor: `trace_id` + propagación W3C

Una request genera un **trace** compuesto de **spans** (un span por operación: handler, query DB, llamada a otro servicio). El `trace_id` viaja entre servicios vía el header estándar **W3C `traceparent`**.

```
Cliente → Kong (inicia trace, header traceparent)
        → Servicio A (span: handler → span: query DB)
        → Servicio B (continúa el MISMO trace, no uno nuevo)
```

Requisitos:
- **Kong**: plugin `opentelemetry` para iniciar/propagar el trace en el borde (ver skill `kong`). Alinea con `correlation-id`.
- **Propagación W3C TraceContext** habilitada en todos los servicios (es el default de OTel).
- El `trace_id` se loguea en cada log JSON (campo `trace_id`) para saltar trace ↔ logs.

## Instrumentación — Go (Gin)

```go
// internal/infrastructure/http/middleware/otel.go
import (
    "go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
)

// En el router (ver skill hexagonal-go): r.Use(otelgin.Middleware("orders-service"))
```

```go
// cmd/api/main.go — bootstrap del tracer
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/resource"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
    exp, err := otlptracegrpc.New(ctx) // endpoint via OTEL_EXPORTER_OTLP_ENDPOINT
    if err != nil { return nil, err }
    tp := sdktrace.NewTracerProvider(
        sdktrace.WithBatcher(exp),
        sdktrace.WithResource(resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceName("orders-service"),
            semconv.DeploymentEnvironment("prod"),
        )),
        sdktrace.WithSampler(sdktrace.ParentBased(sdktrace.TraceIDRatioBased(0.1))), // 10% en prod
    )
    otel.SetTracerProvider(tp)
    return tp, nil
}
```

Spans manuales en operaciones que importan (query DB, llamada externa):
```go
ctx, span := otel.Tracer("orders").Start(ctx, "PgOrderRepository.Save")
defer span.End()
span.SetAttributes(attribute.String("order.id", order.ID().String()))
// ... si err: span.RecordError(err); span.SetStatus(codes.Error, "save failed")
```

> El `ctx` ya se propaga porque hexagonal-go pasa `context.Context` como primer parámetro en todo lo que toca I/O. Esa regla es lo que hace el tracing trivial.

> **DB con `database/sql`**: envolvé el driver con [`otelsql`](https://github.com/XSAM/otelsql) para spans automáticos de cada query (`otelsql.Open("postgres", dsn, ...)`), además de los spans manuales en operaciones clave.

## Instrumentación — Python (FastAPI)

```python
# infrastructure/observability/tracing.py
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased

def init_tracing(service_name: str) -> None:
    provider = TracerProvider(
        resource=Resource.create({"service.name": service_name, "deployment.environment": "prod"}),
        sampler=ParentBased(TraceIdRatioBased(0.1)),  # 10% en prod
    )
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))  # OTEL_EXPORTER_OTLP_ENDPOINT
    trace.set_tracer_provider(provider)

# main.py — auto-instrumentación de FastAPI + SQLAlchemy
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
FastAPIInstrumentor.instrument_app(app)
SQLAlchemyInstrumentor().instrument(engine=engine.sync_engine)
```

Span manual cuando hace falta granularidad:
```python
tracer = trace.get_tracer("orders")
with tracer.start_as_current_span("place_order_usecase") as span:
    span.set_attribute("customer.id", str(params.customer_id))
```

## Sampling: no traces el 100%

- **Dev/staging:** 100% (`AlwaysOn`) para ver todo.
- **Prod:** `ParentBased(TraceIDRatioBased(0.05–0.1))` — 5–10%. **ParentBased** respeta la decisión del trace iniciado en Kong, así un trace es completo o no existe (no medio trace).
- Considerá **tail sampling** en el OTel Collector para quedarte siempre con los traces que tienen error o latencia alta, sampleando el resto.

## Atributos: qué sí y qué no

- **Sí:** `service.name`, `http.route` (sin IDs), `db.system`, `order.id` (id de negocio acotado), `http.status_code`.
- **No:** PII, secretos, tokens, payloads completos. Igual que en logs (RULE-03). Un span con un número de tarjeta es un incidente.

## Correlación: el pago del esfuerzo

El stack se vuelve uno solo cuando saltás entre señales en Grafana:

1. **Métrica** (Prometheus): spike de latencia p95 en `orders`.
2. **Trace** (Tempo): abrís un trace lento → ves que el 80% del tiempo está en una query a la DB.
3. **Log** (Loki): del span con error saltás al log por `trace_id` y ves el mensaje exacto.

Para que funcione: `trace_id` en los logs JSON, *exemplars* en las métricas de Prometheus (linkean una métrica a un trace de ejemplo), y los tres datasources en el mismo Grafana. Ver skill `observability-stack`.

## Checklist de tracing listo

1. ¿Kong inicia/propaga el trace (plugin `opentelemetry`, W3C traceparent)?
2. ¿Todos los servicios propagan TraceContext (default OTel) — el trace no se corta entre servicios?
3. ¿`trace_id` en cada log JSON?
4. ¿Sampling razonable en prod (ParentBased ~10%), no 100%?
5. ¿Spans en las operaciones que importan (DB, llamadas externas) con `RecordError` en fallos?
6. ¿Cero PII/secretos en atributos de span?
7. ¿Export vía OTLP → Collector → Tempo, no contra un backend hardcodeado?

## Integración con el stack

- **Kong** (skill `kong`): inicia el trace en el borde.
- **Go/Python** (skills `hexagonal-go`, `hexagonal-python`): el `context.Context` / contexto async propaga el span.
- **Grafana** (skill `grafana`): Tempo como datasource, trace view + correlación.
- **Loki/Prometheus**: `trace_id` en logs, exemplars en métricas.
- **Digital Ocean** (skill `digital-ocean`): Tempo + Collector en Droplets (VPC privada), traces en Spaces.
- Panorama completo: skill `observability-stack`. Dueño operativo: agente `dev-monitoreo`.

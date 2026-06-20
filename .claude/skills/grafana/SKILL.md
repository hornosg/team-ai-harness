---
name: grafana
description: Dashboards, SLOs y visualización en Grafana. Estructura de dashboards por audiencia, paneles efectivos, dashboards-as-code (provisioning), alerting unificado y correlación métricas/logs/traces. Invocar al construir dashboards, definir SLOs o revisar observabilidad visual.
triggers:
  - "grafana"
  - "dashboard"
  - "slo"
  - "panel"
  - "visualización"
  - "tablero"
---

# Grafana — Dashboards y SLOs

> Un dashboard existe para responder una pregunta concreta a una audiencia concreta. Si no podés decir qué pregunta responde y quién lo mira, no lo construyas.

## Dashboards por audiencia (no uno gigante para todos)

| Dashboard | Audiencia | Responde |
|-----------|-----------|----------|
| **Executive / SLO** | Liderazgo, on-call de alto nivel | ¿Cumplimos el SLO? ¿Cuánto error budget queda? |
| **Service overview (RED)** | Dev del servicio, on-call | Rate, Errors, Duration del servicio |
| **Resource (USE)** | DevOps/SRE | CPU, memoria, disco, pools, saturación |
| **Gateway (Kong)** | DevOps, on-call | Latencia por route, 5xx, rate-limit rejections |

Regla: **top-down**. Arriba el SLO/salud general; abajo el detalle para diagnosticar. El que mira debe poder ir del síntoma a la causa scrolleando.

## Anatomía de un panel efectivo

- **Un panel = una pregunta.** Título en forma de pregunta o métrica clara ("Error rate por servicio", no "Panel 3").
- Unidades correctas (segundos, %, req/s) — Grafana las formatea si las seteás.
- Thresholds visuales alineados al SLO (verde/amarillo/rojo).
- Para latencia mostrá **p50, p95, p99 juntas** — el promedio miente.
- Variables de template (`$service`, `$env`, `$route`) para reusar un dashboard en todos los servicios.
- Anotaciones de deploys: marcá releases en el eje temporal para correlacionar cambios con regresiones.

## Dashboards-as-code (provisioning)

No construyas dashboards a mano en la UI y los dejes ahí: se pierden, no se versionan, no se revisan.

- Exportá el JSON del dashboard y versionalo en el repo (`observability/grafana/dashboards/*.json`).
- Provisioná datasources y dashboards por archivo:

```yaml
# provisioning/dashboards/dashboards.yaml
apiVersion: 1
providers:
  - name: 'team-dashboards'
    folder: 'Services'
    type: file
    options: { path: /var/lib/grafana/dashboards }
```

```yaml
# provisioning/datasources/datasources.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    isDefault: true
  - name: Loki
    type: loki
    url: http://loki:3100
```

Cambios a dashboards → PR → review. Igual que el código.

## SLOs en Grafana

Definí SLOs explícitos y mostralos:

- **SLI**: el indicador (ej. % de requests con latencia < 300ms y status < 500).
- **SLO**: el objetivo (ej. 99.5% en 30 días).
- **Error budget**: `1 - SLO`. Mostrá el budget consumido y el **burn rate**.

```promql
# Disponibilidad (SLI) últimos 30d
sum(rate(http_requests_total{status_code!~"5.."}[30d]))
  / sum(rate(http_requests_total[30d]))
```

Panel de error budget: cuando el burn rate se acelera, es señal de frenar features y estabilizar (conecta con el agente `dev-monitoreo` y la decisión de ceremony level).

## Correlación métricas → logs → traces

El valor real del stack está en saltar de un spike a su causa:

- En un panel de Prometheus, configurá **data links** a Loki filtrando por el mismo `service`/`correlation_id`.
- Del log en Loki, saltá al trace si tenés tracing.
- Esto exige `correlation-id` consistente desde Kong (ver skill `kong`) y labels coherentes (`service`, `env`) en métricas y logs.

## Alerting unificado

Grafana puede centralizar alertas de Prometheus y Loki. Pero:
- Si ya tenés Alertmanager, mantené las alertas críticas ahí (single source of truth) y usá Grafana para visualizar.
- No dupliques la misma alerta en Prometheus y Grafana — definí dónde vive y respétalo.

## Checklist de un dashboard listo

1. ¿Qué pregunta responde y quién lo mira? (escrito en la descripción)
2. ¿Top-down: salud arriba, detalle abajo?
3. ¿Latencia con p50/p95/p99, no promedio?
4. ¿Variables de template para reuso?
5. ¿Anotaciones de deploy?
6. ¿JSON versionado y provisionado, no hecho a mano?
7. ¿Data links a Loki para diagnosticar?

## Integración con el stack

- Datasources: **Prometheus** (métricas) y **Loki** (logs).
- Dueño: agente `dev-monitoreo`. Corre en Digital Ocean (ver skill `digital-ocean`).
- Para el panorama completo del stack, ver skill `observability-stack`.

---
name: observability-stack
description: Visión integral de observabilidad sobre Prometheus + Grafana + Loki. Cuándo usar métricas vs logs, SLO/error budget, correlación de señales y flujo de diagnóstico de incidentes. Punto de entrada que rutea a las skills específicas (prometheus, grafana, loki). Invocar al diseñar observabilidad de un servicio nuevo o instrumentar un incidente.
triggers:
  - "observabilidad"
  - "observability"
  - "monitoreo"
  - "stack de monitoreo"
  - "instrumentar un servicio"
  - "diagnóstico de incidente"
---

# Observability Stack — Prometheus + Grafana + Loki

> Skill paraguas. Da la estrategia y deriva al detalle: instrumentación de métricas → skill `prometheus`; dashboards y SLOs → skill `grafana`; logging → skill `loki`. Para alertas y respuesta a producción, el dueño operativo es el agente `dev-monitoreo`.

## Los tres pilares y para qué sirve cada uno

| Señal | Herramienta | Responde | Cardinalidad |
|-------|-------------|----------|--------------|
| **Métricas** | Prometheus | ¿Está sano? ¿Cumple SLO? (agregado, barato) | Baja — labels acotados |
| **Logs** | Loki | ¿Qué pasó exactamente en este caso? | Eventos discretos, contexto rico |
| **Traces** | OpenTelemetry + Tempo (skill `tracing`) | ¿Dónde se fue el tiempo en esta request? | Por request (muestreado) |

Regla mental: **métricas para detectar, logs para diagnosticar.** Alertás sobre métricas (síntoma agregado); investigás en logs (caso concreto).

## El hilo conductor: `correlation_id`

Todo el stack se vuelve útil cuando una sola request es rastreable de punta a punta:

```
Cliente → Kong (genera/propaga X-Request-Id)
        → Servicio (loguea correlation_id en JSON, expone métricas)
        → Prometheus (métrica agregada)  ── detectás el spike
        → Loki (filtrás por correlation_id) ── encontrás la causa
```

Requisitos transversales (no opcionales):
- Kong con plugin `correlation-id` global (ver skill `kong`).
- Labels coherentes en métricas y logs: `service`, `env`.
- Logs JSON estructurados sin PII.

## Flujo de instrumentación de un servicio nuevo

1. **Métricas** (skill `prometheus`): exponer `/metrics` con los 4 golden signals (rate, errors, duration, saturation). Naming con unidades, baja cardinalidad.
2. **Logs** (skill `loki`): JSON a stdout con `level`/`service`/`correlation_id`, sin secretos.
3. **Dashboard** (skill `grafana`): panel RED del servicio + link a Loki. JSON versionado.
4. **SLO** (skill `grafana`): definir SLI, objetivo y error budget. Panel de burn rate.
5. **Tracing** (skill `tracing`): propagar el trace desde Kong, spans en DB y llamadas externas, `trace_id` en los logs.
6. **Alertas** (skill `prometheus`): sobre síntomas que el usuario siente, con runbook y `for:`.

## SLO y error budget como herramienta de decisión

- SLO define el nivel de servicio aceptable; el **error budget** (`1 - SLO`) es cuánto te podés permitir romper.
- Budget sano → libertad para mover rápido y tomar riesgo.
- Budget quemándose rápido → frenar features, estabilizar. Esto alimenta la priorización del `dev-project-leader` y puede subir el ceremony level de cambios relacionados.

## Flujo de diagnóstico de un incidente

1. **Alerta** dispara (Prometheus/Alertmanager) → severidad `page` o `ticket`.
2. **Dashboard SLO/RED** (Grafana): ¿qué servicio, desde cuándo, qué señal? Correlacioná con anotaciones de deploy.
3. **Logs** (Loki): filtrá por `service` + `level=error` en la ventana; tomá un `correlation_id`.
4. **Reconstruí la request** por `correlation_id` a través de gateway y servicios.
5. **Mitigá** (rollback del deploy marcado, feature flag, scale).
6. **Postmortem**: el agente `dev-monitoreo` documenta causa raíz, cierra el loop con el equipo y guarda el aprendizaje en memoria (Engram).

## Anti-patrones a evitar

- Indexar texto libre en Loki o meter alta cardinalidad como labels → mata Loki/Prometheus.
- Dashboards hechos a mano en la UI sin versionar → se pierden.
- Alertas sobre causas internas en vez de síntomas del usuario → ruido, fatiga de alertas.
- Promedio de latencia en vez de p95/p99 → esconde la cola que el usuario sí siente.
- Logs con PII/secretos → incidente de seguridad/compliance (RULE-03).

## Mapa de skills

| Necesito… | Skill |
|-----------|-------|
| Instrumentar métricas, escribir PromQL, definir alertas | `prometheus` |
| Construir dashboards, SLOs, visualización | `grafana` |
| Logging estructurado, LogQL, pipeline de logs | `loki` |
| Tracing distribuido, OpenTelemetry, Tempo | `tracing` |
| Gateway y propagación de correlation-id | `kong` |
| Dónde corre todo esto (infra, retención, storage) | `digital-ocean` |

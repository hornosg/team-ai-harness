# Planes atómicos vinculados a este proyecto

Este archivo es un índice de los planes atómicos cross-project que afectan a `team-ai-harness`. Los planes concretos viven centralizados en `/Users/hornosg/Projects/management/plans/`.

## Planes activos

| Proyecto | Plan | Archivo | Descripción | Estado |
|---|---|---|---|---|
| mercado-cercano | S2S + hexagonal | `/Users/hornosg/Projects/management/plans/mercado-cercano/2026-06-25_s2s-hex-audit-atomic.md` | Revisión S2S scoped keys + normalización hexagonal por servicio. Afecta servicios bajo `mercado-cercano/services/` y plataforma (`notification-service`, `iam-service`, etc.). | Sin empezar |
| iteye | Observabilidad SDD | `/Users/hornosg/Projects/management/plans/iteye/2026-06-25_iteye-observability-sdd-atomic.md` | Convertir iteye en observador del workflow SDD, costos y agentes. | Sin empezar |

## Proyectos con harness instalado

- `/Users/hornosg/Projects/active/team-ai-harness` (fuente canónica)
- `/Users/hornosg/Projects/active/mercado-cercano`
- `/Users/hornosg/Projects/active/iteye`
- `/Users/hornosg/Projects/platform/notification-service`

## Metodología de ejecución

- Cada plan sigue la skill `atomic-session-planning`.
- Una sola tarea `in_progress` por sesión.
- Handoff mediante Engram (`mcp_engram_mem_save` / `mcp_engram_mem_session_summary`).

## Skills relevantes

- `skills/software-development/atomic-session-planning`
- `skills/dev/hexagonal-workflow`
- `skills/dev/hexagonal-go`
- `skills/dev/go-hex-audit`

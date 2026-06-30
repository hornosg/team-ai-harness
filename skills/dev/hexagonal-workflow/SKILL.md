---
name: hexagonal-workflow
description: Workflow obligatorio para todo codigo Go escrito bajo el harness de agentes. Define cuando y quien ejecuta hexagonal-go y go-hex-audit, los gates por ceremony level, y el Definition of Done para features Go. Cargar siempre que un agente del equipo dev intervenga en un servicio Go.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [go, hexagonal, ddd, workflow, harness, ceremony, gate]
    related_skills: [hexagonal-go, go-hex-audit, code-reviewer, conventional-commit, pr-workflow]
---

# Workflow Hexagonal / DDD en el Harness de Agentes

Use this skill when un agente del equipo dev va a planificar, implementar, revisar o firmar codigo Go.

Este skill no reemplaza a `hexagonal-go` ni a `go-hex-audit`: los referencia y los ubica en el flujo SDD (`propose` / epica / task) del harness.

## Regla de oro

**Si `go-hex-audit` Phase 2 encuentra findings `CRITICAL` o `HIGH` en codigo nuevo o modificado, el PR no pasa.**

Este gate se aplica tres veces en el ciclo:

1. **Antes de asignar la implementacion** (`@technical-leader`): baseline audit.
2. **Despues de codear, antes de pedir review** (`@senior-backend` / `@junior-backend`): auto-audit.
3. **Durante el code review** (`@technical-leader`, dimension D4) y en el sign-off previo a release (`@qa`): gate final.

## Skills que este workflow referencia

| Skill | Rol | Quien la carga |
|---|---|---|
| `hexagonal-go` | Estructura de carpetas, dependency direction, patrones por layer, testing. | `@senior-backend`, `@junior-backend`, `@technical-leader` |
| `go-hex-audit` | Auditoria de acoplamiento, coverage, OpenAPI, e2e; reporte `AUDIT.md`. | `@architect`, `@technical-leader`, `@senior-backend`, `@junior-backend`, `@qa` |
| `code-reviewer` | Review en 7 dimensiones; D4 usa `go-hex-audit`. | `@technical-leader` |
| `conventional-commit`, `pr-workflow` | Cierre de la tarea. | `@dev-orchestrator` |

## Punto de entrada: SDD (`propose` -> epica -> task)

El pedido entra por `@meta-router` -> `@dev-orchestrator`.

Para una feature Go, el flujo SDD integra este workflow asi:

```
Owner -> @meta-router -> @dev-orchestrator
                              |
                              | crea ENN-*.md + actualiza roadmap.yaml
                              | vincula plan atomico en management/plans/<proyecto>/
                              | genera openspec/changes/[nombre]/tasks.md
                              |
                              v
                    @technical-leader
                    carga hexagonal-workflow, hexagonal-go, go-hex-audit
                    ejecuta go-hex-audit Phase 0 + 1 + 2 (baseline)
                              |
              +---------------+---------------+
              |                               |
              v                               v
        findings CRITICAL/HIGH          findings OK
              |                               |
              v                               v
        @architect (L3/L4)             @senior-backend / @junior-backend
        ADR + plan de normalizacion      codea con hexagonal-go
        vuelve a TL                       re-ejecuta go-hex-audit Phase 2
              |                               |
              +---------------+---------------+
                              |
                              v
                    @technical-leader
                    review D4 con go-hex-audit
                    comparar findings vs baseline
                              |
                              v
                            @qa
                    valida TEST-IDs + gate de arquitectura
                              |
                              v
                         sign-off
                              |
                              v
                    commit + push (conventional-commit + pr-workflow)
```

## Ceremony levels para codigo Go

| Nivel | Cuando aplica | Audit obligatorio |
|---|---|---|
| L1 | Quick fix en codigo Go (< 30 min, reversible, no toca dominio/infra/auth/dinero). | Opcional: al menos `go build ./...` y `go test ./...`. Corre `go-hex-audit` si el cambio toca layers. |
| L2 | Feature estandar, patrones conocidos, no cambia arquitectura. | **Si**: baseline (TL) + auto-audit (dev) + D4 (TL review) + gate QA. |
| L3 | Cambio arquitectural, migracion, nuevo bounded context o integracion critica. | **Si, con ADR**: architect disena; TL baseline; dev auto-audit; D4 + security si aplica; QA gate. |
| L4 | Money / auth / compliance / datos sensibles. | **Si, inamovible**: `dev-architect` + `dev-security` + `go-hex-audit` en todos los momentos. |

Regla: si el pedido toca `domain/`, `application/`, `infrastructure/` o contratos de API, aplica al menos L2.

## `@technical-leader` — antes de asignar

1. Cargar este skill y `go-hex-audit`.
2. Ejecutar **Phase 0 (Discovery) + Phase 1 (Compile) + Phase 2 (Architecture Audit)** sobre el servicio a modificar.
3. Evaluar findings:

| Severity | Accion |
|---|---|
| `CRITICAL` / `HIGH` | **Bloquea la asignacion**. Escalar a `@architect` para ADR + plan de normalizacion antes de agregar features nuevas. |
| `MEDIUM` / `LOW` | Documentar en `openspec/changes/[nombre]/tasks.md` y mitigar. No bloquean salvo que esten en el path del cambio. |

4. Cada **FILE-ID** del plan debe declarar layer: `Domain`, `Application`, `Infrastructure`. Si un FILE-ID no encaja, hay un problema de arquitectura por resolver antes de codear.

## `@senior-backend` / `@junior-backend` — al codear

### Antes de tocar codigo

1. Cargar `hexagonal-go`.
2. Cargar este skill y ejecutar `go-hex-audit` Phase 0+1+2 para conocer baseline.
3. Si hay findings `CRITICAL`/`HIGH`, no agregar codigo nuevo hasta consultar a `@technical-leader` o `@architect`.
4. Documentar el baseline en el PR description o en `openspec/changes/[nombre]/findings.md`.

### Durante la implementacion

- **Dominio primero**: entidades, value objects, reglas de negocio.
- **Use cases delgados**: orquestan, no implementan logica de negocio.
- **Adaptadores al final**: handlers, repos, clientes externos.
- **Dependency direction respetada**:

```
Infrastructure -> Application -> Domain
     ^                ^           ^
  depende de      depende de    no depende
  interfaces      interfaces    de nadie
  del dominio     del dominio
```

- **Handlers traducen HTTP <-> DTO**: nunca serializan entidades de dominio directamente.
- **Tests del dominio puros**: sin I/O, usando mocks de los ports del dominio.
- **Ports driven en el consumer**: un adaptador expone una interfaz cuando la consume application, no cuando la define domain (salvo domain services puros).

### Despues de codear

1. Re-ejecutar `go-hex-audit` Phase 2 sobre el area modificada.
2. **Cero findings `CRITICAL`/`HIGH`** antes de pasar a review.
3. `MEDIUM`/`LOW`: resolver si es factible; si no, documentar en PR.
4. Para Go: `go build ./...` antes de `go test ./...`.

## `@technical-leader` — code review

Usar `code-reviewer` en las 7 dimensiones. La dimension **D4 (Architecture)** incluye obligatoriamente:

1. Re-ejecutar `go-hex-audit` Phase 2.
2. Comparar findings contra el baseline del inicio de la tarea.
3. Confirmar que no se introdujeron violaciones `CRITICAL`/`HIGH`.

**Score:**

- Si `go-hex-audit` reporta `CRITICAL`/`HIGH` en codigo nuevo/modificado -> **REVISION OBLIGATORIA**, score <= 24/35.
- Sin nuevas violaciones graves -> puede aprobar (>= 30/35).

## `@qa` — sign-off

Antes de firmar release (L2+):

1. Validar TEST-IDs del plan (`openspec/changes/[nombre]/tasks.md`).
2. Ejecutar `go-hex-audit` Phase 2 como gate de arquitectura.
3. Verificar dependency direction:
   - `domain` no importa `application`, `infrastructure`, handlers, DB drivers ni frameworks HTTP.
   - `application` solo importa `domain` y sus propios ports; nunca adaptadores concretos.
   - Handlers/router no serializan entidades de dominio directamente; usan DTOs de application.

| Hallazgo | Accion |
|---|---|
| Sin findings `CRITICAL`/`HIGH` | Arquitectura OK para sign-off. |
| Findings `CRITICAL`/`HIGH` en codigo del release | **Bloquear release** — no merge hasta fix. |
| Findings preexistentes fuera del scope | Reportar como deuda tecnica documentada; no bloquean si no se tocaron. |

## `@dev-orchestrator` — cierre

Una vez QA da sign-off sin violaciones nuevas de hex/DDD:

1. `conventional-commit`: commit con formato estandar.
2. `pr-workflow`: push al branch, PR, merge controlado.
3. No push directo a `main`/`master`.

## Integracion con planes atomicos

Para iniciativas que afectan varios servicios o repos, el plan atomico vive en `/Users/hornosg/Projects/management/plans/<proyecto>/YYYY-MM-DD_<slug>.md` y se vincula desde:

- `roadmap/epicas/ENN-*.md` seccion "Plan de ejecucion atomica".
- `openspec/changes/[nombre]/tasks.md` encabezado.
- `.hermes/plans/INDEX.md` del repo afectado (si existe).

Cada tarea atomica se ejecuta en una sola sesion:
- marcar una sola tarea `in_progress`;
- verificar (`go build ./...`, luego `go test ./...`);
- guardar resultado en Engram (`mcp_engram_mem_save` / `mcp_engram_mem_session_summary`);
- sugerir la siguiente tarea lista.

## Definition of Done para features Go

- [ ] `go-hex-audit` Phase 0+1+2 ejecutado y sin findings `CRITICAL`/`HIGH` en codigo nuevo/modificado.
- [ ] FILE-IDs del plan cubren Domain / Application / Infrastructure segun corresponda.
- [ ] TEST-IDs implementados y pasando.
- [ ] Code review D4 aprobado (>= 30/35, o revisiones resueltas).
- [ ] Para L3/L4: ADR aprobado.
- [ ] Para L4: `dev-security` sign-off.
- [ ] QA sign-off con gate de arquitectura.
- [ ] Commit + PR siguiendo conventional-commit y pr-workflow.

## Referencias

- `skills/dev/hexagonal-go/SKILL.md` — guia de arquitectura hexagonal + DDD para Go.
- `skills/dev/go-hex-audit/SKILL.md` — pipeline de auditoria, coverage, OpenAPI, e2e.
- `skills/dev/code-reviewer/SKILL.md` — review en 7 dimensiones con D4.
- `skills/dev/conventional-commit/SKILL.md` — formato de commits.
- `skills/dev/pr-workflow/SKILL.md` — flujo de PR y merge.
- `docs/workflow-hexagonal-ddd.md` — version anterior del mismo workflow (mantener sincronizada con esta skill).

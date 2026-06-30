# Workflow Hexagonal / DDD en el Harness de Agentes

> Este documento describe el flujo de trabajo obligatorio para todo código Go que se escriba bajo el harness de agentes. El objetivo es garantizar que los principios de arquitectura hexagonal y DDD se respeten antes, durante y después de escribir código.

## Regla de oro

**Si `skills/dev/go-hex-audit/SKILL.md` Phase 2 encuentra findings `CRITICAL` o `HIGH` en código nuevo o modificado, el PR no pasa.**

Este gate se aplica cuatro veces en el ciclo:

1. Antes de asignar la implementación (`@technical-leader`).
2. Después de codear, antes de pedir review (`@senior-backend` / `@junior-backend`).
3. Durante el code review (`@technical-leader`, dimensión D4).
4. En el sign-off previo a release (`@qa`).

## Skills involucradas

| Skill | Cuándo usar | Quién la carga |
|---|---|---|
| `skills/dev/hexagonal-go/SKILL.md` | Siempre que se escriba código Go. Define estructura de carpetas, dependency direction, patrones por layer y testing. | `@senior-backend`, `@junior-backend`, `@technical-leader` |
| `skills/dev/go-hex-audit/SKILL.md` | Para auditar la baseline, autorevisar y gatillar. | `@architect`, `@technical-leader`, `@senior-backend`, `@junior-backend`, `@qa` |

## Flujo end-to-end

### 1. Owner pide una feature Go

**`@meta-router`** clasifica el pedido como DEV y lo rutea a **`@dev-orchestrator`**.

### 2. `@dev-orchestrator` arma la cadena

Ejemplo para una feature **L2** sobre un servicio Go:

```
@technical-leader  ← valida baseline hexagonal/DDD
  ↓
@senior-backend    ← codea con hexagonal-go + go-hex-audit
  ↓
@qa                ← gate de arquitectura + TEST-IDs
```

El Definition of Done de L2 (y superiores) exige:

- Code-review `@technical-leader` con las 7 dimensiones, incluyendo **D4 con `go-hex-audit`**.
- QA aplica el **gate de arquitectura Go** antes del sign-off.

### 3. `@technical-leader` — antes de asignar

Carga `skills/dev/go-hex-audit/SKILL.md` y ejecuta **Phase 0 (Discovery) + Phase 1 (Compile) + Phase 2 (Architecture Audit)** sobre el servicio a modificar.

**Resultados posibles:**

| Severity | Acción |
|---|---|
| `CRITICAL` / `HIGH` | **Bloquea la asignación**. Escalar a `@architect` para definir plan de normalización antes de agregar features nuevas. |
| `MEDIUM` / `LOW` | Documentar en `workspace/[nombre]/tasks.md` y mitigar en el plan. No bloquean salvo que estén en el path del cambio. |

Además, cada **FILE-ID** del plan debe declarar explícitamente su layer:

- `Domain`
- `Application`
- `Infrastructure`

Si un FILE-ID no encaja en una layer, hay un problema de arquitectura por resolver antes de codear.

### 4. `@senior-backend` / `@junior-backend` — al codear

#### Antes de tocar código

1. Cargar `skills/dev/hexagonal-go/SKILL.md` (estructura, naming, testing).
2. Ejecutar `skills/dev/go-hex-audit/SKILL.md` Phase 0+1+2 para conocer el baseline del servicio.
3. Si hay findings `CRITICAL`/`HIGH`, no agregar código nuevo hasta consultar a `@technical-leader` o `@architect`.
4. Documentar el baseline en el PR description.

#### Durante la implementación

- **Dominio primero**: entidades, value objects, reglas de negocio.
- **Use cases delgados**: orquestan, no implementan lógica de negocio.
- **Adaptadores al final**: handlers, repos, clientes externos.
- **Dependency direction respetada**:

```
Infrastructure → Application → Domain
     ↑                ↑           ↑
  depende de      depende de    no depende
  interfaces      interfaces    de nadie
  del dominio     del dominio
```

- **Handlers traducen HTTP ↔ DTO**: nunca serializan entidades de dominio directamente.
- **Tests del dominio puros**: sin I/O, usando mocks de los ports del dominio.

#### Después de codear

- Re-ejecutar `go-hex-audit` Phase 2 sobre el área modificada.
- **Cero findings `CRITICAL`/`HIGH`** antes de pasar a review.
- `MEDIUM`/`LOW` se intentan resolver; si no, se documentan en el PR.

### 5. `@technical-leader` — code review

Usa `skills/dev/code-reviewer/SKILL.md` en las 7 dimensiones. La dimensión **D4 (Architecture)** ahora incluye obligatoriamente:

- Re-ejecutar `skills/dev/go-hex-audit/SKILL.md` Phase 2.
- Comparar findings contra el baseline del inicio de la tarea.
- Confirmar que no se introdujeron violaciones `CRITICAL`/`HIGH`.

**Score:**

- Si `go-hex-audit` reporta `CRITICAL`/`HIGH` en código nuevo/modificado → **REVISIÓN OBLIGATORIA**, score ≤ 24/35.
- Sin nuevas violaciones graves → puede aprobar (≥ 30/35).

### 6. `@qa` — sign-off

Antes de firmar el release (L2+):

1. Validar TEST-IDs del plan (`workspace/[nombre]/tasks.md`).
2. Ejecutar `go-hex-audit` Phase 2 como **gate de arquitectura**.
3. Verificar dependency direction:
   - `domain` no importa `application`, `infrastructure`, handlers, DB drivers ni frameworks HTTP.
   - `application` solo importa `domain` y sus propios ports; nunca adaptadores concretos.
   - Handlers/router no serializan entidades de dominio directamente; usan DTOs de application.

**Resultado del gate:**

| Hallazgo | Acción |
|---|---|
| Sin findings `CRITICAL`/`HIGH` | ✅ Arquitectura OK para sign-off. |
| Findings `CRITICAL`/`HIGH` en código del release | 🚨 **Bloquear release** — no merge hasta fix. |
| Findings preexistentes fuera del scope | ⚠️ Reportar como deuda técnica documentada; no bloquean si no se tocaron. |

### 7. `@dev-orchestrator` — cierre

Una vez QA da sign-off sin violaciones nuevas de hex/DDD, se ejecuta:

- Commit con formato convencional (`skills/dev/conventional-commit/SKILL.md`).
- Push al branch siguiendo `skills/dev/pr-workflow/SKILL.md`.
- No push directo a `main`/`master`.

## Diagrama resumido

```
Owner → @meta-router → @dev-orchestrator
                            ↓
              ┌─────────────────────────────┐
              │ @technical-leader           │
              │ baseline go-hex-audit       │
              │ Phase 0 + 1 + 2             │
              └─────────────┬───────────────┘
                            ↓ CRITICAL/HIGH
                     ┌──────┴──────┐
                     ↓              ↓
              @architect        @senior-backend
              normalización     hexagonal-go + audit
                                autorevisión audit
                                ↓
                         @technical-leader
                         review D4 con audit
                                ↓
                              @qa
                         gate de arquitectura
                         TEST-IDs
                                ↓
                         sign-off / bloqueo
                                ↓
                           commit + push
```

## Referencias

- `skills/dev/hexagonal-go/SKILL.md` — guía de arquitectura hexagonal + DDD para Go.
- `skills/dev/go-hex-audit/SKILL.md` — pipeline de auditoría de acoplamiento, coverage, OpenAPI y e2e.
- `agents/dev/architect.md` — baseline hexagonal/DDD en la planificación y ADR.
- `agents/dev/technical-leader.md` — audit antes de asignar, D4 en review, post-audit.
- `agents/dev/senior-backend.md` — cargar `hexagonal-go` y ejecutar `go-hex-audit` antes/después de codear.
- `agents/dev/junior-backend.md` — seguir `hexagonal-go` y audit antes/después.
- `agents/dev/qa.md` — gate de arquitectura hexagonal/DDD en sign-off.
- `agents/orchestrators/dev-orchestrator.md` — cadenas y DoD con `go-hex-audit`.

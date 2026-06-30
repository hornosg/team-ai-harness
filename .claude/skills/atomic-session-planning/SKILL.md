---
name: atomic-session-planning
description: "Planificación atómica multi-sesión: descompone trabajo complejo en tareas de una sola sesión con dependencias explícitas, entregables verificables y handoff via Engram."
triggers:
  - "plan atómico"
  - "atomic planning"
  - "descomponer en tareas"
  - "plan de sesiones"
  - "qué tareas siguen"
---

# Atomic Session Planning

Usá esta skill cuando el pedido implique **múltiples pasos, servicios o sesiones** y haya que descomponerlo en unidades de trabajo que un agente pueda ejecutar de principio a fin en una sola conversación.

## Core Principle

**Una tarea = una sesión = un entregable verificable.**

Una tarea es atómica cuando:
- Tiene un único objetivo claro.
- Se completa de principio a fin sin iniciar otras tareas.
- Necesita contexto mínimo: lo carga ella misma al empezar (Engram, spec, plan).
- Termina con output verificable: tests green, archivo guardado, decisión escrita, Engram persistido.
- Declara explícitamente sus prerrequisitos.

## Cuándo usar esta skill

- El usuario pide "planificar [X]".
- Un propuesta/epic afecta más de un servicio o repo.
- Hay que coordinar trabajo entre sesiones (una tarea no entra en una sola conversación).
- Se detecta scope creep durante una sesión: detenerse, replanificar y dividir.

## Dónde vive el plan

| Tipo de iniciativa | Ubicación del plan | Índice local |
|---|---|---|
| Afecta un solo repo / un solo servicio | `.claude/plans/YYYY-MM-DD_<slug>.md` | `.claude/plans/INDEX.md` |
| Afecta varios repos o servicios | `~/Projects/management/plans/<proyecto>/YYYY-MM-DD_<slug>.md` | `.claude/plans/INDEX.md` apunta al plan centralizado |

**Regla**: si el plan es cross-project, el archivo canónico vive en `management/plans/<proyecto>/`; el repo afectado solo guarda un índice local que vincula.

## Plan Format

Usá una lista plana y numerada. Evitá subtareas anidadas.

```markdown
# Plan: [objetivo]

## Phase 1: Foundation

### Task F.1: [verbo + objeto concreto]
- **Goal:** ...
- **Files:** paths a leer/modificar
- **Commands:** tests/verificación
- **Deliverable:** qué se entrega
- **Prerequisites:** ninguno | Task X.Y done
- **Estimated:** 1 sesión

### Task F.2: ...

## Phase 2: [nombre] (depends on Phase 1)

### Task I.1: ...
- **Goal:** ...
- **Prerequisites:** F.1 done, F.2 done
- **Estimated:** 1 sesión
```

## Reglas de split/combine

**Dividir** si cualquiera de estas condiciones se cumple:
- Requeriría más de ~15 tool calls.
- Toca más de 3 concerns no relacionados.
- No se puede verificar completamente en una sesión.
- Depende de una decisión que aún no se tomó.

**Combinar** solo si dos tareas son triviales, secuenciales y ambas entran en <10 tool calls.

## Workflow de ejecución

Cuando el usuario diga "hagamos la tarea X":

1. **Cargar contexto**:
   - Leer el plan atómico (`.claude/plans/...` o `management/plans/...`).
   - `mcp_engram_mem_context` / `mcp_engram_mem_search` para estado del proyecto.
2. **Marcar** la tarea X como `in_progress`:
   - Usá `TaskUpdate` (o `TaskCreate` si no existe).
   - Nunca dejes más de una tarea `in_progress`.
3. **Ejecutar** solo la tarea X.
4. **Verificar** el deliverable.
5. **Guardar handoff** en Engram (`mcp_engram_mem_save` o `mcp_engram_mem_session_summary`).
6. **Marcar** la tarea X como `completed`.
7. **Sugerir** la siguiente tarea lista (prerrequisitos cumplidos).

## Handoff entre sesiones

Al finalizar cada tarea atómica, producí un resumen corto y guardalo en Engram:

```text
Done: [task id] — [one-line result]
Next ready: [task id] (prerequisites met)
Blocked: [task id] (waiting for [what])
```

Usá `mcp_engram_mem_session_summary` con:
- **goal**: objetivo de la sesión.
- **discoveries**: hallazgos no obvios.
- **accomplished**: qué quedó hecho.
- **next_steps**: próxima tarea lista o bloqueos.
- **relevant_files**: paths clave.

## Integración con herramientas de Claude Code

- **Planes**: leélos con `Read` desde `.claude/plans/` o `management/plans/`.
- **Tareas**: usá `TaskCreate` / `TaskUpdate` para reflejar estado.
- **Memoria**: usá las herramientas MCP de Engram (`mcp_engram_*`) según `skills/dev/memory-protocol/SKILL.md`.
- **Skills**: si la tarea requiere otra skill (ej. `hexagonal-go`, `go-hex-audit`), invocala con la tool `Skill`.

## Ejemplo de tarea atómica

```markdown
### Task H.1: Auditar uso de S2S scoped keys en notification-service
- **Goal:** Identificar todos los usos de `system:admin`, `S2S_API_KEY` y violaciones hexagonales.
- **Files:** `services/notification-service/src/**/infrastructure/client/*.go`, `src/main.go`
- **Commands:** `grep -R "S2S_API_KEY"`, `go test ./...`
- **Deliverable:** Reporte markdown guardado en `.claude/plans/findings/`
- **Prerequisites:** ninguno
- **Estimated:** 1 sesión
```

## Recuerda

- Atómico = una sesión = un deliverable concreto.
- Una sola tarea `in_progress` por vez.
- Engram es el mecanismo de handoff entre sesiones.
- El agente rutea y ejecuta un nodo a la vez; no implementa todo el grafo en una conversación.

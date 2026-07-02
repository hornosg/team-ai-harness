---
name: loop-next-task
description: Elige y ejecuta la primera tarea desbloqueada del roadmap/épica activa, pensada para correr sin el owner en el medio (driver de loop autónomo). Marca la tarea, actualiza estado y cierra con handoff en Engram.
triggers:
  - "next-task"
  - "próxima tarea"
  - "loop next task"
---

# Loop Next Task

Driver de una sola iteración de loop autónomo: elige la primera tarea `[ ]` desbloqueada del
roadmap, la ejecuta de punta a punta según su ceremony level, y deja el estado en disco +
Engram listo para que la próxima iteración (contexto fresco) retome sin ambigüedad.

Invocada como comando especial `next-task` de `@meta-router` (ver
`agents/orchestrators/meta-router.md`). No se invoca a mano salvo para depurar el loop.

## Precondición — roadmap único, multi-proyecto

Desde 2026-07-02, `roadmap.yaml` es **un solo archivo** para toda la plataforma
(`$DEVY_ROADMAP_PATH`, default `~/Projects/management/roadmap.yaml`) — ya no hay un
`roadmap.yaml` separado por scope (`platform/` vs `projects/<nombre>/`). Cada hito y cada
épica dentro de ese archivo lleva `proyecto: <nombre>` (`platform` para lab-wide, o el nombre
del proyecto cliente). Los IDs (`HNN`, `ENN`) son únicos **dentro de un proyecto**, no
globalmente — pueden colisionar entre proyectos (ej. `E24` existe en `proyecto: platform` y en
`proyecto: mercado-cercano` con contenido distinto).

**Cómo se resuelve el path y el proyecto:**
1. Path del roadmap: `$DEVY_ROADMAP_PATH` si está seteada; si no, el path que venga en
   `--roadmap <path>` (típicamente desde `scripts/loop-runner.sh`); si tampoco, fallback
   `~/Projects/management/roadmap.yaml`.
2. Proyecto: si el comando llegó como `next-task --proyecto <nombre>`, usar ese valor sin
   negociar. Si no vino explícito, inferirlo del cwd igual que cualquier pedido normal del
   meta-router (Paso 0) — con la advertencia de que esa inferencia **no es confiable** cuando
   el loop corre dentro del working directory de un servicio de un proyecto cliente (ej.
   `active/mercado-cercano/services/ledger-service` puede inferir `proyecto: mercado-cercano`
   aunque la épica objetivo sea `proyecto: platform`). Descubierto en el piloto de E33 con E24
   (2026-07-02, cuando el roadmap todavía era multi-archivo) — el mismo riesgo de inferencia
   persiste con el archivo único, ahora a nivel de filtro `proyecto:` en vez de selección de
   archivo. **Preferir siempre `--proyecto` explícito en corridas de loop no supervisadas.**

## Algoritmo

### 1. Elegir la tarea

1. Cargar `$DEVY_ROADMAP_PATH` (o el path resuelto arriba) y filtrar por el `proyecto`
   resuelto. Todo lo que sigue opera **solo** sobre `hitos:`/`epicas:` de ese `proyecto`.
2. Del subconjunto filtrado, tomar la épica con `estado: en-progreso` de mayor prioridad en el
   hito `fase_actual` de ese proyecto. Si no hay ninguna `en-progreso`, tomar la primera
   `pendiente` cuyas dependencias (árbol de ejecución, si existe para ese proyecto) estén
   satisfechas.
3. Leer el archivo de esa épica (`archivo:` en el roadmap — ya viene con el prefijo de scope
   resuelto, ej. `platform/epicas/E24-....md` o `projects/mercado-cercano/epicas/....md`,
   relativo a `management/`). Si no tiene `archivo:`, no es ejecutable por loop — devolver a
   replanificación (ver §4).
4. **Ubicar el código**: leer `management/projects/<proyecto>/PROJECT.md` (o, si la épica es de
   `proyecto: platform` pero opera sobre código de un proyecto cliente — como los retrofits RLS —
   el PROJECT.md del proyecto dueño del servicio que la épica nombra en `servicios:` o en su
   texto). Ahí está el path raíz del repo y el índice de componentes. NUNCA inferir la ubicación
   del código por cwd — el loop siempre corre desde `$DEVY_PATH`.
5. Recorrer las tareas de la épica en orden. Elegir la **primera** con checkbox `[ ]` cuyo
   `Depende de:` esté en `[x]` (o `ninguna`).
6. Si ninguna tarea cumple la condición → backlog vacío para esta épica/proyecto. Reportar
   `NEXT-TASK: empty` y salir sin marcar nada (el runner interpreta esto como fin de
   iteraciones útiles, ver `scripts/loop-runner.sh`).

### 2. Ejecutar según ceremony level

- **L1/L2**: ejecutar directo con el agente de implementación correspondiente al tipo de
  tarea (dev-senior-backend, dev-senior-frontend, dev-devops, según corresponda).
- **L3**: requiere `@dev-architect` en el diseño si la tarea lo dice explícitamente; si no,
  ejecutar directo pero dejar registrado en el handoff que fue L3.
- **L4**: ver `config/routing-rules.yaml → loop_mode` — regla "L4 nunca desatendido". La
  iteración implementa hasta el gate (build/test verdes), escribe la escalación (Engram +
  `management/escalations/YYYY-MM-DD_<slug-tarea>.md`) y **NO commitea sin sign-off**. El
  loop no se detiene por esto: sigue con la próxima tarea sin dependencias pendientes en la
  siguiente iteración.

### 3. Verificar "Hecho cuando"

Cada tarea atómica (formato `skills/dev/atomic-session-planning`) declara su criterio de
salida como comando o check verificable. Correrlo. Si falla:
- Reintentar dentro de la misma iteración si el fix es evidente y acotado.
- Si no cierra, dejar la tarea `[ ]` y anotar en el handoff qué falta — no marcar `[x]` sin
  que el criterio pase.

### 4. Casos de corte (presupuesto gobernado por contexto)

1. **Tarea L4 detectada** → escalar y continuar (§2). No es un corte de iteración, es una
   ruta de ejecución distinta dentro de la misma tarea.
2. **~50% de la ventana de contexto consumida (≈100k tokens) y la tarea no cerró** →
   checkpoint intermedio: escribir en el handoff (§5) un resumen estructurado
   `hecho / falta / próximo paso concreto` sin marcar `[x]`. La próxima iteración retoma esa
   misma tarea desde el checkpoint, no desde cero.
3. **3ra iteración consecutiva sin cerrar la misma tarea** → no es un problema de contexto,
   es que la tarea no era atómica. Devolver a replanificación: invocar
   `skills/dev/atomic-session-planning/SKILL.md` para partirla, dejar la tarea original
   marcada como bloqueada en el handoff (no en el roadmap — el split lo hace un humano o una
   sesión interactiva), y salir sin marcar `[x]`.

### 5. Cerrar la iteración

Al completar (o cortar) la tarea:

1. Si cerró: marcar `[x]` en el archivo de la épica.
2. Actualizar `estado` de la épica en `roadmap.yaml` si corresponde (`pendiente` →
   `en-progreso` en la primera tarea tocada; `en-progreso` → `completo` si era la última y
   el `gate` del hito lo permite) — seguir `skills/shared/roadmap-management/SKILL.md`.
3. Guardar handoff con `mem_session_summary`:
   ```
   Done: [tarea] — [resultado en una línea]
   Next ready: [próxima tarea desbloqueada] | ninguna (backlog vacío)
   Blocked: [tarea] (esperando [qué]) | ninguno
   ```
4. Reportar en el output de la iteración una línea `NEXT-TASK: <resultado>` que el runner
   (`scripts/loop-runner.sh`) usa para decidir si sigue iterando (ver freno por 2 iteraciones
   sin progreso — se mide por diff del roadmap/épica entre iteraciones, no por este string).

## Guardrails (no negociables)

- Una sola tarea por iteración. Nunca encadenar la siguiente tarea en la misma pasada aunque
  quede contexto — el reinicio con contexto limpio es la garantía de calidad del loop.
- L4 nunca commitea sin sign-off del owner, sin excepción, incluso si el build/test pasan.
- Nunca editar `.claude/agents/` generados — la skill y el meta-router
  se editan en `agents/`/`skills/` canónicos de team-ai-harness.
- Si la épica no tiene `archivo:` en el roadmap, o el archivo no tiene tareas en formato
  checkbox con `Depende de:`, no es ejecutable por loop — reportarlo y no improvisar formato.

## Salida esperada (para el runner)

Una línea final parseable:

```
NEXT-TASK: done <proyecto>/<epica>.<tarea-id> | checkpoint <proyecto>/<epica>.<tarea-id> | blocked <proyecto>/<epica>.<tarea-id> | empty
```

`scripts/loop-runner.sh` compara el diff de `roadmap.yaml` + archivo de épica entre
iteraciones consecutivas para decidir el freno de "2 iteraciones sin progreso" — no confía
únicamente en este string.

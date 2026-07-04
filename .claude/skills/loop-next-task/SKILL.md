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
   relativo a `management/`). **Si no tiene `archivo:`, o el archivo existe pero no tiene tareas
   en formato checkbox con `Depende de:`, NO es un backlog vacío ni un corte — es trabajo
   legítimo de la iteración.** Ver §1bis: escribir el archivo de la épica es la tarea de esta
   iteración, no un motivo para devolver a replanificación humana.
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

### 1bis. Autoría de épica sin `archivo:` (cuenta como la tarea de la iteración)

Cuando §1.3 detecta que la épica elegida no tiene `archivo:` (o lo tiene pero sin tareas en
formato checkbox), la iteración escribe ese archivo en vez de devolver a replanificación humana:

1. **Buscar un patrón ya establecido antes de diseñar desde cero.** Revisar
   `management/rules/` (ej. RULE-09/RULE-10 + `platform-architecture.md` §3 para el patrón
   "Retrofit RLS fail-closed") y épicas hermanas ya completadas con el mismo prefijo de nombre
   (ej. otra "Retrofit RLS fail-closed: <servicio>" con `estado: completo`). Si existe, aplicarlo
   mecánicamente — el contexto es el mismo entre servicios, lo que cambia es el volumen
   (archivos/tablas afectadas). Si no existe un patrón previo, es una épica genuinamente nueva y
   la ambigüedad de diseño es mayor (pesa en el gate del punto 4).
2. Invocar `skills/shared/roadmap-management/SKILL.md` para escribir el archivo de la épica en el
   `Detalle de ejecución` que corresponda (`reforzado` si el proyecto lo usa) — mismo estándar
   que `platform/epicas/PLAT-E24-retrofit-rls-ledger-service.md`.
3. **Aplicar P-22 (`PROJECT.md`) sin negociar**: si la épica agrupa varios servicios/entidades o
   su volumen esperado es grande, partir en un grupo de tareas por servicio/unidad — nunca una
   tarea única monolítica.
4. Agregar `archivo:` a la entrada correspondiente en `roadmap.yaml`.
5. Esta autoría **es el trabajo completo de la iteración** — no se ejecuta ninguna tarea del
   plan recién escrito en la misma pasada (mismo guardrail que "una sola tarea por iteración").
   Cerrar con handoff (§5) normal, pero **sin marcar ningún `[x]`**.
6. **Gate de revisión antes de que otra iteración ejecute T1 del plan recién escrito.** Reportar
   `NEXT-TASK: checkpoint <proyecto>/<epica> — plan escrito, pendiente de revisión` (no `done`)
   si se cumple **cualquiera** de estas condiciones:
   - La épica es ceremony `L3` o `L4` (los retrofits RLS lo son siempre — RULE-10 exige
     @architect + @security en el diseño).
   - No hay precedente: ninguna épica hermana con el mismo patrón llegó a `estado: completo`
     todavía (primera vez que el loop aplica ese tipo de épica).
   - El agente tuvo que resolver una ambigüedad de diseño real al escribir las tareas (el
     patrón existente no cubría el caso tal cual).
   Si **ninguna** aplica (ceremony L1/L2, patrón con al menos un precedente ya completo y
   validado por el owner, sin ambigüedad al escribir), la iteración siguiente puede ejecutar T1
   directo sin pedir revisión — no todo plan recién escrito necesita frenar el loop, solo los
   que son L3/L4 o genuinamente nuevos.
   **Motivo**: sin este gate, un loop desatendido podría escribir un plan mal escopeado y
   ejecutarlo varias iteraciones antes de que el owner lo note — mismo riesgo que motivó "L4
   nunca desatendido" en §2, aplicado un paso antes (a la autoría del plan, no solo a su
   ejecución).

### 2. Ejecutar según ceremony level

- **L1/L2**: ejecutar directo con el agente de implementación correspondiente al tipo de
  tarea (dev-senior-backend, dev-senior-frontend, dev-devops, según corresponda).
- **L3**: requiere `@dev-architect` en el diseño si la tarea lo dice explícitamente; si no,
  ejecutar directo pero dejar registrado en el handoff que fue L3.
- **L4**: ver `config/routing-rules.yaml → loop_mode` — regla "L4 nunca desatendido". La
  iteración implementa hasta el gate (build/test verdes) y **NO commitea sin sign-off**. La
  escalación **no es un paso narrado en el handoff — es un gate mecánico** previo a cerrar la
  iteración (§5), con verificación obligatoria en este orden:
  1. Escribir `management/escalations/YYYY-MM-DD_<slug-tarea>.md` con el tool `Write`. No
     alcanza con describir el contenido de la escalación en el texto de la respuesta.
  2. Inmediatamente después, confirmar el archivo en disco con `Read` (o `ls` vía Bash) —
     nunca asumir que un `Write` mencionado en la respuesta se ejecutó realmente.
  3. Guardar el mismo contenido en Engram con `mem_save` (`project` explícito, ver §5.3).
  4. Solo si (1) y (2) quedaron verificados, marcar la escalación como cerrada en el handoff
     y continuar con la próxima tarea sin dependencias pendientes en la siguiente iteración.
  Si el paso 2 no puede confirmar el archivo en disco, la iteración **no reporta `done`**:
  reporta `checkpoint <proyecto>/<epica>.<tarea-id>` (§4.2) anotando en el handoff la causa
  `escalation-write-failed`, y se detiene ahí en vez de asumir que la escalación quedó escrita.
  **Motivo**: en el piloto E24 (2026-07-03, PLAT-E33 T7) ninguna iteración L4 escribió la
  escalación en tiempo real pese a reportarla en el texto de salida — se reconstruyó todo
  retroactivamente (`escalations/2026-07-03_E24-T4-T7-piloto-loop.md`). El paso 2 (verificación
  con `Read`/`ls`) es lo que cierra ese gap: convierte una instrucción en prosa en un chequeo
  verificable, igual que el criterio "Hecho cuando" de §3.

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
3. Guardar handoff en Engram. **No usar `mem_session_summary`** — esa tool no acepta un
   `project` explícito y el loop siempre corre desde `$ROOT` (`~/Projects`, multi-repo), lo que
   la hace fallar con `ambiguous_project` en cada iteración (bug confirmado en el piloto E24,
   2026-07-03: 2 de 3 iteraciones perdieron el handoff por esto). Usar `mem_save` con `project`
   resuelto explícito en su lugar:
   1. Resolver el proyecto dueño del código tocado (no el cwd del loop) — `mem_current_project`
      da candidatos si hace falta, pero normalmente ya se sabe por el `PROJECT.md` leído en
      §1.4 (ej. la épica es `proyecto: platform` pero el código es de `mercado-cercano` →
      `project: mercado-cercano`).
   2. Llamar `mem_save` con:
      - `title`: `<epica>.<tarea> — <resultado en una línea>`
      - `project`: el resuelto en el paso anterior (nunca dejarlo vacío/implícito)
      - `type`: `decision` (o `bugfix`/`discovery` si aplica mejor)
      - `content` con el formato:
        ```
        **What**: [tarea] — [qué se hizo]
        **Why**: [criterio "Hecho cuando" y cómo se verificó]
        **Where**: [archivos/paths tocados]
        **Learned**: Next ready: [próxima tarea desbloqueada] | ninguna (backlog vacío).
          Blocked: [tarea] (esperando [qué]) | ninguno.
        ```
   Si en algún momento `mem_session_summary` deja de fallar en cwd multi-repo (soporta
   `project` explícito), se puede volver a usar — hasta entonces, `mem_save` es la única
   ruta confiable en modo loop.
4. Reportar en el output de la iteración una línea `NEXT-TASK: <resultado>` que el runner
   (`scripts/loop-runner.sh`) usa para decidir si sigue iterando (ver freno por 2 iteraciones
   sin progreso — se mide por diff del roadmap/épica entre iteraciones, no por este string).

## Guardrails (no negociables)

- Una sola tarea por iteración. Nunca encadenar la siguiente tarea en la misma pasada aunque
  quede contexto — el reinicio con contexto limpio es la garantía de calidad del loop.
- L4 nunca commitea sin sign-off del owner, sin excepción, incluso si el build/test pasan.
- La escalación L4 se verifica con `Read`/`ls` antes de cerrar la iteración (§2) — nunca se
  asume que un `Write` reportado en texto se ejecutó de verdad. No negociable.
- Nunca editar `.claude/agents/` generados — la skill y el meta-router
  se editan en `agents/`/`skills/` canónicos de team-ai-harness.
- Si la épica no tiene `archivo:` en el roadmap, o el archivo no tiene tareas en formato
  checkbox con `Depende de:`, escribirlo es la tarea de la iteración (§1bis) — nunca
  improvisar formato, y nunca ejecutar T1 de un plan recién escrito sin pasar el gate de
  revisión de §1bis.6 cuando aplique.

## Plugins y skills externos en modo loop

El entorno del owner tiene plugins de Claude Code instalados a nivel usuario (superpowers,
code-review, context7, engram, playwright, etc.). Sus hooks y skills se inyectan también en
cada iteración headless (`claude -p`) — no se pueden apagar por iteración, se gobiernan por
política. Fuente de verdad: `config/routing-rules.yaml → loop_mode.plugins`. Resumen operativo:

1. **Precedencia**: este protocolo (loop-next-task) manda sobre cualquier mandato de plugin.
   El mandato de superpowers de "invocar skills antes de cualquier respuesta" NO aplica
   dentro del loop cuando la skill es interactiva o consume turnos en subagentes.
2. **Permitidos en loop**: `engram` (REQUERIDO — el handoff del §5 depende de él), `context7`
   (consulta puntual de docs si la tarea toca una librería desconocida — read-only, 1-2
   llamadas máximo), skills pasivas de guía (`security-guidance`) y las skills no interactivas
   de superpowers que refuerzan el "Hecho cuando" (`verification-before-completion`,
   `systematic-debugging`, `test-driven-development`).
3. **Prohibidos en loop**: cualquier skill que dialogue con el owner
   (`superpowers:brainstorming`), que despache subagentes
   (`dispatching-parallel-agents`, `subagent-driven-development` — rompen el presupuesto
   `--max-turns 40`), o que abra browser (`playwright`, `claude-in-chrome` — riesgo de hang
   en headless).
4. **Overlap plugin ↔ skill del harness**: gana SIEMPRE la skill del harness (`code-review`
   plugin → usar `code-reviewer`; `security-guidance` → usar `owasp-top10` como gate). Los
   ceremony levels referencian las skills del harness, no los plugins.
5. **Intento interactivo = bloqueo**: si un plugin o skill pide input del owner en modo loop,
   tratarlo como checkpoint (§4.2) y continuar. Nunca quedarse esperando input en headless.

## Salida esperada (para el runner)

Una línea final parseable:

```
NEXT-TASK: done <proyecto>/<epica>.<tarea-id> | checkpoint <proyecto>/<epica>.<tarea-id> | blocked <proyecto>/<epica>.<tarea-id> | empty
```

`checkpoint` cubre tres causas distintas — anotar cuál en el handoff (§5), no solo el string:
checkpoint intermedio por presupuesto de contexto (§4.2), falla al verificar la escalación L4 en
disco (`escalation-write-failed`, §2), o plan de épica recién escrito pendiente de revisión
(`plan-authored-pending-review`, §1bis.6).

`scripts/loop-runner.sh` compara el diff de `roadmap.yaml` + archivo de épica entre
iteraciones consecutivas para decidir el freno de "2 iteraciones sin progreso" — no confía
únicamente en este string.

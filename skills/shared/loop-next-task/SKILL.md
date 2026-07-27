---
name: loop-next-task
description: Elige y ejecuta la primera tarea desbloqueada del roadmap/épica activa, pensada para correr sin el owner en el medio (driver de loop autónomo). Marca la tarea, actualiza estado y cierra con handoff en Engram.
triggers:
  - "next-task"
  - "próxima tarea"
  - "loop next task"
---

# Loop Next Task

Driver de **una** iteración de loop autónomo. La invoca `scripts/loop-runner.sh`; no se invoca a
mano salvo para depurar.

> **Referencias** (leer sólo cuando el caso lo pide, no de entrada):
> - `reference/casos-borde.md` — épica fijada `--epica`, autoría de épica sin `archivo:`,
>   cortes por presupuesto, política de plugins en modo loop.
> - `reference/historia.md` — los incidentes que originaron cada regla. Consultar al dudar de
>   *por qué* una regla es como es; nunca hace falta para ejecutar.

## Tarea ≠ iteración

Dos unidades distintas que se venían confundiendo, y de ahí que el top-level terminara haciendo
todo en una sola pasada:

| | **Tarea** | **Iteración** |
|---|---|---|
| Qué es | Unidad de **trabajo** | Unidad de **ejecución** |
| Dónde vive | Un `[ ]` en el archivo de la épica | Una vuelta del `while` en `loop-runner.sh` |
| Quién la define | El plan de la épica | El runner |
| Cuándo termina | Cuando su "Hecho cuando" pasa | Cuando se emite el marcador `NEXT-TASK:` |

Una iteración cierra **como mucho** una tarea. Puede cerrar cero (checkpoint, blocked) y **nunca**
más de una. El contexto fresco de cada iteración es la garantía de calidad del loop: encadenar una
segunda tarea porque "quedaba contexto" es exactamente lo que el diseño evita.

## Contrato de fases

Cada iteración son dos invocaciones aisladas. El runner las despacha por `agent-dispatcher.py`,
así que **cada fase corre con el modelo declarado en el frontmatter de su agente**.

### Fase 1 — SELECT

| | |
|---|---|
| **Agente** | `@meta-router` (haiku — clasificar y rutear es determinístico) |
| **Skill** | esta, sólo §1 y §2 |
| **Contexto mínimo** | el índice `roadmap.yaml`; el archivo de la épica elegida; nada más |
| **NO hace** | leer código, editar archivos, marcar `[x]`, abrir `roadmap-descripciones.yaml` salvo que la épica no tenga `archivo:` |
| **Devuelve** | `LOOP-SELECT: proyecto=<p> epica=<KEY-ENN> tarea=<id> ceremony=<L1..L4> agente=<agente-canonico>` |
| **O termina** | `NEXT-TASK: empty` / `NEXT-TASK: blocked <detalle>` — y la iteración no gasta la fase 2 |

### Fase 2 — EXEC

| | |
|---|---|
| **Agente** | el que SELECT designó (sonnet para implementar, opus para L4/arquitectura) |
| **Skill** | esta, §3 a §6 — más las skills propias del agente (hexagonal-go, owasp-top10, …) |
| **Contexto mínimo** | la tarea designada; el archivo de la épica; el `PROJECT.md` del proyecto **dueño del código** |
| **NO hace** | elegir otra tarea, encadenar la siguiente, re-litigar la selección |
| **Devuelve** | `NEXT-TASK: done\|checkpoint\|blocked <proyecto>/<epica>.<tarea>` |

### Fase 3 — REVIEW (sólo si `ceremony: L4`)

| | |
|---|---|
| **Agente** | `@dev-security` (opus, **read-only** por frontmatter: puede señalar, no "arreglar") |
| **Skill** | `dev/owasp-top10` |
| **Cuándo** | ceremony L4 y EXEC no salió `blocked` |
| **Qué revisa** | el **diseño** si EXEC escribió un plan de épica; el **diff sin commitear** si implementó una tarea |
| **Devuelve** | `SECURITY-REVIEW: ok\|objeciones\|bloqueante <resumen>` |

RULE-10 siempre exigió `@dev-security` en L4, pero hasta 2026-07-27 eso dependía de que el agente
ejecutor se acordara de invocarlo. Cableada como fase del runner, la revisión **ocurre**.

La revisión se dispara por **dos** caminos: después de EXEC sobre trabajo recién hecho, y cuando
SELECT reporta `blocked` por un gate L4 que quedó pendiente de una iteración anterior. Sin el
segundo hay deadlock — el gate espera la revisión y la revisión espera que el gate deje pasar.

Ante un veredicto `bloqueante`, el runner despacha **REMEDIATE** (`@dev-architect`): resolver las
objeciones **en el plan**, con la prohibición explícita de corregir la redacción en vez del
problema, y con la salida honesta de discrepar por escrito y con evidencia. Después, `@dev-security`
**re-revisa partiendo de sus objeciones originales** — no del plan corregido, porque preguntar
"¿está bien ahora?" invita a mirar sólo lo que cambió. Un ciclo por corrida: si dos revisiones
seguidas bloquean, es un problema de diseño y lo mira una persona.

Después viene el sign-off del owner, que el runner ofrece por consola sólo con
`--interactive-signoff` **y** TTY. Sin terminal no se pregunta nada: se registra el veredicto y el
loop sigue su curso normal (nunca esperar input en headless — `reference/casos-borde.md` §D.5).
**La remediación no aprueba nada por sí sola**: sólo habilita que se te pregunte.

Toda decisión — aprobada, denegada o pendiente — se escribe en
`management/escalations/YYYY-MM-DD_<epica>-<tarea>-signoff.md` con el veredicto de seguridad
completo. **El sign-off no es un keystroke: es un archivo.** Sin rastro de qué se aprobó y con qué
análisis, el gate L4 se degrada a un trámite.

**Qué se le pasa a la iteración siguiente**: nada en memoria. El estado viaja por disco (el `[x]`
en la épica, el `estado:` en el roadmap, el archivo de sign-off) y por el handoff de Engram (§6).
La iteración siguiente arranca en cero y vuelve a SELECT. Si algo tiene que sobrevivir, se
escribe — no se recuerda.

## Precondición — roadmap único, partido en índice + descripciones

`roadmap.yaml` es **un solo archivo** multi-proyecto (`$DEVY_ROADMAP_PATH`, default
`~/Projects/management/roadmap.yaml`). Cada hito y épica lleva `proyecto:` y un `id:` **prefijado
por project key** (`PLAT-E38`, `MC-E04`) — los ids sin prefijo colisionan entre proyectos.

Desde 2026-07-27 está partido: el **índice** (`roadmap.yaml`) tiene
`id/proyecto/nombre/estado/prioridad/hito/depende_de/archivo/servicios`, y las descripciones
viven en el hermano `roadmap-descripciones.yaml`. **Cargar el índice; abrir el hermano sólo para
UNA épica y sólo si su descripción hace falta** (típicamente: la épica no tiene `archivo:`
todavía). Si tiene `archivo:`, la fuente de verdad es ese archivo.

**Resolución de scope:**
1. **Path**: `$DEVY_ROADMAP_PATH` → `--roadmap <path>` → fallback `~/Projects/management/roadmap.yaml`.
2. **Proyecto**: si vino `--proyecto <nombre>`, usarlo sin negociar. **Nunca inferirlo del cwd** en
   una corrida de loop: el loop corre desde `$DEVY_PATH` y el cwd no identifica el proyecto de la
   épica.
3. **Épica**: si vino `--epica <KEY-ENN>`, el loop queda fijado a esa épica → `reference/casos-borde.md` §A.

## 1. Elegir la épica

1. **No leer `roadmap.yaml` entero.** Correr la consulta, que ya filtra por proyecto y resuelve
   `depende_de:`:

   ```bash
   management/scripts/roadmap-query.py --proyecto <p>       # o --epica <KEY-ENN>
   ```

   Devuelve ~5 KB (las épicas activas del proyecto, marcadas `ELEGIBLE`/`BLOQUEADA`, ya ordenadas
   por el criterio de abajo) en vez de los 47,8 KB del índice, del cual >90% son épicas de otros
   proyectos o ya completas que sólo existen para que `depende_de:` las pueda referenciar. Si con
   `--epica` la salida ya es un `NEXT-TASK:`, emitirlo tal cual y terminar.

   Leer el YAML a mano sólo si la consulta falla o si hace falta un campo que no expone.
2. Tomar la primera `ELEGIBLE` de la lista: es la `en-progreso` de mayor prioridad en el hito
   `fase_actual`, y si no hay, la primera `pendiente` elegible.
3. **Elegible = su `depende_de:` está satisfecho**: cada id listado debe tener `estado: completo`.
   Un id inexistente cuenta como dependencia NO satisfecha (roadmap inconsistente — anotarlo).
   Sin `depende_de:`, la épica está desbloqueada.

   Esto aplica **también a las `en-progreso`**: una épica arrancada fuera de orden con
   dependencias sin cumplir se saltea, no se premia por estar empezada.

   `depende_de:` es la **única** fuente del orden de ejecución. El árbol narrativo en comentarios
   YAML es documentación y **no gobierna nada** — driftea y no es parseable de forma confiable.
4. Leer el archivo de la épica (campo `archivo:`, relativo a `management/`). Si la épica no tiene
   `archivo:`, o lo tiene pero sin tareas en formato checkbox, **escribirlo es la tarea de esta
   iteración** → `reference/casos-borde.md` §B. No es backlog vacío ni motivo de corte.

## 2. Elegir la tarea y designar ejecutor

1. Recorrer las tareas en orden. Elegir la **primera** `[ ]` cuyo `Depende de:` esté en `[x]` (o
   `ninguna`).
2. Si ninguna cumple → `NEXT-TASK: empty`, sin marcar nada. El runner corta la corrida.
3. **Ubicar el código**: leer `management/projects/<proyecto>/PROJECT.md`. Si la épica es
   `proyecto: platform` pero opera sobre código de un proyecto cliente (como los retrofits RLS),
   el `PROJECT.md` del proyecto dueño del servicio que la épica nombra en `servicios:`. **Nunca
   inferir la ubicación del código por cwd.**
4. Designar el agente ejecutor según el tipo de tarea y su ceremony level (`config/routing-rules.yaml`):
   backend → `dev-senior-backend`; infra/observabilidad/Docker/Kong → `dev-devops`; frontend →
   `dev-senior-frontend`; diseño estructural o L4 de arquitectura → `dev-architect`;
   auth/money/PII → sumar `dev-security`.
5. Emitir `LOOP-SELECT:` con proyecto, épica, tarea, ceremony y agente. **Fin de la fase SELECT** —
   no ejecutar nada.

## 3. Ejecutar según ceremony level

- **L1/L2**: ejecutar directo.
- **L3**: `@dev-architect` en el diseño si la tarea lo pide explícitamente; si no, ejecutar directo
  dejando registrado en el handoff que fue L3.
- **L4**: regla **"L4 nunca desatendido"** (`config/routing-rules.yaml → loop_mode`). La iteración
  implementa hasta el gate (build/test verdes) y **NO commitea ni pushea código sin sign-off**.

  El gate es sobre **código** (`git commit`/`git push`). **No** sobre DDL contra la infra local del
  lab: `lab-postgres`/`lab-redis`/`lab-kong` no son producción, así que `CREATE ROLE`, `ALTER`,
  migraciones o habilitar RLS contra ellos se ejecutan en la misma iteración sin escalar —
  siempre que el DDL exista primero como **artefacto versionado** (migración `NNN_*.up/down.sql` u
  otro script checked-in; nunca SQL ad-hoc sin archivo). El archivo queda sin commitear como
  cualquier cambio L4. En producción real (k3s) el mismo DDL sí requiere sign-off.

  La escalación **no es un paso narrado: es un gate mecánico** previo a cerrar, en este orden:
  1. `Write` de `management/escalations/YYYY-MM-DD_<slug-tarea>.md`.
  2. Confirmar el archivo en disco con `Read` (o `ls`). **Nunca asumir que un `Write` mencionado
     en la respuesta se ejecutó.**
  3. `mem_save` del mismo contenido (`project` explícito, §6).
  4. Sólo con (1) y (2) verificados, cerrar.

  Si (2) no confirma el archivo, la iteración **no reporta `done`**: reporta `checkpoint` con causa
  `escalation-write-failed` y se detiene ahí.

## 4. Verificar "Hecho cuando"

Cada tarea declara su criterio de salida como comando o check verificable. **Correrlo.** Si falla:
reintentar dentro de la iteración si el fix es evidente y acotado; si no cierra, dejar la tarea
`[ ]` y anotar en el handoff qué falta. **Nunca marcar `[x]` sin que el criterio pase.**

## 5. Continuidad con las iteraciones anteriores (no negociable)

El contexto fresco es la garantía de calidad del loop y también su punto ciego: **una iteración
puede pisar sin darse cuenta la cautela que registró la anterior.**

Antes de marcar `[x]`, leer las notas de cierre de: las tareas listadas en su `Depende de:`, y las
tareas ya cerradas del mismo objetivo/grupo.

Si alguna registró un **caveat explícito** — una limitación, un "esto no se puede confirmar sin X",
un "queda para la tarea siguiente verificar Y" — hay exactamente dos salidas válidas:

1. **Satisfacer X** y dejar constancia de cómo, o
2. **Explicar con evidencia por qué ya no aplica.**

> **Prohibido cerrar una tarea con la misma evidencia que una tarea anterior declaró
> insuficiente.** Si el caveat no se puede satisfacer dentro del presupuesto de la iteración, la
> tarea NO cierra: se deja `[ ]` con checkpoint.

**Mediciones.** Una medición sólo es evidencia si es *comparable* con aquella contra la que se la
contrasta: mismo uptime, misma carga, misma configuración salvo la variable bajo prueba. Comparar
un proceso recién arrancado contra uno con horas encima no prueba nada sobre la variable — prueba
que reiniciar libera memoria. Ante la duda, **re-medir la línea de base en lugar de citarla**.

Además: verificar **qué mide** la métrica antes de tratarla como dato. Para memoria de un
contenedor, `anon` de `memory.stat` del cgroup o `process_resident_memory_bytes` de Prometheus —
nunca `docker stats` a secas, que suma page cache y lleva a perseguir problemas inexistentes.

(Los dos incidentes que originaron esta sección: `reference/historia.md`.)

## 6. Cerrar la iteración

1. Si cerró: marcar `[x]` en el archivo de la épica.
2. Actualizar `estado:` de la épica en el índice si corresponde (`pendiente` → `en-progreso` en la
   primera tarea tocada; `en-progreso` → `completo` si era la última y el `gate` del hito lo
   permite) — seguir `skills/shared/roadmap-management`. Las notas de cierre extensas van a la
   **bitácora** de la épica (`<epica>-bitacora.md`), no al archivo de la épica ni al roadmap.
3. Handoff en Engram. **No usar `mem_session_summary`**: no acepta `project` explícito y el loop
   corre desde `~/Projects` (multi-repo), con lo que falla con `ambiguous_project` en cada
   iteración. Usar `mem_save`:
   - `project`: el proyecto **dueño del código tocado**, no el cwd (la épica puede ser
     `proyecto: platform` y el código de `mercado-cercano`).
   - `title`: `<epica>.<tarea> — <resultado en una línea>`
   - `type`: `decision` (o `bugfix`/`discovery`).
   - `content`:
     ```
     **What**: [tarea] — [qué se hizo]
     **Why**: [criterio "Hecho cuando" y cómo se verificó]
     **Where**: [archivos/paths tocados]
     **Learned**: Next ready: [próxima tarea desbloqueada] | ninguna (backlog vacío).
       Blocked: [tarea] (esperando [qué]) | ninguno.
     ```
4. **Emitir SIEMPRE, como última línea, el marcador terminal.**

## Marcador terminal (contrato con el runner)

```
NEXT-TASK: done <proyecto>/<epica>.<tarea-id>
NEXT-TASK: checkpoint <proyecto>/<epica>.<tarea-id>
NEXT-TASK: blocked <proyecto>/<epica>.<tarea-id>
NEXT-TASK: empty
```

Es la **señal autoritativa** de que la iteración terminó lo que empezó. Su **ausencia** se
interpreta como terminación anormal (muerte por `--max-turns`, crash del CLI, salida truncada): el
runner la cuenta como no-progreso, avisa si quedaron cambios en disco sin cerrar, y corta tras dos
seguidas. Por eso el marcador sale **incluso cuando la tarea no cerró** — `blocked` con el motivo,
nunca silencio.

> **Un cambio en disco no es evidencia de que la tarea se completó. El marcador sí.**

`checkpoint` cubre tres causas — anotar cuál en el handoff, no sólo el string: presupuesto de
contexto agotado, `escalation-write-failed` (§3), o `plan-authored-pending-review`
(`reference/casos-borde.md` §B).

## Guardrails (no negociables)

- **Una sola tarea por iteración.** Nunca encadenar la siguiente aunque quede contexto.
- **Nunca cerrar una tarea con la misma evidencia que una tarea anterior declaró insuficiente**
  (§5). El contexto fresco no autoriza a re-litigar una limitación ya registrada.
- **Siempre emitir el marcador terminal** como última línea, incluso al no cerrar.
- **L4 nunca commitea sin sign-off del owner**, sin excepción, incluso con build/test en verde.
- **La escalación L4 se verifica con `Read`/`ls`** antes de cerrar — nunca se asume que un `Write`
  reportado en texto se ejecutó.
- **Nunca marcar `[x]` sin correr el criterio "Hecho cuando".**
- **Nunca editar `.claude/agents/` ni `.claude/skills/`** — son generados por `sync-agents.sh`. La
  fuente canónica es `agents/`/`skills/` de `active/team-ai-harness` (ADR-001).
- **Las descripciones no vuelven al índice del roadmap** — van a `roadmap-descripciones.yaml`.

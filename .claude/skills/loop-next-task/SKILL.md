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
roadmap (o de UNA épica fijada por el owner con `--epica`, ver §0), la ejecuta de punta a
punta según su ceremony level, y deja el estado en disco + Engram listo para que la próxima
iteración (contexto fresco) retome sin ambigüedad.

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

**Cómo se resuelve el path, el proyecto y la épica:**
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
3. Épica (opcional): si el comando llegó como `next-task --epica <KEY-ENN>` (id prefijado tal
   como figura en `id:` del roadmap, ej. `PLAT-E25`), el loop queda **fijado a esa épica** —
   ver §0. El prefijo de la épica resuelve el proyecto vía el bloque `prefijos:` del roadmap;
   si además vino `--proyecto` y no coincide con ese prefijo, es un error de invocación:
   reportar `NEXT-TASK: blocked <epica> — proyecto-mismatch` y salir sin tocar nada.
   Sin `--epica`, la selección automática de §1 aplica igual que siempre.

## Algoritmo

### 0. Modo épica fijada (`--epica`, opcional)

Cuando vino `--epica <KEY-ENN>`, la selección de épica de §1.2 **no corre**: la épica ya está
decidida por el owner y tiene precedencia sobre cualquier otra `en-progreso` del roadmap.
Antes de pasar a las tareas (§1.3 en adelante), validar en este orden:

1. **Existe**: hay una entrada con ese `id:` exacto en el roadmap. Si no →
   `NEXT-TASK: blocked <epica> — epica-inexistente` y salir.
2. **Proyecto consistente**: el `proyecto:` de la entrada coincide con el que resuelve el
   prefijo del id (bloque `prefijos:`) y con `--proyecto` si vino (ver resolución, punto 3).
3. **No está completa**: si `estado: completo` → `NEXT-TASK: empty` (nada que hacer; el
   runner corta la corrida).
4. **Dependencias satisfechas**: si la entrada tiene `depende_de:` (ver §1ter), TODAS las
   épicas listadas deben tener `estado: completo`. Si alguna no →
   `NEXT-TASK: blocked <proyecto>/<epica> — depende_de pendiente: <ids>` y salir sin marcar
   nada. Fijar una épica NO saltea sus dependencias — si el owner quiere forzarla igual,
   edita el `depende_de:` en el roadmap, no el loop.

Pasadas las validaciones, continuar en §1.3 con esa épica (incluida la autoría de plan de
§1bis si no tiene `archivo:` — sus gates aplican idénticos). Iteración tras iteración el
runner repite el mismo `--epica`, así que el loop trabaja SOLO tareas de esa épica hasta
`NEXT-TASK: empty` (épica completa) o `blocked`/`checkpoint` (requiere acción del owner).
El guardrail "una sola tarea por iteración" no cambia. Origen: pedido del owner 2026-07-08 —
PLAT-E25 quedó huérfana porque la selección automática nunca la elegía.

### 1. Elegir la tarea

1. Cargar `$DEVY_ROADMAP_PATH` (o el path resuelto arriba) y filtrar por el `proyecto`
   resuelto. Todo lo que sigue opera **solo** sobre `hitos:`/`epicas:` de ese `proyecto`.
2. (Solo sin `--epica` — si vino, la épica ya quedó fijada en §0.) Del subconjunto filtrado,
   tomar la épica con `estado: en-progreso` de mayor prioridad en el hito `fase_actual` de ese
   proyecto. Si no hay ninguna `en-progreso` elegible, tomar la primera `pendiente` elegible.
   **Elegible = su `depende_de:` está completamente satisfecho (§1ter)** — y esto aplica
   TAMBIÉN a las `en-progreso`: una épica arrancada fuera de orden con dependencias sin
   cumplir se saltea (anotándolo en el handoff), no se premia por estar empezada. Verificar
   contra los campos, nunca contra los comentarios narrativos del roadmap: el árbol en
   comentarios probó driftear y ser inaplicable mecánicamente (el loop autónomo escribió el
   plan de PLAT-E26 salteándose PLAT-E25 pese a que el árbol decía E24 → E25 → E26 — commit
   3d802cb, 2026-07-08).
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

### 1ter. Dependencias estructuradas (`depende_de:`)

Cada entrada de épica en `roadmap.yaml` puede llevar un campo `depende_de:` — lista de ids
prefijados de épicas (ej. `[PLAT-E24]`) que deben estar `estado: completo` antes de que esta
épica sea elegible. Es la **única fuente verificable por máquina** del orden de ejecución:

- El árbol narrativo en comentarios YAML del roadmap sigue existiendo como documentación,
  pero **no gobierna la selección** — driftea (quedó diciendo "E33 EN PROgreso" con
  `estado: completo` al lado) y no es parseable de forma confiable.
- Sin `depende_de:`, la épica se considera desbloqueada (equivalente al `Depende de: ninguna`
  de las tareas).
- La verificación es literal: buscar cada id listado en el roadmap y chequear
  `estado: completo`. Un id inexistente cuenta como dependencia NO satisfecha (roadmap
  inconsistente — anotarlo en el handoff).
- Mantenimiento: lo escribe `skills/shared/roadmap-management/SKILL.md` al crear/actualizar
  épicas; al migrar orden desde comentarios, el campo gana ante cualquier discrepancia.

### 2. Ejecutar según ceremony level

- **L1/L2**: ejecutar directo con el agente de implementación correspondiente al tipo de
  tarea (dev-senior-backend, dev-senior-frontend, dev-devops, según corresponda).
- **L3**: requiere `@dev-architect` en el diseño si la tarea lo dice explícitamente; si no,
  ejecutar directo pero dejar registrado en el handoff que fue L3.
- **L4**: ver `config/routing-rules.yaml → loop_mode` — regla "L4 nunca desatendido". La
  iteración implementa hasta el gate (build/test verdes) y **NO commitea/pushea código sin
  sign-off**. Ese gate es sobre CÓDIGO (`git commit`/`git push` en el repo del servicio) — **no**
  sobre DDL contra infra local del lab. `lab-postgres`/`lab-redis`/`lab-kong` (columna "Dev
  local" de `platform-architecture.md` §7) **no son producción**: `CREATE ROLE`, `ALTER`,
  aplicar migraciones o habilitar RLS contra ellos se ejecuta directo en la misma iteración, sin
  escalar, siempre que el DDL exista primero como artefacto versionado (migración
  `NNN_*.up/down.sql` u otro script checked-in — nunca SQL ad-hoc sin archivo; ver
  `config/routing-rules.yaml → loop_mode.local_infra_ddl_policy` y `platform-architecture.md §7`
  para el detalle y el porqué — origen: PLAT-E25 T3, 2026-07-09, escaló esto por error). El
  archivo creado queda sin commitear (como cualquier cambio L4) hasta sign-off del owner; lo que
  NO se frena es su aplicación contra la infra local. Esta regla NO aplica a producción real
  (k3s, cuando exista) — ahí el mismo DDL sigue requiriendo sign-off explícito.

  La escalación **no es un paso narrado en el handoff — es un gate mecánico** previo a cerrar la
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

En modo `--epica` hay además un `blocked` a nivel épica (sin `.<tarea-id>`), con la causa
inline: `blocked <proyecto>/<epica> — depende_de pendiente: <ids>` |
`blocked <epica> — epica-inexistente` | `blocked <epica> — proyecto-mismatch` (§0). El runner
corta la corrida ante cualquier `blocked` cuando la épica está fijada — reiterar no la
desbloquea. `empty` en modo `--epica` significa "épica completa", no backlog global vacío.

`checkpoint` cubre tres causas distintas — anotar cuál en el handoff (§5), no solo el string:
checkpoint intermedio por presupuesto de contexto (§4.2), falla al verificar la escalación L4 en
disco (`escalation-write-failed`, §2), o plan de épica recién escrito pendiente de revisión
(`plan-authored-pending-review`, §1bis.6).

`scripts/loop-runner.sh` compara el diff de `roadmap.yaml` + archivo de épica entre
iteraciones consecutivas para decidir el freno de "2 iteraciones sin progreso" — no confía
únicamente en este string.

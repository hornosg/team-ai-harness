# loop-next-task — casos de borde

Complemento de `SKILL.md`. **No cargar de entrada**: leer sólo la sección que el caso concreto
pide. El flujo normal de una iteración no necesita nada de acá.

---

## §A — Épica fijada (`--epica <KEY-ENN>`)

Cuando el runner pasa `--epica`, la selección de épica de §1 **no corre**: la épica ya está
decidida por el owner y tiene precedencia sobre cualquier otra `en-progreso`. Validar en este
orden antes de pasar a las tareas:

1. **Existe** una entrada con ese `id:` exacto. Si no → `NEXT-TASK: blocked <epica> —
   epica-inexistente`.
2. **Proyecto consistente**: el `proyecto:` de la entrada coincide con el que resuelve el prefijo
   del id (bloque `prefijos:` del roadmap) y con `--proyecto` si vino. Si no →
   `NEXT-TASK: blocked <epica> — proyecto-mismatch`, sin tocar nada.
3. **No está completa**: si `estado: completo` → `NEXT-TASK: empty`. El runner corta la corrida.
4. **Dependencias satisfechas**: si tiene `depende_de:`, TODAS deben estar `completo`. Si alguna
   no → `NEXT-TASK: blocked <proyecto>/<epica> — depende_de pendiente: <ids>`, sin marcar nada.

   **Fijar una épica NO saltea sus dependencias.** Si el owner quiere forzarla igual, edita el
   `depende_de:` en el roadmap, no el loop.

Pasadas las validaciones, seguir en §2 de `SKILL.md` con esa épica (incluida la autoría de plan de
§B si no tiene `archivo:` — sus gates aplican idénticos). El runner repite el mismo `--epica` en
cada iteración, así que el loop trabaja **sólo** tareas de esa épica hasta `empty` (completa) o
`blocked`/`checkpoint` (requiere acción del owner). El guardrail "una sola tarea por iteración" no
cambia.

> Origen: pedido del owner 2026-07-08 — `PLAT-E25` quedó huérfana porque la selección automática
> nunca la elegía.

---

## §B — Autoría de épica sin `archivo:` (cuenta como la tarea de la iteración)

Cuando §1.4 detecta que la épica elegida no tiene `archivo:` (o lo tiene pero sin tareas en formato
checkbox), la iteración **escribe ese archivo** en vez de devolver a replanificación humana. Es la
única situación donde la fase EXEC produce un plan en vez de ejecutar una tarea.

1. **Buscar un patrón ya establecido antes de diseñar desde cero.** Revisar `management/rules/`
   (ej. RULE-09/RULE-10 + `platform-architecture.md` §3 para "Retrofit RLS fail-closed") y épicas
   hermanas ya `completo` con el mismo prefijo de nombre. Si existe, aplicarlo mecánicamente: el
   contexto es el mismo entre servicios, lo que cambia es el volumen. Si no existe precedente, es
   una épica genuinamente nueva y la ambigüedad de diseño es mayor (pesa en el gate del punto 5).
2. Leer la descripción de la épica en `roadmap-descripciones.yaml` — **acá sí hace falta**: sin
   `archivo:`, esa descripción es la única spec disponible.
3. Invocar `skills/shared/roadmap-management` para escribir el archivo en el `Detalle de ejecución`
   que corresponda (`reforzado` si el proyecto lo usa), con el estándar de
   `platform/epicas/PLAT-E24-retrofit-rls-ledger-service.md`.
4. **Aplicar P-22 (`PROJECT.md`) sin negociar**: si la épica agrupa varios servicios/entidades o su
   volumen esperado es grande, partir en un grupo de tareas por servicio/unidad — **nunca una
   tarea única monolítica**.
5. Agregar `archivo:` a la entrada del índice.
6. Esta autoría **es el trabajo completo de la iteración**. No se ejecuta ninguna tarea del plan
   recién escrito en la misma pasada (mismo guardrail que "una sola tarea por iteración"). Cerrar
   con handoff normal, **sin marcar ningún `[x]`**.

### Gate de revisión antes de que otra iteración ejecute T1

Reportar `NEXT-TASK: checkpoint <proyecto>/<epica> — plan-authored-pending-review` (no `done`) si
se cumple **cualquiera** de estas:

- La épica es ceremony **L3 o L4** (los retrofits RLS lo son siempre — RULE-10 exige `@dev-architect`
  + `@dev-security` en el diseño).
- **No hay precedente**: ninguna épica hermana con el mismo patrón llegó a `completo` todavía.
- El agente tuvo que **resolver una ambigüedad de diseño real** al escribir las tareas (el patrón
  existente no cubría el caso tal cual).

Si **ninguna** aplica (L1/L2, patrón con al menos un precedente completo y validado por el owner,
sin ambigüedad), la iteración siguiente puede ejecutar T1 directo. No todo plan recién escrito
necesita frenar el loop — sólo los L3/L4 o genuinamente nuevos.

> **Motivo**: sin este gate, un loop desatendido podría escribir un plan mal escopeado y ejecutarlo
> varias iteraciones antes de que el owner lo note. Mismo riesgo que motivó "L4 nunca desatendido",
> aplicado un paso antes: a la autoría del plan, no sólo a su ejecución.

---

## §C — Cortes por presupuesto

1. **Tarea L4 detectada** → escalar y continuar (§3 de `SKILL.md`). No es un corte de iteración,
   es una ruta de ejecución distinta dentro de la misma tarea.
2. **~50% de la ventana consumida (≈100k tokens) y la tarea no cerró** → checkpoint intermedio:
   escribir en el handoff un resumen `hecho / falta / próximo paso concreto`, **sin marcar `[x]`**.
   La próxima iteración retoma esa misma tarea desde el checkpoint, no desde cero.
3. **3ra iteración consecutiva sin cerrar la misma tarea** → no es un problema de contexto, es que
   la tarea no era atómica. Invocar `skills/dev/atomic-session-planning` para partirla, dejar la
   original marcada como bloqueada **en el handoff** (no en el roadmap — el split lo hace un humano
   o una sesión interactiva), y salir sin marcar `[x]`.

---

## §D — Plugins y skills externos en modo loop

El entorno del owner tiene plugins de Claude Code instalados a nivel usuario (superpowers,
code-review, context7, engram, playwright…). Sus hooks y skills se inyectan también en cada
iteración headless — no se pueden apagar por iteración, se gobiernan por política. Fuente de
verdad: `config/routing-rules.yaml → loop_mode.plugins`.

1. **Precedencia**: este protocolo manda sobre cualquier mandato de plugin. El mandato de
   superpowers de "invocar skills antes de cualquier respuesta" **no aplica** dentro del loop
   cuando la skill es interactiva o consume turnos en subagentes.
2. **Permitidos**: `engram` (REQUERIDO — el handoff depende de él), `context7` (consulta puntual de
   docs, read-only, 1-2 llamadas máximo), skills pasivas de guía (`security-guidance`) y las no
   interactivas de superpowers que refuerzan el "Hecho cuando" (`verification-before-completion`,
   `systematic-debugging`, `test-driven-development`).
3. **Prohibidos**: cualquier skill que dialogue con el owner (`superpowers:brainstorming`), que
   despache subagentes (`dispatching-parallel-agents`, `subagent-driven-development` — rompen el
   presupuesto de turnos), o que abra browser (`playwright`, `claude-in-chrome` — riesgo de hang en
   headless).
4. **Overlap plugin ↔ skill del harness**: gana **siempre** la del harness (`code-review` plugin →
   usar `code-reviewer`; `security-guidance` → usar `owasp-top10` como gate). Los ceremony levels
   referencian las skills del harness, no los plugins.
5. **Intento interactivo = bloqueo**: si un plugin o skill pide input del owner en modo loop,
   tratarlo como checkpoint (§C.2) y continuar. **Nunca quedarse esperando input en headless.**

# loop-next-task — de dónde salió cada regla

**No hace falta para ejecutar una iteración.** Está acá para cuando una regla parece arbitraria o
cara y alguien evalúa relajarla: cada una salió de un modo de fallo observado, no de una intuición.

---

## El marcador terminal `NEXT-TASK:` (2026-07-26, commit `ea0489f`)

El runner sólo comparaba el hash de `roadmap.yaml` + archivos de épica entre iteraciones. Si el
agente moría por agotar `--max-turns` **habiendo alcanzado a escribir algo**, el hash cambiaba y se
registraba "progreso detectado" — reseteando la racha de no-progreso y dejando que el loop siguiera
sobre una tarea a medio hacer.

Ahora el marcador es la señal autoritativa y su ausencia es terminación anormal.

> **Un cambio en disco no es evidencia de que la tarea se completó.**

---

## Invocar la skill, no `@meta-router` (2026-07-26, commit `a4fb716`)

El runner invocaba `@meta-router next-task`. Ese agente declara `tools: [Skill]`: no puede leer
archivos, correr comandos ni editar la épica. Era **estructuralmente incapaz** de ejecutar la tarea.

Síntoma: dos iteraciones de cierre de `PLAT-E38` reportaron textualmente *«el agente meta-router no
tiene acceso a Bash/Read, así que terminé el ciclo yo mismo»*. El trabajo salió **bien**, pero se
hizo **fuera de la skill** — y por eso ninguna emitió el marcador. El runner las marcó como
anormales, **correctamente**: no tenía forma de distinguirlas de una muerte por turnos. El guard
nuevo no dio falso positivo; detectó que el trabajo se hacía fuera del protocolo.

> **Lección general**: al construir un prompt para un runner autónomo, verificar que el
> destinatario tenga las tools para hacer lo que se le pide. El síntoma es sutil porque el modelo
> top-level "rescata" la tarea y la hace igual: el trabajo sale, pero sin guardrails ni marcadores.

Nota: con el dispatcher (2026-07-27) `@meta-router` vuelve a aparecer en el loop, pero en un rol
distinto y compatible con sus tools — la fase SELECT, que **sólo elige** y no ejecuta.

---

## §5 Continuidad — el caso PLAT-E38 (2026-07-26, commit `0e42aaf`)

`T-STK-M1` midió con un spam de `/health` y escribió: *«La hipótesis GOMEMLIMIT no se puede
confirmar ni descartar con esta medición — hace falta carga real contra `/api/v1/*` sostenida en el
tiempo, no un spam de `/health`»*.

`T-STK-M3`, con contexto fresco, corrió **el mismo spam de `/health`**, obtuvo un número más bajo y
escribió *«Confirma la hipótesis principal»*. La épica se marcó completa con el criterio sin
cumplir; medido cuatro horas después, el servicio estaba al triple del valor reportado.

**Nada en el runner podía detectarlo**: los archivos cambiaron y el marcador se emitió. Por eso la
regla vive en la skill y no en el driver.

---

## §5 Mediciones — el page cache de stock-service (2026-07-26)

La épica `PLAT-E38` nació de un `docker stats` que mostraba `stock-service` en 204 MB contra 38-61
MB de sus pares. Se persiguió esa hipótesis durante **nueve tareas**. El desglose de `memory.stat`
de los cgroups, mismo instante, sin reiniciar nada:

| servicio | `anon` (proceso real) | `file` (page cache) |
|---|---|---|
| mc-stock-service | **17,0 MiB** | 245,0 MiB |
| mc-pim-service | **11,5 MiB** | 47,7 MiB |
| mc-sales-service | **16,1 MiB** | 25,2 MiB |

La memoria real de los tres es prácticamente idéntica: **todo el diferencial era page cache**, que
es reclamable y no es consumo del proceso. La señal que lo destrabó estaba desde antes sin que
nadie la mirara: `process_resident_memory_bytes` reportaba 20,9 MiB mientras `docker stats`
reportaba 92,65 MiB **para el mismo proceso en el mismo instante**.

Impacto evitado: dimensionar pods de `PLAT-H2` (k3s) con `docker stats` habría sobreestimado el
requerimiento real en **un orden de magnitud**.

> **Patrón común de los tres errores encadenados de ese hilo** (comparar uptimes distintos;
> confirmar una hipótesis con evidencia ya declarada insuficiente; tomar `docker stats` como
> memoria del proceso): **tratar un número como dato sin verificar qué está midiendo.**

---

## La escalación L4 como gate mecánico (2026-07-03, piloto E24 / PLAT-E33 T7)

Ninguna iteración L4 escribió la escalación en tiempo real pese a **reportarla en el texto de
salida**. Se reconstruyó todo retroactivamente en
`escalations/2026-07-03_E24-T4-T7-piloto-loop.md`.

El paso de verificación con `Read`/`ls` es lo que cierra ese gap: convierte una instrucción en
prosa en un chequeo verificable, igual que el criterio "Hecho cuando".

---

## `mem_save` en vez de `mem_session_summary` (2026-07-03, piloto E24)

`mem_session_summary` no acepta `project` explícito y el loop corre desde `~/Projects`
(multi-repo), con lo que falla con `ambiguous_project`. **2 de 3 iteraciones del piloto perdieron
el handoff por esto.** Si algún día soporta `project` explícito, se puede volver a usar.

---

## `depende_de:` estructurado (2026-07-08, commit `3d802cb`)

El orden de ejecución vivía en un árbol narrativo en comentarios YAML. Drifteó — llegó a decir
"E33 EN PROGRESO" con `estado: completo` al lado — y no es parseable de forma confiable. El loop
autónomo escribió el plan de `PLAT-E26` salteándose `PLAT-E25` pese a que el árbol decía
E24 → E25 → E26.

Desde entonces la selección verifica **campos**, nunca comentarios.

---

## El split del roadmap y del pack de contexto (2026-07-27)

Medición de lo que una iteración cargaba **antes de empezar a trabajar**: ~202 KB.

| pieza | antes | después |
|---|---|---|
| `roadmap.yaml` | 122,1 KB (53% descripciones; 32,7 KB de épicas ya completas) | 47,8 KB índice + hermano bajo demanda |
| `SKILL.md` de loop-next-task | 24,7 KB | core + `reference/` bajo demanda |
| archivos de épica | hasta 39,8 KB (`PLAT-E38`) por notas de cierre acumuladas | épica + bitácora hermana |
| pack del dispatcher (si se hubiera usado `full`) | 123,9 KB para `meta-router` | 12,0 KB en `native` |

El pack `full` inyectaba inline los `CLAUDE.md`, `PROJECT.md`, `routing-rules` y el **texto
completo de cada skill del agente** — todo lo cual Claude Code ya carga solo o expone por el tool
`Skill`. Correcto para Codex, que no conoce el harness; puro duplicado dentro de la misma ventana
para un runtime Claude Code.

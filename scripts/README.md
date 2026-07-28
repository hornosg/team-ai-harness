# `loop-runner.sh` — driver de loop autónomo

Itera con **contexto fresco por iteración** hasta que se cumple una condición de corte. Cada
pasada elige y ejecuta la primera tarea desbloqueada del roadmap (o de una épica fijada), deja el
estado en disco + Engram, y la siguiente iteración retoma sin ambigüedad. La skill que decide qué
hacer es `skills/shared/loop-next-task/SKILL.md`.

Desde 2026-07-27 cada iteración son **dos invocaciones** (`SELECT` → `EXEC`) y **todas** pasan por
`agent-dispatcher.py`, que resuelve el modelo desde el frontmatter de cada agente. Ver
[Contrato de fases](#contrato-de-fases).

> **⚠️ El script vive en DOS lugares sin sync automático:** `management/scripts/loop-runner.sh`
> (repo `devy-management`) y `active/team-ai-harness/scripts/loop-runner.sh` (canónico, repo
> `team-ai-harness`). Al editarlo, **actualizar y commitear en ambos** — deben quedar byte-idénticos.
> `./scripts/harness-drift.sh` detecta cuándo divergieron.

## Uso

```
./scripts/loop-runner.sh [--proyecto <nombre>] [--epica <KEY-ENN>]
                         [--roadmap <path>]
                         [--provider anthropic|ollama|codex] [--model <alias>] [--ollama-model <id>]
                         [--phases split|single] [--select-agent <a>] [--exec-agent <a>]
                         [--max-iterations N] [--max-turns N] [--dry-run]
```

## Flags

| Flag | Default | Qué hace |
|------|---------|----------|
| `--proyecto <nombre>` | vacío (infiere del cwd) | Filtra el roadmap a ese proyecto (`platform`, `mercado-cercano`, …). |
| `--epica <KEY-ENN>` | vacío (selección automática) | **Fija** una épica (ej. `PLAT-E28`). Tiene precedencia sobre cualquier `en-progreso`. Valida §0: existencia, proyecto consistente, no-completa, `depende_de` satisfecho. NO saltea dependencias. |
| `--roadmap <path>` | `$DEVY_ROADMAP_PATH` (o `~/Projects/management/roadmap.yaml`) | Roadmap único multi-proyecto a leer. |
| `--provider anthropic\|ollama\|codex` | `anthropic` | Backing del loop. Los tres pasan por `agent-dispatcher.py`. `anthropic` = `claude -p` (context-mode `native`); `ollama` = `ollama launch claude`, backing global kimi, sin cupo Anthropic (`native`); `codex` = `codex exec`, requiere `--model` (`full`). |
| `--model <alias>` | vacío (**frontmatter de cada agente**) | Override de emergencia: pisa el modelo declarado por el agente **en todas las fases**. Sin el flag, cada agente corre en el modelo que declara (haiku para orquestar, sonnet/opus para ejecutar) — ése es el modo normal. Para Codex es obligatorio (ej. `gpt-5.6-luna`). |
| `--ollama-model <id>` | `kimi-k2.7-code:cloud` | Modelo cuando `--provider ollama`. El backing es global, el frontmatter no aplica. |
| `--phases split\|single` | `split` | `split` = dos invocaciones por iteración (SELECT → EXEC), cada una con su agente y su modelo. `single` = una sola invocación hace todo (comportamiento previo al 2026-07-27); escape hatch si el handoff entre fases falla. |
| `--select-agent <a>` | `meta-router` | Agente de la fase SELECT. |
| `--security-agent <a>` | `dev-security` | Agente de la fase REVIEW (sólo L4). |
| `--no-security-review` | — | Desactiva la fase REVIEW. **No usar en L4 real**: RULE-10 la exige. |
| `--interactive-signoff` | desactivado | Tras REVIEW, pregunta `¿Aprobás? [s/N]` por consola. **Sólo con TTY**: sin terminal se registra el veredicto y sigue, nunca cuelga. |
| `--signoff-timeout N` | `1800` | Segundos de espera. Vencido se registra **SIN RESPUESTA**, que no es lo mismo que un rechazo. |
| `--resume-gate` | desactivado | Reusa el veredicto de un gate que quedó SIN RESPUESTA, sin volver a pagar la revisión de opus. Sólo válido si el diff no cambió. |
| `--remediate-agent <a>` | `dev-architect` | Quien corrige el plan tras un veredicto `bloqueante`. Necesita `Write` (`dev-security` es read-only). |
| `--remediate-cycles N` | `1` | Ciclos de remediación + re-revisión en el gate de **plan**. `0` desactiva: `bloqueante` corta de una. |
| `--review-turns N` | `25` | Presupuesto del gate de **plan** (revisar un diseño entero). |
| `--review-commit-turns N` | `15` | Presupuesto del gate de **commit** (revisar un diff acotado). |
| `--remediate-on-commit` | desactivado | Permite remediación automática también sobre diffs. Por defecto no: un `bloqueante` sobre código vuelve por el loop normal como una tarea más. |
| `--exec-agent <a>` | `dev-senior-backend` | Fallback de EXEC cuando SELECT no designa un agente válido. |
| `--max-iterations N` | `0` (sin límite duro) | Tope de iteraciones. El freno real es la racha de no-progreso. |
| `--max-turns N` | `40` | Presupuesto de turnos de la fase EXEC. SELECT usa 15 fijo (sólo lee y decide). |
| `--dry-run` | — | No ejecuta la invocación real; resuelve agente→modelo→tamaño de contexto de cada fase y lo imprime. |

## Contrato de fases

Una **tarea** es la unidad de trabajo (un `[ ]` en la épica). Una **iteración** es la unidad de
ejecución (una vuelta del loop). Una iteración cierra **como mucho** una tarea — puede cerrar cero
(checkpoint, blocked) y nunca más de una.

Cada iteración son dos invocaciones aisladas, y cada una corre con el modelo que declara **su**
agente:

| | Fase 1 — SELECT | Fase 2 — EXEC | Fase 3 — REVIEW (sólo L4) |
|---|---|---|---|
| Agente | `@meta-router` (haiku) | el que SELECT designó (sonnet/opus) | `@dev-security` (opus, read-only) |
| Presupuesto | 15 turnos | `--max-turns` (40) | 25 turnos |
| Contexto mínimo | consulta del roadmap + tareas de la épica | la tarea + épica + `PROJECT.md` del dueño del código | lo que EXEC dejó (plan o diff) |
| Hace | elige la tarea y designa ejecutor | ejecuta esa única tarea y cierra | dictamina sobre auth/identidad/money/PII/RLS |
| No hace | leer código, editar, marcar `[x]` | elegir otra tarea, encadenar la siguiente | editar, commitear, "arreglar" |
| Devuelve | `LOOP-SELECT: proyecto= epica= tarea= ceremony= agente=` | `NEXT-TASK: done\|checkpoint\|blocked` | `SECURITY-REVIEW: ok\|objeciones\|bloqueante` |

### Gate L4 y sign-off

RULE-10 siempre exigió `@dev-security` en L4, pero dependía de que el agente ejecutor se acordara
de invocarlo. Desde 2026-07-27 es una fase del runner: si el ceremony es L4, la revisión **ocurre**.

Se dispara por **dos** caminos, y el segundo es el que importa en la práctica:

1. **Después de EXEC**, sobre trabajo recién hecho en esa iteración.
2. **Cuando SELECT reporta `blocked` por un gate L4 que quedó pendiente** de una iteración
   anterior — el plan ya está escrito y espera revisión. Sin este camino había un deadlock: el
   gate esperaba a la revisión, EXEC nunca corría porque SELECT devolvía `blocked`, y la revisión
   que destrabaría el gate no se disparaba nunca. Observado en PLAT-E39.

Un `blocked` por `depende_de:` sin cumplir **no** dispara la revisión: ahí no hay nada que revisar,
falta que otra épica se complete.

Tras un sign-off aprobado, el runner despacha una anotación corta para dejar el gate marcado como
aprobado en el archivo de la épica (`@dev-security` es read-only y no puede hacerlo). Si la épica
vuelve a reportar el mismo gate después de aprobarlo, el runner **corta**: reintentar sería un
bucle infinito sobre un archivo que nadie está actualizando.

Con `--interactive-signoff` **y** TTY, el runner pregunta por consola:

```
  ┌─ GATE L4 ─────────────────────────────────────────────
  │ PLAT-E39.DESIGN
  │ Veredicto de @dev-security: SECURITY-REVIEW: objeciones — …
  └───────────────────────────────────────────────────────
  ¿Aprobás? [s/N] (timeout 1800s → NO):
```

**Timeout ≠ rechazo.** Un veredicto L4 son varios miles de palabras que hay que leer antes de
decidir; en PLAT-E39.T1f los 600s originales vencieron mientras el owner lo leía, y el archivo
quedó diciendo "NO APROBADO" sobre trabajo que nadie llegó a evaluar. Un registro que miente sobre
por qué algo no se aprobó es peor que no tenerlo. El default subió a 1800s, el motivo real se
registra, y `--resume-gate` permite retomar sin re-comprar la revisión.

Reglas del prompt, todas verificadas:

| Situación | Resultado |
|---|---|
| `s` / `si` / `y` / `yes` | APROBADO — se registra y el loop sigue |
| `n`, enter vacío, cualquier otra cosa | **NO APROBADO** (rechazo explícito) — se registra y corta |
| Timeout o EOF | **SIN RESPUESTA** — corta igual (en L4, ante la duda no se avanza) pero el registro dice que nadie decidió, no que se rechazó |
| **Sin TTY** (cron, `nohup`, background) | **No pregunta**: registra `PENDIENTE` y sigue el flujo normal |
| Veredicto `bloqueante` | Dispara REMEDIATE (ver abajo); si tras el ciclo sigue bloqueante, corta sin ofrecer sign-off |

Lo de "sin TTY" no es un detalle: un `read` sin terminal cuelga el proceso **para siempre**, que es
el peor modo de fallo posible para un runner autónomo. Por eso el prompt es opt-in y condicionado.

Toda decisión se escribe en `management/escalations/AAAA-MM-DD_<épica>-<tarea>-signoff.md` con el
veredicto de seguridad completo, incluido el rastro de las remediaciones. **El sign-off no es un
keystroke: es un archivo.** Sin rastro de qué se aprobó y con qué análisis, el gate L4 se degrada
a un trámite.

### Los dos gates no cuestan lo mismo

| | Gate de **plan** | Gate de **commit** |
|---|---|---|
| Cuándo | una vez por épica, cuando el plan espera revisión | por cada tarea L4 implementada |
| Qué revisa | el diseño y sus decisiones abiertas | el diff sin commitear |
| Presupuesto | 25 turnos | 15 turnos |
| Remediación | 1 ciclo | ninguno (opt-in con `--remediate-on-commit`) |

La distinción es de **costo**, y no es teórica: una épica L4 con 25 tareas dispara 25 gates de
commit. Cobrarlos al precio de un gate de plan agota la ventana de uso antes de terminar la épica
— medido en PLAT-E39 el 2026-07-27: 32% de una ventana de 5h consumido en la primera tarea.

Sobre un diff, además, la remediación automática tiene menos sentido: un `bloqueante` ahí significa
reescribir código, y eso vuelve por el loop normal como una tarea más, con su propio ciclo completo.

### Cuándo NO corre el gate de commit

Sólo tiene sentido revisar lo que EXEC dejó **si EXEC terminó**. Se omite cuando murió por
`--max-turns`, cuando no emitió marcador, o cuando reportó `blocked` — en los tres casos no hay
diff que auditar. Sí corre ante un `checkpoint`: ahí hay trabajo parcial en disco.

Observado en PLAT-E39.T1 (2026-07-27): EXEC agotó los 40 turnos sin crear nada y la revisión corrió
igual, gastando una invocación opus para ir a disco, comprobar que `catalog-service` no existía y
reportar el false-dispatch. Tenía razón — y el prompt le había afirmado como premisa que la tarea
"se acababa de ejecutar".

> **Nunca afirmarle a un agente que algo existe sin haberlo verificado.** La revisión buena cuesta
> una invocación cara; la mala fabrica un veredicto sobre nada.

### El `tools:` del frontmatter NO restringe (verificado)

Un agente despachado por `agent-dispatcher.py` corre en un `claude -p` top-level, que tiene
**todas** las tools. El `tools: [...]` de su frontmatter viaja en el pack como texto, no como
restricción: describe el rol, no lo limita.

Verificado en PLAT-E39.T1f (2026-07-28): SELECT designó `@dev-architect` — que declara
`tools: [Read, Grep, Glob, WebFetch, WebSearch, Skill]`, sin `Write` — para una tarea que mueve
código entre repos. **Escribió el código igual**, corrió los tests y cerró con checkpoint correcto.

Esto es distinto del bug de `a4fb716`: ahí `@meta-router` se invocaba como **subagente** vía la
tool `Agent`, donde las tools sí se aplican. Por el dispatcher, no.

Consecuencia práctica: SELECT puede designar por dominio sin preocuparse por la capacidad. Pero el
frontmatter deja de ser una garantía — si querés que un agente **realmente** no pueda escribir, el
dispatcher no es el camino.

### Si la revisión no cierra

Una revisión que muere sin emitir `SECURITY-REVIEW:` **no ofrece sign-off**. Pedirte que apruebes
algo que nadie llegó a mirar es peor que no preguntar: el archivo quedaría diciendo "APROBADO" con
un veredicto vacío al lado. Se registra como `SIN REVISAR` y el loop corta, sugiriendo subir el
presupuesto de turnos.

### Fase REMEDIATE — qué pasa tras un `bloqueante`

```
REVIEW (@dev-security)  → bloqueante
REMEDIATE (@dev-architect) → resuelve las objeciones EN EL PLAN
RE-REVIEW (@dev-security)  → ¿el problema de fondo quedó resuelto?
   ├─ ok | objeciones → sign-off del owner
   └─ bloqueante otra vez → corta, sin ofrecer sign-off
```

El riesgo evidente de que el mismo loop corrija lo que otro agente objetó es que el corrector
**satisfaga al revisor en la letra**: reescribir el enunciado para que la objeción deje de aplicar,
sin resolver nada. Tres cosas lo acotan:

1. El prompt de REMEDIATE lo prohíbe explícitamente, y habilita la salida honesta: si el agente
   cree que una objeción es incorrecta, debe **dejar escrito por qué con evidencia**, no ignorarla.
   Discrepar con argumento es válido.
2. La re-revisión **parte de las objeciones originales**, no del plan corregido. Preguntar "¿está
   bien ahora?" invita a mirar sólo lo que cambió; lo que importa es si el problema sigue ahí. El
   prompt le pide explícitamente marcar como bloqueante toda objeción "resuelta" por redacción.
3. **El sign-off del owner sigue siendo obligatorio.** La remediación no puede aprobar nada por sí
   sola — sólo habilita que se te pregunte.

El tope por defecto es **un** ciclo, a propósito: si dos revisiones seguidas siguen bloqueando, el
problema es de diseño y lo tiene que mirar una persona.

Comportamiento de borde:

- Si SELECT emite un marcador terminal (`empty`/`blocked`), la iteración **no gasta EXEC**.
- Si SELECT no emite `LOOP-SELECT` **ni** marcador, EXEC **no se despacha** — ejecutar sin saber
  qué tarea se eligió es el modo de fallo que el loop viene eliminando. Cuenta como terminación
  anormal.
- Si el agente designado no existe, cae a `--exec-agent` avisando, en vez de quemar la iteración.

Entre iteraciones **no viaja nada en memoria**: el estado va por disco (el `[x]`, el `estado:`) y
por el handoff de Engram. Lo que tiene que sobrevivir, se escribe.

En consola se ve así:

```
[loop-runner] iteración 1 — fase SELECT con @meta-router (provider=anthropic, --max-turns 15)
…
DISPATCH-STATUS: success model=claude-haiku-4-5-20251001 agent=meta-router
[loop-runner] iteración 1 — fase EXEC de PLAT-E21.T4 (L2) con @dev-devops (--max-turns 40)
…
DISPATCH-STATUS: success model=claude-opus-4-8 agent=dev-devops
[loop-runner] progreso confirmado (marcador NEXT-TASK + cambio de estado)
```

El log por iteración (`$ITER_LOG_DIR`, default `management/.loop-logs/<timestamp>/`) guarda **las
dos fases** separadas por `===== FASE SELECT =====` / `===== FASE EXEC =====`: cuando una
iteración sale mal, la mitad de las veces la causa está en la selección, no en la ejecución.

## Formas de ejecución (ejemplos)

```bash
# Épica fijada, provider y modelo por default (lo más común)
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E28

# Selección automática: la primera épica desbloqueada del proyecto
./management/scripts/loop-runner.sh --proyecto platform

# Override de emergencia del modelo (pisa el frontmatter en AMBAS fases).
# Sólo para escapar de un pool sin créditos — normalmente no se pasa.
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E28 --model sonnet
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E29 --model fable

# Volver a una sola invocación por iteración (comportamiento previo al 2026-07-27)
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E28 --phases single

# Forzar quién ejecuta cuando la épica es de un dominio puntual
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E35 --exec-agent dev-devops

# Codex como execution origin del loop, entrando por @meta-router
./management/scripts/loop-runner.sh \
  --provider codex \
  --model gpt-5.6-luna \
  --proyecto platform \
  --epica PLAT-E28

# Si Codex no fue agregado al PATH del shell (por ejemplo, instalación del plugin de VS Code),
# el runner intenta localizarlo en ~/.vscode-server/extensions, ~/.vscode/extensions,
# ~/.local/bin y ~/.cargo/bin. También se puede fijar explícitamente:
export CODEX_BIN="$HOME/.vscode-server/extensions/openai.chatgpt-<version>/bin/<platform>/codex"

# Caveman por sesión headless de Codex: auto lo activa si existe la skill en CODEX_HOME
# o en AGENTS_HOME (por defecto ~/.agents, destino de `npx skills add`).
# Para forzarlo después de instalarla: full | lite | ultra | wenyan. Para apagarlo: off.
# Instalación única (no la ejecuta el runner): npx skills add JuliusBrussee/caveman -a codex
export CODEX_CAVEMAN_MODE=full

# Fallback sin cupo Anthropic: backing global kimi vía Ollama
./management/scripts/loop-runner.sh --proyecto platform --ollama-model kimi-k2.7-code:cloud --provider ollama

# Roadmap alternativo + tope de iteraciones
./management/scripts/loop-runner.sh --roadmap /ruta/otro-roadmap.yaml --max-iterations 5

# Validar el driver sin ejecutar (imprime la invocación que haría)
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E28 --model fable --dry-run
```

## `agent-dispatcher.py` — resolución agente → modelo → contexto

**Toda** invocación del loop pasa por acá desde 2026-07-27. Antes sólo lo hacía `--provider
codex`; anthropic y ollama llamaban al CLI directo, salteándose la resolución: no se cargaba el
frontmatter del agente, no se aplicaba el modelo por agente, y la iteración entera corría al
precio del `--model` del loop. Tener una rama que evita el dispatcher es tener dos mecanismos que
divergen.

También se usa suelto, para ejecutar un agente puntual fuera del loop (ejemplos abajo).

### `--context-mode`

Qué contexto viaja en el pack. El default sale del provider y casi nunca hace falta tocarlo:

| Modo | Providers | Qué inyecta | Por qué |
|---|---|---|---|
| `native` | `claude`, `ollama` | Sólo las instrucciones del agente + **punteros por path** al resto | El runtime **es** Claude Code (`ollama launch claude` también): ya carga los `CLAUDE.md` del lab y expone las skills por el tool `Skill`. Inyectarlas otra vez duplica el contenido en la misma ventana. |
| `full` | `codex` | `CLAUDE.md`, `PROJECT.md`, `routing-rules`, `ceremony-levels` y el **texto completo** de cada skill del agente | Codex no conoce el harness ni tiene el tool `Skill`: si no viaja en el pack, no existe. |

Medido sobre los 32 agentes: **2,52 MB** de pack `full` contra **182 KB** en `native` (−92,8%).
Para `meta-router`, 123,9 KB → 12,0 KB.

### Uso suelto

```bash
# Validar el dispatch sin ejecutar ningún provider
python3 management/scripts/agent-dispatcher.py \
  --agent dev-junior-backend \
  --provider codex \
  --model gpt-5.6-luna \
  --project team-ai-harness \
  --execution-origin claude \
  --task 'Canario read-only; no modificar archivos' \
  --cwd active/team-ai-harness \
  --dry-run

# Ejecución Codex aislada y read-only (canario)
python3 management/scripts/agent-dispatcher.py \
  --agent dev-junior-backend \
  --provider codex \
  --model gpt-5.6-luna \
  --project team-ai-harness \
  --execution-origin claude \
  --task-file /ruta/a/tarea.md \
  --cwd active/team-ai-harness

# Equivalente Codex por agente para una tarea ya seleccionada de PLAT-E28
# (el loop sigue seleccionando la épica; el dispatcher ejecuta una tarea puntual)
python3 management/scripts/agent-dispatcher.py \
  --agent dev-junior-backend \
  --provider codex \
  --model gpt-5.6-luna \
  --project platform \
  --execution-origin claude \
  --task-file /tmp/PLAT-E28-T1.md \
  --cwd active/mercado-cercano
```

`execution-origin` describe desde qué frontend se inició la sesión; `provider` describe qué runtime
ejecuta al agente. `--unattended` habilita permisos no interactivos: el loop lo pasa siempre, y a
mano conviene reservarlo para un canario explícitamente aprobado.

El dispatcher devuelve **una línea JSON** con `status`, `model`, `context_mode`, `context_bytes` y
`output_tail`. El runner la desenvuelve (`unwrap_dispatch`) para que los detectores de cuota y de
marcador trabajen sobre texto plano.

> **Trampa de quoting, documentada porque ya mordió dos veces:** un `python3 -c '…'` inline dentro
> de un `log "…$(…)"` queda con el quoting triplemente anidado (bash → `$()` → python) y los `\"`
> llegan literales a python (`SyntaxError`). Y **`--dry-run` no lo atrapa**, porque no ejecuta esa
> ruta. Por eso `unwrap_dispatch` y `summarize_dispatch` son funciones propias, probables aisladas:
>
> ```bash
> source <(sed -n '/^unwrap_dispatch()/,/^}/p' scripts/loop-runner.sh)
> printf '%s' '{"status":"success","agent":"a","model":"m","output_tail":"NEXT-TASK: empty"}' | unwrap_dispatch
> ```

## Condiciones de corte

El loop termina (limpio) cuando:

- **`NEXT-TASK: empty`** — la épica/roadmap no tiene tareas ejecutables (backlog vacío). En modo
  `--epica` suele significar "épica completa salvo acción del owner" (ej. sign-off L4 pendiente).
- **`NEXT-TASK: blocked`** (solo con `--epica`) — la épica está bloqueada (dependencia sin cumplir);
  reiterar no la desbloquea → corta.
- **`NEXT-TASK: checkpoint` que espera a una persona** (solo con `--epica`) — causa
  `plan-authored-pending-review` (plan L4 recién escrito, gate §B) o `escalation-write-failed`.
  Lo destraba un sign-off, no otra iteración → corta. El checkpoint por **contexto agotado** NO
  corta: ahí la próxima iteración retoma la misma tarea desde donde quedó.
- **Racha de no-progreso** — 2 iteraciones consecutivas sin cambio del hash de estado
  (`NO_PROGRESS_THRESHOLD`) → corta.
- **Racha de terminaciones anormales** — 2 seguidas (`ABNORMAL_THRESHOLD`) → corta. Es más bajo
  que el umbral de no-progreso a propósito: una anormal cuesta el presupuesto completo de turnos
  sin entregar nada.
- **Muerte por `--max-turns`** — corta a la **primera** (`MAX_TURNS_THRESHOLD=1`), sin reintentar.
  No es el mismo fallo que un crash: agotar el presupuesto es **determinístico**, así que la misma
  tarea con el mismo presupuesto y contexto fresco vuelve a agotarlo. Reintentar sólo compra otro
  presupuesto tirado. Medido en PLAT-E39.T1: 40 turnos de sonnet sin producir un archivo.

  El mensaje ofrece las dos salidas reales — subir `--max-turns` o **trocear la tarea**. Si la
  tarea mezcla varias cosas con criterios de aceptación distintos, trocear es lo correcto: más
  presupuesto sólo compra un fallo más caro.
- **`--max-iterations`** alcanzado (si se pasó > 0).
- **Kill-switch** — si aparece el archivo `.loop-stop` en el cwd, corta antes de la próxima
  iteración (freno manual, también se respeta durante la espera de cuota).

### Terminación anormal

Una iteración es anormal cuando muere por `--max-turns` **o** cuando termina sin el marcador
`NEXT-TASK:` (`done`, `empty`, `blocked` o `checkpoint` — los cuatro son cierres válidos). Nunca
cuenta como progreso, **haya escrito o no en disco**.

> Un cambio en disco no es evidencia de que la tarea se completó. El marcador sí.

Antes de este guard (2026-07-26), una invocación que moría por turnos habiendo alcanzado a escribir
algo cambiaba el hash y se registraba como "progreso detectado", reseteando la racha y dejando que
el loop siguiera sobre una tarea a medio hacer. Si además quedaron cambios en disco sin marcador,
el runner lo avisa y lista los repos con working tree sucio — es trabajo a medias que la próxima
iteración heredaría sin saberlo.

## Manejo de cuota / créditos

- **Session limit** (`You've hit your session limit · resets H:MMam/pm (TZ)`): **NO** es fallo —
  parsea el horario de reset, duerme (en tramos de 5 min, atendiendo el kill-switch) hasta ese
  momento + 60s, y reintenta la MISMA invocación. No consume iteración ni suma a la racha.
- **Créditos agotados** (`You're out of usage credits. Run /usage-credits …`): **terminal** — no
  trae hora de reset (hay que recargar o cambiar de modelo), así que **corta limpio** sin dormir ni
  sumar a la racha. Recargá con `/usage-credits` o relanzá con `--model <otro>`.
- **Tope de gasto** (`You've hit your monthly spend limit …`): **terminal** — tampoco trae reset y
  no se arregla con `/model`. Corta limpio; subilo en `claude.ai/settings/usage` y relanzá.

Las tres son condiciones distintas y se chequean en ese orden. Ninguna suma a la racha de
no-progreso: cortar con el mensaje engañoso "sin cambios en roadmap" cuando en realidad se acabó
el cupo hace perder tiempo diagnosticando lo que no es.

## Herramientas de contexto

Scripts de apoyo, todos con salida legible y código de salida útil para encadenar:

| Script | Qué hace |
|---|---|
| `roadmap-query.py --proyecto <p>` | Épicas elegibles del proyecto con `depende_de:` ya resuelto, ~5 KB en vez de los 47,8 KB del índice. Es lo que usa la fase SELECT. Acepta `--epica <KEY-ENN>` y `--json`. |
| `split-roadmap.py check` | Falla si una descripción volvió al índice del roadmap. Correr después de tocarlo. `split` migra las que se hayan colado. |
| `harness-drift.sh` | Reporta divergencia entre la fuente (`team-ai-harness`), la instalación (`management`) y lo generado (`.claude`). Sólo lee, así que corre aunque ambos lados estén sucios. |

**Por qué existe el split del roadmap**: el índice es lo único que toda iteración carga entero para
elegir la próxima tarea, y el 53% de sus bytes eran descripciones — 32,7 KB de ellas de épicas ya
`completo`, cargadas para no usarse nunca. Hoy el índice tiene los campos y
`roadmap-descripciones.yaml` las descripciones, que se leen bajo demanda y de a una.

**Por qué existe `harness-drift.sh`**: el sync fuente→instalación (`install-management.sh
--upgrade`) aborta si la instalación tiene cambios sin commitear en las rutas que va a sobrescribir.
El guard es correcto — `--upgrade` pisa y git no lo recupera — pero como siempre hay trabajo sin
commitear de alguna sesión, nunca corre y la instalación queda atrás **en silencio**. Y `.claude/`,
que es lo que el loop ejecuta, se genera desde la instalación: el 2026-07-27 estaba 8 agentes atrás.

### Contexto por iteración

Medido antes y después del cambio del 2026-07-27:

| | Antes | Después (pico por fase) |
|---|---|---|
| `CLAUDE.md` (auto) | 15,7 KB | 15,7 KB |
| skill `loop-next-task` | 25,3 KB | 13,6 KB (core; `reference/` bajo demanda) |
| roadmap | 122,1 KB | 4,8 KB (vía `roadmap-query.py`) |
| pack del dispatcher | — | 12,0 KB (`native`) |
| archivo de épica | 39,8 KB (la mayor) | 9,3 KB (promedio de las activas) |
| **total** | **201,9 KB** | **54,6 KB (−73%)** |

## Guardrail L4

El loop implementa las tareas hasta el gate de build/test verdes, pero **nunca commitea ni pushea
código** de un servicio L4 (money/auth/identidad/PII) sin sign-off del owner. Sí aplica DDL local
contra `lab-postgres` (dev local) cuando el artefacto está versionado primero. Antes de cualquier
`git commit`/`push` escribe la escalación en `management/escalations/AAAA-MM-DD_<épica>-<tarea>.md`
+ Engram y la verifica en disco. El sign-off del gate de revisión de plan (L4) y el de merge/push
son del owner, en sesión interactiva.

## Permisos

Corre con `--dangerously-skip-permissions` (override del owner, 2026-07-02). El kill-switch
`.loop-stop` es el freno manual principal; el guardrail L4 sigue vigente e independiente.

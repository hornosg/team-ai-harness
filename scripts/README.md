# `loop-runner.sh` — driver de loop autónomo

Itera `claude -p "@meta-router next-task …"` con **contexto fresco por iteración** hasta que se
cumple una condición de corte. Cada pasada elige y ejecuta la primera tarea desbloqueada del
roadmap (o de una épica fijada), deja el estado en disco + Engram, y la siguiente iteración retoma
sin ambigüedad. La skill que decide qué hacer es `skills/shared/loop-next-task/SKILL.md`.

> **⚠️ El script vive en DOS lugares sin sync automático:** `management/scripts/loop-runner.sh`
> (repo `devy-management`) y `active/team-ai-harness/scripts/loop-runner.sh` (canónico, repo
> `team-ai-harness`). Al editarlo, **actualizar y commitear en ambos** — deben quedar byte-idénticos.

## Uso

```
./scripts/loop-runner.sh [--proyecto <nombre>] [--epica <KEY-ENN>]
                         [--roadmap <path>]
                         [--provider anthropic|ollama] [--model <alias>] [--ollama-model <id>]
                         [--max-iterations N] [--max-turns N] [--dry-run]
```

## Flags

| Flag | Default | Qué hace |
|------|---------|----------|
| `--proyecto <nombre>` | vacío (infiere del cwd) | Filtra el roadmap a ese proyecto (`platform`, `mercado-cercano`, …). |
| `--epica <KEY-ENN>` | vacío (selección automática) | **Fija** una épica (ej. `PLAT-E28`). Tiene precedencia sobre cualquier `en-progreso`. Valida §0: existencia, proyecto consistente, no-completa, `depende_de` satisfecho. NO saltea dependencias. |
| `--roadmap <path>` | `$DEVY_ROADMAP_PATH` (o `~/Projects/management/roadmap.yaml`) | Roadmap único multi-proyecto a leer. |
| `--provider anthropic\|ollama` | `anthropic` | Backing del loop. `anthropic` = `claude -p` nativo (histórico). `ollama` = `ollama launch claude` contra el endpoint de Ollama (modelo abierto, no consume cupo Anthropic; el backing pasa a global y los artefactos a `reforzado`, L4 nunca auto-aprueba). |
| `--model <alias>` | vacío (modelo de la config) | **Solo provider anthropic.** Fija el modelo del `claude -p`: alias `opus`/`sonnet`/`haiku`/`fable` o nombre completo (`claude-sonnet-5`). Sin el flag = comportamiento histórico. Útil para correr en otro modelo/pool (ej. tras `out of usage credits`). |
| `--ollama-model <id>` | `kimi-k2.7-code:cloud` | Modelo cuando `--provider ollama`. |
| `--max-iterations N` | `0` (sin límite duro) | Tope de iteraciones. El freno real es la racha de no-progreso. |
| `--max-turns N` | `40` | `--max-turns` que se le pasa a `claude -p` por iteración. |
| `--dry-run` | — | No ejecuta la invocación real; valida el driver e imprime qué invocaría. |

## Formas de ejecución (ejemplos)

```bash
# Épica fijada, provider y modelo por default (lo más común)
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E28

# Selección automática: la primera épica desbloqueada del proyecto
./management/scripts/loop-runner.sh --proyecto platform

# Fijar el modelo Anthropic del loop (p. ej. para otro pool de cupo)
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E28 --model sonnet
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E29 --model fable

# Fallback sin cupo Anthropic: backing global kimi vía Ollama
./management/scripts/loop-runner.sh --proyecto platform --ollama-model kimi-k2.7-code:cloud --provider ollama

# Roadmap alternativo + tope de iteraciones
./management/scripts/loop-runner.sh --roadmap /ruta/otro-roadmap.yaml --max-iterations 5

# Validar el driver sin ejecutar (imprime la invocación que haría)
./management/scripts/loop-runner.sh --proyecto platform --epica PLAT-E28 --model fable --dry-run
```

## Condiciones de corte

El loop termina (limpio) cuando:

- **`NEXT-TASK: empty`** — la épica/roadmap no tiene tareas ejecutables (backlog vacío). En modo
  `--epica` suele significar "épica completa salvo acción del owner" (ej. sign-off L4 pendiente).
- **`NEXT-TASK: blocked`** (solo con `--epica`) — la épica está bloqueada (dependencia sin cumplir o
  checkpoint); reiterar no la desbloquea → corta.
- **Racha de no-progreso** — 2 iteraciones consecutivas sin cambio del hash de estado
  (`NO_PROGRESS_THRESHOLD`) → corta.
- **`--max-iterations`** alcanzado (si se pasó > 0).
- **Kill-switch** — si aparece el archivo `.loop-stop` en el cwd, corta antes de la próxima
  iteración (freno manual, también se respeta durante la espera de cuota).

## Manejo de cuota / créditos

- **Session limit** (`You've hit your session limit · resets H:MMam/pm (TZ)`): **NO** es fallo —
  parsea el horario de reset, duerme (en tramos de 5 min, atendiendo el kill-switch) hasta ese
  momento + 60s, y reintenta la MISMA invocación. No consume iteración ni suma a la racha.
- **Créditos agotados** (`You're out of usage credits. Run /usage-credits …`): **terminal** — no
  trae hora de reset (hay que recargar o cambiar de modelo), así que **corta limpio** sin dormir ni
  sumar a la racha. Recargá con `/usage-credits` o relanzá con `--model <otro>`.

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

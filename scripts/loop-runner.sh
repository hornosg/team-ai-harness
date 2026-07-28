#!/usr/bin/env bash
# loop-runner.sh
# Driver de loop autónomo: itera `claude -p "@meta-router next-task"` con contexto
# fresco por iteración hasta agotar backlog o tocar un límite.
#
# Piezas de diseño (PROP-008 / E33 — epicas/E33-agent-loops-harness.md):
#   - Contexto fresco por iteración: cada `claude -p` arranca sin historial previo.
#   - --max-turns 40 como proxy de presupuesto por iteración (contexto, no conteo de loops).
#   - Se detiene solo por: backlog vacío, kill-switch .loop-stop, o 2 iteraciones
#     consecutivas sin ningún [x] nuevo en roadmap.yaml/épica (diff-based, no confía
#     únicamente en el string NEXT-TASK que reporta la skill).
#
# Uso:
#   ./scripts/loop-runner.sh [--proyecto <nombre>] [--epica <KEY-ENN>]
#                            [--roadmap path/a/roadmap.yaml]
#                            [--provider anthropic|ollama|codex] [--model <alias>] [--ollama-model <id>]
#                            [--phases split|single] [--select-agent <a>] [--exec-agent <a>]
#                            [--max-iterations N] [--max-turns N] [--dry-run]
#
# roadmap.yaml es ÚNICO y multi-proyecto desde 2026-07-02 (decisión del owner) — path por
# defecto: $DEVY_ROADMAP_PATH (definida en ~/.zshrc; fallback ~/Projects/management/roadmap.yaml
# si la env var no está seteada, ej. corriendo desde un shell no interactivo que no sourceó
# ~/.zshrc). --roadmap sigue existiendo para overridear el path en casos raros (testing).
#
# --proyecto es la pieza que realmente evita el bug encontrado en el piloto de E33/T7: el cwd
# NO determina de forma confiable qué `proyecto:` del roadmap único hay que mirar (correr el
# loop dentro de active/mercado-cercano/services/ledger-service podría hacer que se infiera
# proyecto=mercado-cercano cuando la épica target es proyecto=platform). Pasarlo siempre que
# se sepa de antemano contra qué proyecto corre el loop.
#
# --epica (opcional) fija el loop a UNA épica puntual del roadmap, por id prefijado
# (ej. PLAT-E25 — el prefijo resuelve el proyecto vía el bloque `prefijos:` del roadmap,
# así que --proyecto se vuelve redundante aunque puede pasarse igual; si ambos vienen y no
# coinciden, la skill corta con blocked). Sin --epica el comportamiento es el histórico:
# la skill elige épica por estado/prioridad/depende_de. Con --epica, la selección ignora
# cualquier otra épica en-progreso y trabaja SOLO tareas de esa épica hasta que se completa
# (NEXT-TASK: empty) o queda bloqueada (NEXT-TASK: blocked — el runner también corta ahí,
# reiterar una épica fijada que no puede avanzar no aporta nada). Origen: pedido del owner
# 2026-07-08 — PLAT-E25 quedó huérfana porque la selección global nunca la elegía.
#
# TODA invocación pasa por `scripts/agent-dispatcher.py` (2026-07-27). Antes sólo `--provider codex`
# lo usaba y las ramas anthropic/ollama llamaban al CLI directo, salteándose la resolución
# agente→modelo→contexto: no se cargaba el frontmatter del agente y toda la iteración corría al
# precio del `--model` del loop. Ahora el modelo sale del frontmatter de cada agente (haiku para
# orquestar, sonnet para ejecutar, opus para gates L4) salvo override explícito con --model.
#
# --provider (opcional, default anthropic) elige el backing del loop:
#   - anthropic (default): dispatcher con `--provider claude` → `claude -p` contra el backend
#     Anthropic nativo, con context-mode `native` (punteros en vez de contexto inline: el runtime
#     ya carga los CLAUDE.md y tiene el tool `Skill`).
#   - ollama: invoca `ollama launch claude --model <OLLAMA_MODEL> -- -p ...`, que lanza Claude Code
#     apuntando al endpoint de Ollama con un modelo abierto (default kimi-k2.7-code:cloud). No consume
#     cupo Anthropic. --ollama-model overridea el modelo (ej. kimi-k2.6:cloud). Impacto de calidad/
#     ceremonia del backing global kimi (artefactos 'reforzado', L4 nunca auto-aprueba): ver la skill
#     provider-selector, sección "Excepción — fallback kimi".
#     NOTA: la espera por cuota (wait_for_quota_reset) es específica del bloqueo de Anthropic; bajo
#     ollama no aplica y un rate-limit de kimi-cloud hoy se contaría como no-progreso. Manejo dedicado
#     pendiente hasta tener un ejemplo del formato de error que devuelve kimi-cloud.
#   - codex: dispatcher con `codex exec` y context-mode `full` — Codex no conoce el harness ni
#     tiene el tool `Skill`, así que el contexto y las skills viajan inline. Requiere --model.
#
# --model (opcional) fija el modelo de TODAS las fases, pisando el frontmatter de cada agente —
#   alias `opus`/`sonnet`/`haiku`/`fable` o nombre completo (`claude-sonnet-5`). Es un override de
#   emergencia (ej. el pool del default se quedó "out of usage credits"), no el modo normal: sin
#   --model cada agente corre en el modelo que declara. Para el provider ollama el modelo lo fija
#   --ollama-model (el backing es global, el frontmatter no aplica).
#
# --phases split|single (default split) — ver "Contrato de fases" en la skill loop-next-task:
#   split  = SELECT (@meta-router, haiku: elige la tarea, no ejecuta) → EXEC (el agente que SELECT
#            designó, con su modelo: ejecuta esa única tarea y cierra). Es lo que hace que el
#            modelo por agente signifique algo, y lo que le da a cada fase su contexto mínimo.
#   single = una sola invocación hace todo (comportamiento previo). Escape hatch si el handoff
#            entre fases falla.
# --select-agent / --exec-agent overridean el agente de SELECT y el fallback de EXEC.
#
# Permisos: corre con --dangerously-skip-permissions (override del owner, 2026-07-02 —
# supersede la mitigación original de PROP-008 de nunca usarlo sobre $HOME). Riesgo
# asumido explícitamente por el owner. El kill-switch (.loop-stop) es el freno manual
# principal; el guardrail L4-nunca-commitea-sin-sign-off sigue vigente e independiente.
#
# Cuota de sesión agotada (owner, 2026-07-10): cuando `claude -p` devuelve el bloqueo de
# Claude Code "You've hit your session limit · resets H:MMam/pm (TZ)", el runner NO lo trata
# como fallo/no-progreso — parsea el horario de reset, duerme (en tramos de 5min, chequeando
# el kill-switch) hasta ese momento + 60s de margen, y reintenta la MISMA invocación sin
# consumir cupo de --max-iterations ni sumar a la racha de no-progreso. Ver wait_for_quota_reset().
#
# Créditos de uso agotados (2026-07-20): distinto del session-limit — "You're out of usage
# credits. Run /usage-credits …" NO trae hora de reset (hay que recargar o cambiar de modelo),
# así que dormir no aplica. El runner corta LIMPIO (is_credits_exhausted → break), sin sumar a la
# racha de no-progreso (antes lo hacía y cortaba con el mensaje engañoso "sin cambios en roadmap").

set -euo pipefail

ROOT="$(pwd)"
ROADMAP_GLOB="${DEVY_ROADMAP_PATH:-$HOME/Projects/management/roadmap.yaml}"
PROYECTO=""        # vacío = dejar que @meta-router infiera el proyecto del cwd (ver --proyecto)
EPICA=""           # vacío = selección automática de épica; ver --epica arriba
PROVIDER="anthropic"                  # backing del loop: anthropic (default) | ollama | codex
MODEL=""                              # --model de anthropic/codex: vacío = default solo en anthropic
OLLAMA_MODEL="kimi-k2.7-code:cloud"   # modelo cuando --provider ollama (--ollama-model lo overridea)
CODEX_CAVEMAN_MODE="${CODEX_CAVEMAN_MODE:-auto}" # auto | off | lite | full | ultra | wenyan
MAX_ITERATIONS=0   # 0 = sin límite duro; el freno real es no_progress_threshold
MAX_TURNS=40
# Fases por iteración (ver §"Contrato de fases" en skills/shared/loop-next-task/SKILL.md):
#   split  (default) — dos invocaciones: SELECT (elige la tarea) → EXEC (la ejecuta). Cada fase
#           corre con SU agente y por lo tanto con el modelo declarado en el frontmatter de ese
#           agente: haiku para elegir, sonnet/opus para ejecutar según ceremony level.
#   single — una sola invocación con $SELECT_AGENT haciendo todo (comportamiento previo al
#           2026-07-27). Escape hatch: si el hand-off entre fases falla, esto sigue funcionando.
PHASES="split"
SELECT_AGENT="meta-router"      # fase SELECT: clasificar/elegir, no ejecutar (haiku por frontmatter)
FALLBACK_EXEC_AGENT="dev-senior-backend"  # si SELECT no designa un agente válido para EXEC
SELECT_MAX_TURNS=15             # SELECT sólo lee y decide: no necesita el presupuesto de EXEC
SECURITY_AGENT="dev-security"   # fase REVIEW en L4 — opus y read-only por frontmatter
REVIEW_MAX_TURNS=25             # gate de PLAN: revisar un diseño entero y sus decisiones abiertas
# Gate de COMMIT (una tarea ya implementada): revisar un diff acotado es mucho menos trabajo que
# revisar un plan completo. Distinguirlos importa por costo: una épica L4 con 25 tareas dispara 25
# gates de commit, y cobrarlos al precio de un gate de plan agota la ventana de uso antes de
# terminar la épica (medido en PLAT-E39, 2026-07-27: 32% de la ventana de 5h en la primera tarea).
REVIEW_COMMIT_TURNS=15
# La remediación automática aplica al PLAN (corregir un diseño es barato y acotado). Sobre un diff
# ya implementado, un `bloqueante` significa reescribir código: eso vuelve por el loop normal como
# una tarea más, no por un ciclo de remediación dentro del gate.
REMEDIATE_ON_COMMIT=false
# Sign-off interactivo del owner tras la revisión L4. OPT-IN y sólo con TTY: el loop está pensado
# para correr desatendido, y un `read` sin terminal (cron, nohup, background) cuelga el proceso
# para siempre. Sin TTY o sin el flag, el comportamiento es el de siempre: cortar con checkpoint
# dejando el veredicto escrito. Ver también §D.5 de la skill ("nunca esperar input en headless").
INTERACTIVE_SIGNOFF=false
SIGNOFF_TIMEOUT=600             # segundos; vencido, se trata como "no aprobado" y corta
# Remediación de un veredicto `bloqueante`: el agente que escribió el plan resuelve las objeciones
# y @dev-security re-revisa. Tope BAJO a propósito — si dos revisiones seguidas siguen bloqueando,
# el problema es de diseño y lo tiene que mirar una persona, no otra vuelta del ciclo.
REMEDIATE_AGENT="dev-architect"  # quien corrige el plan (necesita Write; dev-security es read-only)
REMEDIATE_CYCLES=1               # 0 = desactivado: bloqueante corta de una
NO_PROGRESS_THRESHOLD=2
# Terminaciones anormales consecutivas (max-turns o salida sin marcador NEXT-TASK) antes de cortar.
# Más bajo que NO_PROGRESS_THRESHOLD a propósito: una anormal cuesta el presupuesto completo de
# turnos sin entregar nada, así que conviene cortar antes que ante una iteración que cierra limpio.
ABNORMAL_THRESHOLD=2
# Muerte por --max-turns: umbral propio, MÁS BAJO, porque no es el mismo tipo de fallo.
#
# Un crash del CLI o una salida truncada pueden ser transitorios: reintentar tiene sentido. Agotar
# el presupuesto de turnos es DETERMINÍSTICO — la misma tarea, con el mismo presupuesto y el mismo
# contexto fresco, vuelve a agotarlo. Reintentar sólo compra otro presupuesto completo tirado.
#
# Medido en PLAT-E39.T1 (2026-07-27): 40 turnos de sonnet con la épica entera en contexto, sin
# producir un solo archivo. Con el umbral común de 2, eso se pagaba dos veces antes de avisar.
MAX_TURNS_THRESHOLD=1
# Raíz del lab. $DEVY_PATH es el contrato (ver ~/.zshrc), pero el script también se invoca desde
# shells que no lo exportan: se deriva de la ubicación del propio script como fallback.
LAB_ROOT="${DEVY_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# Directorio de traza por iteración. Vacío = sin traza (comportamiento previo).
ITER_LOG_DIR="${ITER_LOG_DIR:-$LAB_ROOT/management/.loop-logs/$(date +%Y%m%d-%H%M%S)}"
KILL_SWITCH="$ROOT/.loop-stop"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --roadmap) ROADMAP_GLOB="$2"; shift 2 ;;
    --proyecto) PROYECTO="$2"; shift 2 ;;
    --epica) EPICA="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --ollama-model) OLLAMA_MODEL="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --phases) PHASES="$2"; shift 2 ;;
    --select-agent) SELECT_AGENT="$2"; shift 2 ;;
    --exec-agent) FALLBACK_EXEC_AGENT="$2"; shift 2 ;;
    --security-agent) SECURITY_AGENT="$2"; shift 2 ;;
    --no-security-review) SECURITY_AGENT=""; shift ;;
    --interactive-signoff) INTERACTIVE_SIGNOFF=true; shift ;;
    --signoff-timeout) SIGNOFF_TIMEOUT="$2"; shift 2 ;;
    --remediate-agent) REMEDIATE_AGENT="$2"; shift 2 ;;
    --remediate-cycles) REMEDIATE_CYCLES="$2"; shift 2 ;;
    --review-turns) REVIEW_MAX_TURNS="$2"; shift 2 ;;
    --review-commit-turns) REVIEW_COMMIT_TURNS="$2"; shift 2 ;;
    --remediate-on-commit) REMEDIATE_ON_COMMIT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

codex_caveman_installed() {
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local agents_home="${AGENTS_HOME:-$HOME/.agents}"
  local skills_root

  for skills_root in "$codex_home/skills" "$agents_home/skills"; do
    [[ -f "$skills_root/caveman/SKILL.md" ]] && return 0
    if find "$skills_root" -path '*/caveman/SKILL.md' -type f -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done
  return 1
}

# --provider acepta anthropic|ollama|codex; el binario requerido se valida antes de iterar.
case "$PROVIDER" in
  anthropic|ollama|codex) ;;
  *) echo "Provider desconocido: '$PROVIDER' (usar anthropic|ollama|codex)" >&2; exit 1 ;;
esac
if [[ "$PROVIDER" == "ollama" ]] && ! command -v ollama >/dev/null 2>&1; then
  echo "--provider ollama pero 'ollama' no está en el PATH" >&2; exit 1
fi
if [[ "$PROVIDER" == "codex" ]]; then
  # CODEX_BIN permite usar la instalación del plugin de VS Code aunque su directorio
  # no haya sido exportado al shell interactivo. Se mantiene command -v como primera
  # opción para no alterar instalaciones normales.
  if [[ -n "${CODEX_BIN:-}" ]]; then
    if [[ ! -x "$CODEX_BIN" ]]; then
      echo "CODEX_BIN no apunta a un ejecutable: $CODEX_BIN" >&2; exit 1
    fi
  else
    CODEX_BIN="$(command -v codex 2>/dev/null || true)"
    if [[ -z "$CODEX_BIN" ]]; then
      for candidate in "$HOME/.local/bin/codex" "$HOME/.cargo/bin/codex"; do
        if [[ -x "$candidate" ]]; then
          CODEX_BIN="$candidate"
          break
        fi
      done
    fi
    if [[ -z "$CODEX_BIN" ]]; then
      CODEX_BIN="$(find "$HOME/.vscode-server/extensions" "$HOME/.vscode/extensions" \
        -type f -path '*/openai.chatgpt-*/bin/*/codex' -perm -111 -print -quit 2>/dev/null || true)"
    fi
    if [[ -z "$CODEX_BIN" ]]; then
      echo "--provider codex pero 'codex' no está en el PATH; definí CODEX_BIN=/ruta/al/binario/codex" >&2
      exit 1
    fi
  fi
  export CODEX_BIN
fi
if [[ "$PROVIDER" == "codex" && -z "$MODEL" ]]; then
  echo "--provider codex requiere --model (ej. --model gpt-5.6-luna)" >&2; exit 1
fi
case "$PHASES" in
  split|single) ;;
  *) echo "Fases desconocidas: '$PHASES' (usar split|single)" >&2; exit 1 ;;
esac
case "$CODEX_CAVEMAN_MODE" in
  auto|off|lite|full|ultra|wenyan) ;;
  *) echo "CODEX_CAVEMAN_MODE inválido: '$CODEX_CAVEMAN_MODE' (usar auto|off|lite|full|ultra|wenyan)" >&2; exit 1 ;;
esac
if [[ "$PROVIDER" == "codex" && "$CODEX_CAVEMAN_MODE" == "auto" ]]; then
  if codex_caveman_installed; then
    CODEX_CAVEMAN_MODE="full"
  else
    CODEX_CAVEMAN_MODE="off"
    echo "[loop-runner] Caveman no instalado en CODEX_HOME ni AGENTS_HOME; Codex continúa sin activación de estilo" >&2
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '[loop-runner] %s\n' "$1"; }

# El runner habla de "anthropic"; el dispatcher, de "claude". Mismo backing, distinto vocabulario.
dispatch_provider() {
  case "$PROVIDER" in
    anthropic) echo "claude" ;;
    *) echo "$PROVIDER" ;;
  esac
}

# Modelo que le corresponde a una invocación.
#   - Sin --model: NO se pasa nada y el dispatcher lo resuelve del frontmatter del agente
#     (haiku para orquestadores, sonnet para ejecución, opus para gates L4). Éste es el punto
#     de rutear anthropic por el dispatcher: antes `claude -p` corría todo al mismo modelo.
#   - Con --model: override explícito del owner, gana sobre el frontmatter (ej. para escapar de
#     un pool sin créditos). Se aplica a TODAS las fases a propósito: es un override de emergencia.
#   - ollama: el modelo lo fija --ollama-model; el frontmatter no aplica (el backing es global).
dispatch_model_args() {
  if [[ "$PROVIDER" == "ollama" ]]; then
    printf '%s\n%s\n' "--model" "$OLLAMA_MODEL"
  elif [[ -n "$MODEL" ]]; then
    printf '%s\n%s\n' "--model" "$MODEL"
  fi
}

# Corre UNA invocación a través de agent-dispatcher.py y devuelve el texto de salida del agente
# ya desescapado.
#
# Por qué pasa por el dispatcher también en anthropic (2026-07-27): antes esta rama llamaba
# `claude -p` directo, salteándose el dispatcher por completo. Consecuencia: no se cargaba el
# frontmatter del agente, no se aplicaba el modelo declarado por agente, y toda la iteración
# corría al precio del --model del loop (o del default de la config). El dispatcher es el único
# lugar donde vive la resolución agente→modelo→contexto; tener una rama que lo evita es tener
# dos mecanismos que divergen.
#
# El dispatcher emite JSON en una línea (con \n escapados). Se desescapa acá para que TODOS los
# detectores de abajo (is_quota_block, has_terminal_marker, LOOP-SELECT) trabajen sobre texto
# plano, igual que cuando la salida venía de `claude -p` directo. Antes de este cambio el path
# codex grepeaba sobre el JSON crudo.
# Resume una línea JSON del dispatcher en una línea legible. Función propia y no un `python3 -c`
# inline dentro de un `log "...$(...)"`: ahí las comillas quedan triplemente anidadas (bash → $()
# → python) y el escape se rompe en silencio.
summarize_dispatch() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
print("@%s modelo=%s context_mode=%s pack=%sB" % (d["agent"], d["model"], d.get("context_mode"), d["context_bytes"]))
'
}

# Escribe el registro del gate L4 en disco. El sign-off del owner NO puede ser sólo un keystroke:
# sin rastro de qué se aprobó, con qué veredicto de seguridad y cuándo, el gate L4 se degrada a un
# trámite. Este archivo es lo que después justifica el commit.
write_signoff() {
  local decision="$1" epica="$2" tarea="$3" verdict="$4" review="$5"
  local dir="$LAB_ROOT/management/escalations"
  local file="$dir/$(date +%Y-%m-%d)_${epica}-${tarea}-signoff.md"
  mkdir -p "$dir"
  # `printf '- ...'` NO: printf toma el guión inicial como flag y falla ("invalid option").
  # Todo el contenido va por %s, que además evita que un `%` en la revisión rompa el formato.
  {
    printf '# Gate L4 — %s.%s\n\n' "$epica" "$tarea"
    printf '%s\n' "- **Decisión del owner**: $decision"
    printf '%s\n' "- **Fecha**: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf '%s\n' "- **Veredicto de @$SECURITY_AGENT**: $verdict"
    printf '%s\n\n' "- **Modo**: sign-off desde la consola del loop (loop-runner.sh)"
    printf '%s\n\n%s\n' "## Revisión de seguridad" "$review"
  } > "$file"
  # Verificación en disco, mismo criterio que la escalación L4 de la skill: nunca asumir que un
  # write reportado ocurrió.
  if [[ -s "$file" ]]; then
    log "  sign-off registrado en ${file#"$LAB_ROOT"/}"
    return 0
  fi
  log "  ⚠ NO se pudo escribir el sign-off en $file — tratando como NO aprobado"
  return 1
}

# Pregunta al owner. Devuelve 0 sólo ante un "s" explícito. Cualquier otra cosa —"n", timeout,
# EOF, respuesta vacía— es NO: ante la duda, en L4 no se avanza.
prompt_signoff() {
  local epica="$1" tarea="$2" verdict="$3" answer=""
  printf '\n'
  printf '  ┌─ GATE L4 ─────────────────────────────────────────────\n'
  printf '  │ %s.%s\n' "$epica" "$tarea"
  printf '  │ Veredicto de @%s: %s\n' "$SECURITY_AGENT" "$verdict"
  printf '  │ La revisión completa está arriba, en la salida de la fase REVIEW.\n'
  printf '  └───────────────────────────────────────────────────────\n'
  printf '  ¿Aprobás? [s/N] (timeout %ss → NO): ' "$SIGNOFF_TIMEOUT"
  # `read -t` sale con código >128 al vencer; con set -e eso mataría el runner.
  read -r -t "$SIGNOFF_TIMEOUT" answer || answer=""
  printf '\n'
  case "${answer,,}" in
    s|si|sí|y|yes) return 0 ;;
    "") log "  sin respuesta (timeout o EOF) → NO aprobado" ; return 1 ;;
    *) return 1 ;;
  esac
}

# Vuelca la traza de la iteración. Es una función y no un bloque inline porque hay que llamarla
# también ANTES de cada `break`: cuando el gate L4 cortaba dentro del bloque de fases, la escritura
# quedaba río abajo y se perdía el log justo de la iteración que falló. En PLAT-E39.T1 el archivo
# decía "FASE EXEC: <no corrió>" cuando EXEC había corrido y dejado un sign-off.
write_iter_log() {
  [[ -n "${ITER_LOG_DIR:-}" ]] || return 0
  mkdir -p "$ITER_LOG_DIR"
  # TODAS las fases van al log, no sólo la que define el marcador terminal: cuando una iteración
  # sale mal, la mitad de las veces la causa está en la selección o en la revisión.
  {
    if [[ "$PHASES" == "split" ]]; then
      printf '===== FASE SELECT (@%s) =====\n%s\n' "$SELECT_AGENT" "${select_output:-<no corrió>}"
      printf '\n===== FASE EXEC (@%s) =====\n%s\n' "${sel_agente:-<no despachada>}" "${exec_output:-<no corrió>}"
      if [[ -n "${review_output:-}" ]]; then
        printf '\n===== FASE REVIEW (@%s) =====\n%s\n' "$SECURITY_AGENT" "$review_output"
        printf '\nVEREDICTO: %s\n' "${review_verdict:-<ninguno>}"
      fi
    else
      printf '%s\n' "$output"
    fi
  } > "$ITER_LOG_DIR/iter-$(printf '%03d' "$iteration").log"
}

# Corre el gate L4 completo: REVIEW de seguridad → sign-off del owner → registro en disco.
#
# Se invoca desde DOS lugares, y esa es la razón de que sea una función:
#   a) después de EXEC, sobre trabajo recién hecho (plan escrito o diff implementado);
#   b) cuando SELECT reporta que la épica está frenada por un gate L4 que quedó pendiente de una
#      iteración anterior — el caso de PLAT-E39, donde el plan ya existía desde antes.
#
# Devuelve 0 si el gate quedó APROBADO (el loop puede seguir), 1 si no (el loop corta).
run_l4_gate() {
  local epica="$1" tarea="$2" contexto="$3" modo="${4:-plan}"

  [[ -n "$SECURITY_AGENT" ]] || { log "  fase REVIEW desactivada (--no-security-review) → no se puede pasar el gate"; return 1; }

  # Presupuesto y política de remediación según qué se revisa.
  local turns="$REVIEW_MAX_TURNS" cycles="$REMEDIATE_CYCLES"
  if [[ "$modo" == "commit" ]]; then
    turns="$REVIEW_COMMIT_TURNS"
    [[ "$REMEDIATE_ON_COMMIT" == true ]] || cycles=0
  fi

  local prompt="Revisión de seguridad OBLIGATORIA del gate L4 (RULE-10). $scope_prompt"
  prompt="$prompt Épica: $epica. Tarea/alcance: $tarea. $contexto"
  prompt="$prompt Revisá la superficie de auth/identidad/money/PII/RLS: si lo que hay es un PLAN de"
  prompt="$prompt épica, revisá el diseño y sus decisiones abiertas; si hay una tarea implementada,"
  prompt="$prompt revisá el diff sin commitear en el repo del servicio."
  prompt="$prompt Sos read-only: NO edites, NO commitees, NO 'arregles' — señalá."
  prompt="$prompt Aplicá la skill owasp-top10. Sé concreto: archivo y línea cuando corresponda, y"
  prompt="$prompt pronunciate sobre CADA decisión de diseño abierta que encuentres."
  prompt="$prompt Terminá SIEMPRE con la línea 'SECURITY-REVIEW: ok|objeciones|bloqueante <resumen>'"
  prompt="$prompt donde 'bloqueante' significa que NO debe aprobarse como está."

  local cycle=0 first_verdict="" remediation_trail=""
  while :; do
    log "iteración $iteration — fase REVIEW L4 ($modo) de $epica.$tarea con @$SECURITY_AGENT (ciclo $((cycle + 1)), --max-turns $turns)"
    review_output="$(dispatch_agent "$SECURITY_AGENT" "$prompt" "$turns")"
    echo "$review_output"
    review_verdict="$(echo "$review_output" | grep -oE "SECURITY-REVIEW: (ok|objeciones|bloqueante)[^\\\\\"]*" | tail -1 || true)"
    [[ -z "$review_verdict" ]] && review_verdict="SECURITY-REVIEW: <sin veredicto — la revisión no cerró>"
    [[ -z "$first_verdict" ]] && first_verdict="$review_verdict"

    echo "$review_verdict" | grep -q "bloqueante" || break

    if [[ "$cycle" -ge "$cycles" ]]; then
      log "⚠ @$SECURITY_AGENT marcó BLOQUEANTE y se agotaron los ciclos de remediación ($cycles)"
      log "  → no se ofrece sign-off. Las objeciones quedan registradas para resolverlas a mano."
      write_signoff "NO APROBADO (bloqueante de seguridad)" "$epica" "$tarea" "$review_verdict" \
        "$review_output$remediation_trail" || true
      return 1
    fi

    # ---------------------------------------------------------------------------------------
    # FASE REMEDIATE — aplicar las objeciones AL PLAN, no al criterio del revisor.
    #
    # El riesgo obvio de que el mismo loop corrija lo que otro agente objetó es que el corrector
    # "satisfaga al revisor" en la letra: reescribir el texto para que la objeción no aplique, sin
    # resolver el problema. Tres cosas lo acotan: el prompt lo prohíbe explícitamente, la
    # re-revisión parte de las objeciones originales (no de cero), y el sign-off del owner sigue
    # siendo obligatorio al final. La remediación NO puede aprobar nada por sí sola.
    # ---------------------------------------------------------------------------------------
    cycle=$((cycle + 1))
    log "iteración $iteration — fase REMEDIATE (ciclo $cycle/$cycles) con @$REMEDIATE_AGENT"
    local rem_prompt="@$SECURITY_AGENT bloqueó el gate L4 de $epica. $scope_prompt"
    rem_prompt="$rem_prompt Tu tarea es RESOLVER sus objeciones bloqueantes EN EL PLAN de la épica."
    rem_prompt="$rem_prompt Reglas, no negociables:"
    rem_prompt="$rem_prompt (1) Corregí el PROBLEMA, no la redacción — está PROHIBIDO reescribir el"
    rem_prompt="$rem_prompt texto para que la objeción deje de aplicar sin resolver el fondo."
    rem_prompt="$rem_prompt (2) Si creés que una objeción es incorrecta, NO la apliques: dejá escrito"
    rem_prompt="$rem_prompt en el plan por qué, con evidencia. Discrepar con argumento es válido; ignorar no."
    rem_prompt="$rem_prompt (3) Sólo tocás el archivo de la épica y sus decisiones de diseño."
    rem_prompt="$rem_prompt NO ejecutes ninguna tarea, NO marqués ningún [x], NO commitees código."
    rem_prompt="$rem_prompt (4) Al final, listá objeción por objeción qué hiciste."
    rem_prompt="$rem_prompt Terminá con 'NEXT-TASK: checkpoint $epica — objeciones L4 remediadas'."
    rem_prompt="$rem_prompt --- REVISIÓN A RESOLVER ---"$'\n'"$review_output"
    local rem_output
    rem_output="$(dispatch_agent "$REMEDIATE_AGENT" "$rem_prompt" "$MAX_TURNS")"
    echo "$rem_output"
    remediation_trail="$remediation_trail"$'\n\n---\n\n'"## Remediación (ciclo $cycle, @$REMEDIATE_AGENT)"$'\n\n'"$rem_output"

    # La re-revisión arranca de las objeciones originales a propósito: preguntar "¿está bien?"
    # sobre un plan corregido invita a mirar sólo lo que cambió. Lo que importa es si el problema
    # que motivó cada objeción sigue existiendo.
    prompt="RE-REVISIÓN del gate L4 de $epica. $scope_prompt"
    prompt="$prompt @$REMEDIATE_AGENT acaba de modificar el plan para atender TUS objeciones previas."
    prompt="$prompt Verificá, objeción por objeción, si el PROBLEMA DE FONDO quedó resuelto — no si"
    prompt="$prompt el texto cambió. Una objeción 'resuelta' reescribiendo el enunciado para que deje"
    prompt="$prompt de aplicar NO está resuelta: marcala bloqueante de nuevo y decilo explícitamente."
    prompt="$prompt Si el plan argumenta por qué una objeción tuya no corresponde, evaluá el argumento."
    prompt="$prompt Seguís siendo read-only. Aplicá owasp-top10."
    prompt="$prompt Terminá con 'SECURITY-REVIEW: ok|objeciones|bloqueante <resumen>'."
    prompt="$prompt --- TUS OBJECIONES ORIGINALES ---"$'\n'"$review_output"
  done

  if [[ "$cycle" -gt 0 ]]; then
    log "✓ gate destrabado tras $cycle ciclo(s) de remediación — veredicto inicial: ${first_verdict:0:60}…"
    review_output="$review_output$remediation_trail"
  fi

  # Una revisión que no cerró NO es una revisión. Ofrecer el sign-off acá sería pedirle al owner
  # que apruebe algo que nadie llegó a mirar — peor que no preguntar, porque el archivo quedaría
  # diciendo "APROBADO" con un veredicto vacío al lado. Observado en PLAT-E39.T1 (2026-07-27): la
  # revisión murió sin emitir `SECURITY-REVIEW:` y el runner igual abrió el prompt.
  if echo "$review_verdict" | grep -q "sin veredicto"; then
    log "⚠ la revisión de seguridad NO cerró (sin marcador SECURITY-REVIEW) → no se ofrece sign-off"
    log "  Probable causa: agotó los $turns turnos. Subilos con --review-turns/--review-commit-turns."
    write_signoff "SIN REVISAR (la revisión de seguridad no cerró)" "$epica" "$tarea" "$review_verdict" "$review_output" || true
    return 1
  fi

  if [[ "$INTERACTIVE_SIGNOFF" != true || ! -t 0 ]]; then
    # Desatendido: queda el análisis hecho y el owner decide fuera del loop.
    write_signoff "PENDIENTE (corrida desatendida — sin sign-off)" "$epica" "$tarea" "$review_verdict" "$review_output" || true
    [[ "$INTERACTIVE_SIGNOFF" == true ]] && log "  (--interactive-signoff pedido pero no hay TTY → queda PENDIENTE)"
    return 1
  fi

  if ! prompt_signoff "$epica" "$tarea" "$review_verdict"; then
    write_signoff "NO APROBADO" "$epica" "$tarea" "$review_verdict" "$review_output" || true
    log "sign-off denegado por el owner"
    return 1
  fi

  write_signoff "APROBADO" "$epica" "$tarea" "$review_verdict" "$review_output" || return 1

  # El sign-off tiene que quedar reflejado en el archivo de la épica: si no, la próxima iteración
  # vuelve a leer "Gate L4: ⏳ pendiente" y reporta blocked otra vez. @dev-security es read-only,
  # así que la anotación la hace un agente con Write, sin ejecutar ninguna tarea.
  local scribe="${sel_agente:-$FALLBACK_EXEC_AGENT}"
  prompt="El owner APROBÓ el gate L4 de $epica ($tarea) el $(date '+%Y-%m-%d %H:%M')."
  prompt="$prompt Veredicto de @$SECURITY_AGENT: $review_verdict."
  prompt="$prompt Tu ÚNICA tarea es registrar ese sign-off en el archivo de la épica: actualizá el"
  prompt="$prompt encabezado del gate (y el guardrail final si lo repite) de '⏳ pendiente' a"
  prompt="$prompt 'aprobado <fecha>', citando el archivo de respaldo en management/escalations/."
  prompt="$prompt NO ejecutes ninguna tarea de la épica, NO marqués ningún [x], NO commitees."
  prompt="$prompt Terminá con la línea 'NEXT-TASK: checkpoint $epica — gate L4 aprobado y registrado'."
  log "  registrando el sign-off en el archivo de la épica con @$scribe"
  local scribe_output
  scribe_output="$(dispatch_agent "$scribe" "$prompt" 12)"
  echo "$scribe_output"
  return 0
}

dispatch_agent() {
  local agent="$1" prompt="$2" turns="$3"
  local args raw
  args=(
    python3 "$SCRIPT_DIR/agent-dispatcher.py"
    --agent "$agent"
    --provider "$(dispatch_provider)"
    --execution-origin "$(dispatch_provider)"
    --task "$prompt"
    --cwd "$ROOT"
    --max-turns "$turns"
    --unattended
  )
  local model_arg
  while IFS= read -r model_arg; do
    [[ -n "$model_arg" ]] && args+=("$model_arg")
  done < <(dispatch_model_args)
  if [[ -n "$PROYECTO" ]]; then
    args+=(--project "$PROYECTO")
  fi
  if [[ "$PROVIDER" == "codex" && "$CODEX_CAVEMAN_MODE" != "off" ]]; then
    args+=(--codex-caveman "$CODEX_CAVEMAN_MODE")
  fi

  raw="$("${args[@]}" 2>&1 || true)"
  printf '%s' "$raw" | unwrap_dispatch
}

# Extrae el texto del agente del JSON del dispatcher. Sin f-strings ni comillas dobles: este
# heredoc-menos viaja dentro de comillas simples de bash y cualquier `\"` llegaría literal a
# python (SyntaxError). Ya pasó dos veces en este archivo.
unwrap_dispatch() {
  python3 -c '
import json, sys
raw = sys.stdin.read()
# Última línea que parsea como JSON del dispatcher; si ninguna parsea (traceback de python,
# binario faltante, etc.) se devuelve el crudo para no perder el diagnóstico.
for line in reversed(raw.splitlines()):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        payload = json.loads(line)
    except ValueError:
        continue
    if "status" in payload:
        print(payload.get("output_tail", ""))
        print("DISPATCH-STATUS: %s model=%s agent=%s" % (
            payload["status"], payload.get("model"), payload.get("agent")))
        sys.exit(0)
print(raw)
'
}

# Detecta el bloqueo de cuota de sesión de Claude Code en la salida de una invocación.
# Formato observado: "You've hit your session limit · resets 1:20pm (America/Buenos_Aires)"
is_quota_block() {
  echo "$1" | grep -qiE "session limit.*resets"
}

# Detecta agotamiento de CRÉDITOS de uso — condición DISTINTA del session-limit: NO trae hora de
# reset, así que dormir no sirve (hay que recargar créditos o cambiar de modelo). Formato observado
# 2026-07-20: "You're out of usage credits. Run /usage-credits to keep using <modelo> or /model to
# switch models." El loop la trata como terminal (corta limpio), no como no-progreso.
is_credits_exhausted() {
  echo "$1" | grep -qiE "out of usage credits"
}

# Detecta el tope de GASTO mensual/semanal — tercera condición distinta de las dos anteriores.
# No trae hora de reset (no sirve dormir) y no se arregla con /model. Formato observado 2026-07-26:
# "You've hit your monthly spend limit · raise it at claude.ai/settings/usage". Terminal.
is_spend_limit() {
  echo "$1" | grep -qiE "hit your (monthly|weekly|daily) spend limit"
}

# Detecta que la invocación murió por agotar el presupuesto de turnos ANTES de terminar la tarea.
# Formato observado: "Error: Reached max turns (40)". Es una TERMINACIÓN ANORMAL: el agente quedó a
# mitad de camino y puede haber dejado archivos a medio editar. Antes de este chequeo el loop no la
# distinguía de una iteración sana — y si el agente alcanzó a escribir algo, el hash de estado
# cambiaba y se registraba como "progreso detectado", reseteando la racha de no-progreso.
is_max_turns() {
  echo "$1" | grep -qiE "Reached max turns"
}

# La skill loop-next-task cierra SIEMPRE con un marcador terminal explícito
# (`NEXT-TASK: done|empty|blocked ...`). Su ausencia significa que la invocación no llegó a
# cerrar la tarea: murió por turnos, por error del CLI, o por un crash del agente.
# Es la única señal confiable de "la iteración terminó lo que empezó".
has_terminal_marker() {
  # `checkpoint` es terminal igual que los otros tres: la iteración cerró lo que podía cerrar y
  # lo dejó registrado. Omitirlo (bug hasta 2026-07-27) hacía que una iteración SANA se contara
  # como muerte por turnos. Observado en PLAT-E39: la fase EXEC emitió
  # `NEXT-TASK: checkpoint platform/PLAT-E39.DESIGN — plan-authored-pending-review` — el caso que
  # la propia skill §B EXIGE para un plan L4 recién escrito — y el runner lo reportó como
  # "terminó sin marcador NEXT-TASK", sumó a la racha anormal y avisó de trabajo a medias
  # inexistente. El dispatcher ya lo clasificaba bien; el desalineado era este grep.
  echo "$1" | grep -qE "NEXT-TASK: (done|empty|blocked|checkpoint)"
}

# ¿El `blocked` de SELECT es un gate L4 esperando revisión/sign-off, o un bloqueo real?
#
# La distinción es la que destraba el deadlock encontrado el 2026-07-27 en PLAT-E39: la fase
# REVIEW corría sólo después de EXEC, pero cuando el gate L4 ya está pendiente de una iteración
# ANTERIOR, SELECT devuelve `blocked` y EXEC nunca corre — así que la revisión que destrabaría el
# gate no se disparaba nunca. El gate esperaba a la revisión y la revisión esperaba al gate.
#
# Un `depende_de:` sin cumplir es otra cosa: ahí no hay nada que revisar, falta que otra épica se
# complete. Por eso se exige mención explícita de gate/sign-off/revisión Y ausencia de `depende_de`.
is_l4_gate_block() {
  echo "$1" | grep -q "NEXT-TASK: blocked" || return 1
  echo "$1" | grep -qi "depende_de pendiente" && return 1
  echo "$1" | grep -qiE "gate L4|sign-off|signoff|revisión (arquitectural|de seguridad)|pending-review"
}

# ¿El checkpoint requiere acción del OWNER, o es sólo una pausa de presupuesto?
# La distinción importa con --epica fijada: reiterar no resuelve un gate de revisión ni una
# escalación fallida (los destraba una persona), pero SÍ es lo correcto ante un checkpoint por
# contexto agotado — ahí la próxima iteración retoma la misma tarea desde donde quedó.
checkpoint_needs_owner() {
  echo "$1" | grep -qE "NEXT-TASK: checkpoint.*(plan-authored-pending-review|escalation-write-failed)"
}

# ¿Qué repos ensució ESTA iteración? Se usa sólo para AVISAR tras una terminación anormal: un
# working tree sucio después de que el agente murió a mitad de tarea es la señal de trabajo a
# medias que la próxima iteración va a heredar sin saberlo.
#
# Compara contra un snapshot tomado ANTES de la iteración. Sin esa comparación el aviso listaba
# todo repo con cambios sin commitear, viniera de donde viniera: en la corrida de PLAT-E39 nombró
# 15 repos, todos sucios desde sesiones anteriores. Un aviso que siempre grita lo mismo no informa
# nada — y peor, entrena a ignorarlo justo cuando dice algo real.
repo_list() {
  local r
  for r in "$LAB_ROOT/management" "$LAB_ROOT"/active/mercado-cercano/services/*/ "$LAB_ROOT/infra/api-gateway"; do
    [[ -d "$r/.git" ]] && printf '%s\n' "${r%/}"
  done
}

# Directorios de servicio que NO son repos git todavía. Un scaffold recién creado por una tarea de
# extracción vive acá: tiene código real y ningún `git status` lo reporta, así que el aviso de
# "trabajo a medias" era ciego justo para el caso donde más importa.
#
# Observado en PLAT-E39.T1a (2026-07-27): EXEC murió por turnos habiendo creado `catalog-service/`
# entero (Dockerfile, go.mod, cmd/, docker-compose.yml y hasta un binario compilado de 20 MB). El
# runner informó "ningún repo cambió en esta iteración" porque el directorio no tenía `.git`.
untracked_service_dirs() {
  local r out=""
  for r in "$LAB_ROOT"/active/mercado-cercano/services/*/ "$LAB_ROOT"/platform/*/; do
    [[ -d "$r" ]] || continue
    [[ -d "$r/.git" ]] && continue
    # Vacío o sólo con ocultos: no es trabajo a medias, es un directorio suelto.
    [[ -n "$(find "$r" -maxdepth 1 -not -name '.*' -not -path "$r" -print -quit 2>/dev/null)" ]] || continue
    out+="$(basename "${r%/}") "
  done
  echo "$out"
}

dirty_snapshot() {
  local r
  while IFS= read -r r; do
    printf '%s\t%s\n' "$(basename "$r")" "$(git -C "$r" status --porcelain 2>/dev/null | md5sum | cut -d' ' -f1)"
  done < <(repo_list)
}

# Repos cuyo estado CAMBIÓ respecto al snapshot recibido en $1.
dirty_repos_since() {
  local before="$1" now name hash prev out=""
  now="$(dirty_snapshot)"
  while IFS=$'\t' read -r name hash; do
    prev="$(printf '%s' "$before" | awk -F'\t' -v n="$name" '$1==n{print $2}')"
    [[ "$hash" != "$prev" ]] && out+="$name "
  done <<< "$now"
  echo "$out"
}

# Duerme hasta el horario de reset reportado por Claude Code (+60s de margen), en tramos de
# hasta 5min para poder atender el kill-switch durante la espera. Devuelve 1 si el kill-switch
# se activó mientras esperaba (el loop debe cortar), 0 si terminó de esperar normalmente.
wait_for_quota_reset() {
  local block_text="$1"
  local reset_raw tz today_str target_epoch now_epoch remaining chunk

  reset_raw="$(echo "$block_text" | grep -oiE 'resets[[:space:]]+[0-9]{1,2}:[0-9]{2}[[:space:]]*(am|pm)' | head -1 | grep -oiE '[0-9]{1,2}:[0-9]{2}[[:space:]]*(am|pm)' | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
  tz="$(echo "$block_text" | grep -oE '\([A-Za-z_]+/[A-Za-z_]+\)' | head -1 | tr -d '()')"
  tz="${tz:-America/Buenos_Aires}"

  if [[ -z "$reset_raw" ]]; then
    log "cuota de sesión agotada pero no pude parsear el horario de reset → durmiendo 900s como fallback"
    target_epoch=$(( $(date +%s) + 900 ))
  else
    today_str="$(TZ="$tz" date +%Y-%m-%d)"
    target_epoch="$(TZ="$tz" date -j -f "%Y-%m-%d %I:%M%p" "$today_str $reset_raw" +%s 2>/dev/null || true)"
    if [[ -z "$target_epoch" ]]; then
      log "no pude interpretar '$reset_raw ($tz)' como horario → durmiendo 900s como fallback"
      target_epoch=$(( $(date +%s) + 900 ))
    else
      now_epoch=$(date +%s)
      if [[ "$target_epoch" -le "$now_epoch" ]]; then
        target_epoch=$((target_epoch + 86400))  # el horario ya pasó hoy → es mañana
      fi
      target_epoch=$((target_epoch + 60))  # margen de seguridad
      log "cuota de sesión agotada — reset ~$(TZ="$tz" date -r "$target_epoch" '+%H:%M %Z') ($tz). Durmiendo hasta entonces..."
    fi
  fi

  while :; do
    now_epoch=$(date +%s)
    remaining=$((target_epoch - now_epoch))
    if [[ "$remaining" -le 0 ]]; then
      break
    fi
    if [[ -f "$KILL_SWITCH" ]]; then
      log "kill-switch detectado durante la espera de cuota → cortando"
      return 1
    fi
    chunk=$((remaining < 300 ? remaining : 300))
    sleep "$chunk"
  done
  log "ventana de cuota reseteada, reanudando loop"
  return 0
}

# Estado observable: hash combinado de roadmap.yaml + todos los archivos de épicas
# (checkboxes [x]/[ ] y estado: en-progreso/completo viven ahí). Un cambio de hash
# entre iteraciones = progreso real, verificado por disco, no por autoevaluación.
#
# El roadmap NO tiene por qué vivir dentro del cwd del loop (el cwd suele ser el repo del
# SERVICIO target, ej. active/mercado-cercano/services/ledger-service; el roadmap vive en un
# árbol separado, management/). Buscar solo bajo $ROOT da falsos "sin cambios" — buscar desde
# la raíz del roadmap explícito (--roadmap) cuando está disponible, si no desde $HOME/Projects
# como fallback razonable para este lab, nunca solo bajo $ROOT.
state_hash() {
  local search_root roadmap_files
  if [[ -n "$ROADMAP_GLOB" && -f "$ROADMAP_GLOB" ]]; then
    search_root="$(cd "$(dirname "$ROADMAP_GLOB")/.." && pwd)"
  elif [[ -d "$HOME/Projects" ]]; then
    search_root="$HOME/Projects"
  else
    search_root="$ROOT"
  fi
  roadmap_files=$(find "$search_root" -path "*/management/*roadmap.yaml" -o -path "*/management/*epicas/*.md" 2>/dev/null | sort)
  if [[ -z "$roadmap_files" ]]; then
    echo "no-roadmap-found"
    return
  fi
  # shellcheck disable=SC2086
  cat $roadmap_files 2>/dev/null | shasum -a 256 | awk '{print $1}'
}

if [[ "$DRY_RUN" == true ]]; then
  log "DRY RUN — no se ejecuta la invocación real, solo se valida el driver"
  log "provider=$PROVIDER (dispatcher: $(dispatch_provider)) · fases=$PHASES"
  if [[ "$PROVIDER" == "codex" ]]; then
    log "codex executable: $CODEX_BIN"
    log "codex caveman: $CODEX_CAVEMAN_MODE"
  fi
  if [[ -n "$MODEL" || "$PROVIDER" == "ollama" ]]; then
    log "modelo: override explícito ($(dispatch_model_args | tail -1)) — pisa el frontmatter en todas las fases"
  else
    log "modelo: resuelto por agente desde el frontmatter (agent-dispatcher.py)"
  fi
  # Resolución real de agente→modelo→tamaño de contexto, sin ejecutar el agente.
  if [[ "$PHASES" == "split" ]]; then
    dry_agents=("$SELECT_AGENT" "$FALLBACK_EXEC_AGENT")
    dry_labels=("SELECT" "EXEC (fallback; el real lo designa SELECT)")
  else
    dry_agents=("$SELECT_AGENT")
    dry_labels=("fase única")
  fi
  for i in "${!dry_agents[@]}"; do
    dry_args=(python3 "$SCRIPT_DIR/agent-dispatcher.py" --agent "${dry_agents[$i]}"
              --provider "$(dispatch_provider)" --task "<PROMPT>" --cwd "$ROOT" --dry-run)
    while IFS= read -r a; do [[ -n "$a" ]] && dry_args+=("$a"); done < <(dispatch_model_args)
    [[ -n "$PROYECTO" ]] && dry_args+=(--project "$PROYECTO")
    log "fase ${dry_labels[$i]} → $("${dry_args[@]}" | summarize_dispatch)"
  done
  if [[ -f "$KILL_SWITCH" ]]; then
    log "kill-switch .loop-stop presente → 0 iteraciones"
    exit 0
  fi
  hash_before="$(state_hash)"
  log "hash de estado inicial: $hash_before"
  log "backlog vacío simulado → termina en iteración 1"
  exit 0
fi

iteration=0
invocations=0
no_progress_streak=0
max_turns_streak=0
prev_hash="$(state_hash)"

while true; do
  if [[ -f "$KILL_SWITCH" ]]; then
    log "kill-switch $KILL_SWITCH detectado → deteniendo antes de iteración $((iteration + 1))"
    break
  fi

  if [[ "$MAX_ITERATIONS" -gt 0 && "$invocations" -ge "$MAX_ITERATIONS" ]]; then
    log "máximo de iteraciones ($MAX_ITERATIONS) alcanzado → deteniendo"
    break
  fi

  iteration=$((iteration + 1))
  invocations=$((invocations + 1))

  # El PROYECTO (dentro del roadmap.yaml único) NO se infiere del cwd de forma confiable: si el
  # cwd cae dentro de un proyecto (ej. un servicio de mercado-cercano), el meta-router puede
  # filtrar por proyecto=mercado-cercano en vez del proyecto real que --proyecto pide
  # explícitamente. Pasarlo siempre que se conozca de antemano, no confiar en la inferencia.
  # NO invocar `@meta-router`: ese agente tiene SOLO la tool `Skill` (ver agents/orchestrators/
  # meta-router.md) y por lo tanto no puede leer archivos, correr comandos ni editar la épica —
  # es estructuralmente incapaz de ejecutar la tarea. Observado 2026-07-26: las dos iteraciones
  # reportaron "el agente meta-router no tiene acceso a Bash/Read, así que terminé el ciclo yo
  # mismo"; el trabajo salió bien pero fuera de la skill, y por eso ninguna emitió el marcador
  # terminal `NEXT-TASK:` que §5.4 exige. Se invoca la skill directamente, en un contexto que sí
  # tiene tools.
  # Reset explícito: bash conserva estas variables entre vueltas del while, y una iteración que
  # no despacha EXEC heredaría el output de la anterior en el log de traza.
  select_output=""; exec_output=""; sel_agente=""; sel_epica=""; sel_tarea=""
  sel_ceremony=""; sel_proyecto=""; select_line=""; review_output=""; review_verdict=""; review_skip_reason=""
  # Foto del estado git ANTES de trabajar, para poder atribuirle a esta iteración sólo lo que
  # ensució ella y no lo que ya venía sucio de otras sesiones.
  dirty_before="$(dirty_snapshot)"
  untracked_before="$(untracked_service_dirs)"

  scope_prompt="Roadmap: $ROADMAP_GLOB."
  if [[ -n "$PROYECTO" ]]; then
    scope_prompt="$scope_prompt Proyecto: $PROYECTO."
  fi
  if [[ -n "$EPICA" ]]; then
    scope_prompt="$scope_prompt Épica fijada: $EPICA."
  fi

  if [[ "$PHASES" == "single" ]]; then
    # Escape hatch: una sola invocación hace selección + ejecución + cierre.
    PROMPT="Usá la skill loop-next-task para ejecutar la próxima tarea desbloqueada. $scope_prompt"
    PROMPT="$PROMPT Seguí la skill al pie de la letra, incluido §5.4:"
    PROMPT="$PROMPT terminá SIEMPRE con la línea 'NEXT-TASK: done|empty|blocked <detalle>',"
    PROMPT="$PROMPT incluso si la tarea no cerró."
    log "iteración $iteration — fase única con @$SELECT_AGENT (provider=$PROVIDER, --max-turns $MAX_TURNS)"
    output="$(dispatch_agent "$SELECT_AGENT" "$PROMPT" "$MAX_TURNS")"
    echo "$output"
  else
    # -------------------------------------------------------------------------------------------
    # FASE 1 — SELECT. Elegir la tarea, NO ejecutarla.
    # Corre con @meta-router → haiku por frontmatter: clasificar y rutear es determinístico, no
    # necesita un modelo de razonamiento. Su contexto mínimo es el índice del roadmap + la lista
    # de tareas de la épica; no toca código.
    # -------------------------------------------------------------------------------------------
    PROMPT="Usá la skill loop-next-task en MODO SELECT (fase 1 de 2). $scope_prompt"
    PROMPT="$PROMPT Tu trabajo es ELEGIR la próxima tarea desbloqueada y designar quién la ejecuta."
    PROMPT="$PROMPT NO ejecutes la tarea, NO edites código, NO marqués ningún [x]."
    PROMPT="$PROMPT Terminá con EXACTAMENTE UNA de estas dos líneas, como última línea del output:"
    PROMPT="$PROMPT 'LOOP-SELECT: proyecto=<p> epica=<KEY-ENN> tarea=<id> ceremony=<L1|L2|L3|L4> agente=<agente-canonico>'"
    PROMPT="$PROMPT o bien 'NEXT-TASK: empty|blocked <detalle>' si no hay tarea ejecutable."
    log "iteración $iteration — fase SELECT con @$SELECT_AGENT (provider=$PROVIDER, --max-turns $SELECT_MAX_TURNS)"
    select_output="$(dispatch_agent "$SELECT_AGENT" "$PROMPT" "$SELECT_MAX_TURNS")"
    echo "$select_output"
    output="$select_output"

    # Una terminal en SELECT (empty/blocked/cuota/créditos) baja sin gastar la fase EXEC: los
    # chequeos de abajo la ven en $output y cortan igual que siempre.
    if ! echo "$select_output" | grep -qE "NEXT-TASK: (empty|blocked)" \
       && ! is_quota_block "$select_output" && ! is_credits_exhausted "$select_output" \
       && ! is_spend_limit "$select_output"; then
      select_line="$(echo "$select_output" | grep -oE "LOOP-SELECT:[^\\\\\"]*" | tail -1 || true)"
      if [[ -z "$select_line" ]]; then
        # Sin LOOP-SELECT y sin marcador terminal: SELECT murió a mitad. NO se despacha EXEC —
        # ejecutar sin saber qué tarea se eligió es exactamente el modo de fallo que el loop
        # viene tratando de eliminar. Cae como terminación anormal en la clasificación de abajo.
        log "⚠ fase SELECT no emitió LOOP-SELECT ni marcador terminal → no se despacha EXEC"
      else
        sel_epica="$(echo "$select_line" | grep -oE 'epica=[^ ]+' | cut -d= -f2 || true)"
        sel_tarea="$(echo "$select_line" | grep -oE 'tarea=[^ ]+' | cut -d= -f2 || true)"
        sel_ceremony="$(echo "$select_line" | grep -oE 'ceremony=[^ ]+' | cut -d= -f2 || true)"
        sel_proyecto="$(echo "$select_line" | grep -oE 'proyecto=[^ ]+' | cut -d= -f2 || true)"
        sel_agente="$(echo "$select_line" | grep -oE 'agente=[^ ]+' | cut -d= -f2 || true)"
        # Un agente designado que no existe haría fallar el dispatcher con "Agente no encontrado"
        # y quemaría la iteración entera. Se valida antes y se cae al fallback avisando.
        if [[ -z "$sel_agente" ]] || ! grep -rqE "^name:[[:space:]]*$sel_agente[[:space:]]*$" "$LAB_ROOT/management/agents" 2>/dev/null; then
          log "⚠ agente designado por SELECT inválido o ausente ('${sel_agente:-<vacío>}') → usando $FALLBACK_EXEC_AGENT"
          sel_agente="$FALLBACK_EXEC_AGENT"
        fi

        # ---------------------------------------------------------------------------------------
        # FASE 2 — EXEC. Ejecutar SÓLO la tarea que SELECT eligió.
        # Corre con el agente designado → su modelo sale del frontmatter (sonnet para
        # implementación, opus para L4/arquitectura). Su contexto mínimo es la tarea + el archivo
        # de la épica + el PROJECT.md del proyecto dueño del código.
        # ---------------------------------------------------------------------------------------
        PROMPT="Usá la skill loop-next-task en MODO EXEC (fase 2 de 2). $scope_prompt"
        PROMPT="$PROMPT La tarea YA fue elegida por la fase SELECT — no elijas otra:"
        PROMPT="$PROMPT proyecto=$sel_proyecto epica=$sel_epica tarea=$sel_tarea ceremony=$sel_ceremony."
        PROMPT="$PROMPT Ejecutala de punta a punta siguiendo §2 a §5 de la skill: verificá el"
        PROMPT="$PROMPT criterio 'Hecho cuando', respetá §3bis (no cerrar con evidencia que una"
        PROMPT="$PROMPT tarea anterior declaró insuficiente), marcá [x], actualizá roadmap.yaml y"
        PROMPT="$PROMPT guardá el handoff con mem_save. Una sola tarea, no encadenes la siguiente."
        PROMPT="$PROMPT Terminá SIEMPRE con la línea 'NEXT-TASK: done|checkpoint|blocked <detalle>',"
        PROMPT="$PROMPT incluso si la tarea no cerró."
        log "iteración $iteration — fase EXEC de $sel_epica.$sel_tarea ($sel_ceremony) con @$sel_agente (--max-turns $MAX_TURNS)"
        exec_output="$(dispatch_agent "$sel_agente" "$PROMPT" "$MAX_TURNS")"
        echo "$exec_output"
        # El marcador terminal que el runner evalúa es SIEMPRE el de la fase que ejecutó.
        output="$exec_output"

        # -----------------------------------------------------------------------------------
        # FASE 3 — REVIEW (sólo L4). Condicional, read-only, con @dev-security (opus).
        #
        # RULE-10 exige @dev-security en el diseño L4, pero hasta ahora eso dependía de que el
        # agente ejecutor se acordara de invocarlo. Cableado acá, es estructural: si el ceremony
        # es L4, la revisión ocurre — sobre el plan recién escrito o sobre el diff implementado,
        # que es lo que el propio agente distingue al leer el estado.
        #
        # No corre si EXEC salió `blocked`: no hay nada que revisar todavía.
        # -----------------------------------------------------------------------------------
        # El gate de commit revisa lo que EXEC dejó — así que sólo tiene sentido si EXEC TERMINÓ.
        #
        # Antes la condición sólo excluía `blocked`, y una muerte por `--max-turns` disparaba la
        # revisión igual. Observado en PLAT-E39.T1 (2026-07-27): EXEC agotó los 40 turnos sin
        # crear nada, y @dev-security gastó una invocación opus para ir a disco, verificar que
        # `catalog-service` no existía y reportar el false-dispatch. Tenía razón — y el prompt le
        # había afirmado como premisa que la tarea "se acababa de ejecutar".
        #
        # Nunca afirmarle a un agente que algo existe sin haberlo verificado: la revisión buena
        # cuesta una invocación cara, y la mala fabrica un veredicto sobre nada.
        review_skip_reason=""
        if is_max_turns "$exec_output"; then
          review_skip_reason="EXEC agotó el presupuesto de $MAX_TURNS turnos sin cerrar la tarea"
        elif ! has_terminal_marker "$exec_output"; then
          review_skip_reason="EXEC terminó sin marcador NEXT-TASK"
        elif echo "$exec_output" | grep -q "NEXT-TASK: blocked"; then
          review_skip_reason="EXEC reportó blocked"
        fi

        if [[ "$sel_ceremony" == "L4" && -n "$SECURITY_AGENT" && -n "$review_skip_reason" ]]; then
          log "  gate de commit OMITIDO: $review_skip_reason → no hay nada que revisar"
        fi

        if [[ "$sel_ceremony" == "L4" && -n "$SECURITY_AGENT" && -z "$review_skip_reason" ]]; then
          if run_l4_gate "$sel_epica" "$sel_tarea" \
               "Lo acaba de ejecutar @$sel_agente en esta misma iteración. Revisá el DIFF sin commitear." \
               "commit"; then
            log "✓ gate L4 aprobado — la próxima iteración puede avanzar"
          else
            log "gate L4 no superado → deteniendo"
            write_iter_log
            break
          fi
        fi
      fi
    fi
  fi

  # Créditos agotados: TERMINAL. A diferencia del session-limit no hay reset horario que esperar →
  # cortar limpio, sin dormir y sin sumar a la racha de no-progreso (que cortaría igual pero con un
  # mensaje engañoso de "sin cambios"). El owner recarga con /usage-credits o cambia de modelo con
  # /model y relanza el loop. Se chequea ANTES que is_quota_block (mensajes mutuamente excluyentes).
  # Traza de auditoría: sin esto, la salida de cada iteración se pierde si nadie mira la consola,
  # y no hay forma de reconstruir por qué una tarea quedó como quedó.
  write_iter_log

  if is_spend_limit "$output"; then
    log "tope de gasto alcanzado (no hay reset horario que esperar) → deteniendo. Subilo en claude.ai/settings/usage y relanzá el loop."
    break
  fi

  if is_credits_exhausted "$output"; then
    log "créditos de uso agotados (sin reset horario) → deteniendo. Recargá con /usage-credits o cambiá de modelo con /model, y relanzá el loop."
    break
  fi

  if is_quota_block "$output"; then
    iteration=$((iteration - 1))
    invocations=$((invocations - 1))
    if ! wait_for_quota_reset "$output"; then
      break
    fi
    continue
  fi

  if echo "$output" | grep -q "NEXT-TASK: empty"; then
    if [[ -n "$EPICA" ]]; then
      log "épica $EPICA sin tareas ejecutables (completa) → deteniendo"
    else
      log "backlog vacío reportado por la skill → deteniendo"
    fi
    break
  fi

  # Gate L4 pendiente de una iteración ANTERIOR: SELECT reporta blocked porque el plan ya está
  # escrito y espera revisión + sign-off. Ese bloqueo SÍ se puede levantar acá — es precisamente
  # para lo que existe la fase REVIEW. Sin esto, el loop cortaba y la revisión nunca se disparaba
  # (deadlock observado en PLAT-E39, 2026-07-27).
  if is_l4_gate_block "$output" && [[ -n "$SECURITY_AGENT" ]]; then
    gate_epica="${sel_epica:-${EPICA:-$(echo "$output" | grep -oE '[A-Z]{2,4}-E[0-9]+' | head -1)}}"
    # Un gate por épica y por corrida. Si tras aprobarlo la épica vuelve a reportarse frenada por
    # lo mismo, el registro del sign-off no surtió efecto: reintentar la revisión sería un bucle
    # infinito quemando cupo sobre un archivo que nadie está actualizando.
    if [[ " ${gates_run:-} " == *" $gate_epica "* ]]; then
      log "épica $gate_epica sigue reportando gate L4 pendiente DESPUÉS de aprobarlo → deteniendo"
      log "  El sign-off está en management/escalations/, pero el archivo de la épica no quedó"
      log "  actualizado. Revisalo a mano antes de reanudar."
      break
    fi
    gates_run="${gates_run:-} $gate_epica"
    log "iteración $iteration — épica $gate_epica frenada por gate L4 pendiente → corriendo la revisión que lo destraba"
    if run_l4_gate "${gate_epica:-desconocida}" "GATE" \
         "El plan/trabajo ya existe de una iteración anterior y está esperando este gate." \
         "plan"; then
      log "✓ gate L4 aprobado y registrado — reanudando el loop"
      prev_hash="$(state_hash)"
      no_progress_streak=0
      continue
    fi
    log "gate L4 no superado → deteniendo"
    write_iter_log
    break
  fi

  # Con épica fijada, blocked es terminal: reiterar no puede desbloquearla (la dependencia
  # o el checkpoint que la frena requiere acción del owner, no otra pasada del loop).
  if [[ -n "$EPICA" ]] && echo "$output" | grep -q "NEXT-TASK: blocked"; then
    log "épica $EPICA bloqueada (ver handoff en Engram) → deteniendo"
    break
  fi

  # Mismo criterio para el checkpoint que espera a una persona. Sin esto el loop gasta una
  # iteración completa para redescubrir que sigue frenado: en PLAT-E39, tras el checkpoint
  # `plan-authored-pending-review` de la iteración 1, la iteración 2 volvió a leer la épica
  # entera sólo para reportar el mismo bloqueo.
  if [[ -n "$EPICA" ]] && checkpoint_needs_owner "$output"; then
    log "épica $EPICA en checkpoint que requiere sign-off del owner → deteniendo"
    log "  (plan L4 recién escrito o escalación sin verificar — lo destraba una persona, no otra iteración)"
    break
  fi

  # ---------------------------------------------------------------------------------------------
  # Clasificación de la terminación ANTES de mirar el disco.
  #
  # El bug que esto arregla: el loop sólo comparaba el hash de estado. Si el agente moría por
  # turnos habiendo alcanzado a escribir algo, el hash cambiaba y se registraba "progreso
  # detectado" — reseteando la racha de no-progreso y dejando que el loop siguiera sobre una
  # tarea a medio hacer. Un cambio en disco NO es evidencia de que la tarea se completó; el
  # marcador `NEXT-TASK: done` sí.
  # ---------------------------------------------------------------------------------------------
  abnormal=0
  abnormal_reason=""
  if is_max_turns "$output"; then
    abnormal=1
    abnormal_reason="agotó el presupuesto de $MAX_TURNS turnos sin cerrar la tarea"
  elif ! has_terminal_marker "$output"; then
    abnormal=1
    abnormal_reason="terminó sin marcador NEXT-TASK (crash, error del CLI o salida truncada)"
  fi

  new_hash="$(state_hash)"

  if [[ "$abnormal" -eq 1 ]]; then
    abnormal_streak=$(( ${abnormal_streak:-0} + 1 ))
    log "⚠ TERMINACIÓN ANORMAL: $abnormal_reason (racha anormal: $abnormal_streak/$ABNORMAL_THRESHOLD)"
    if [[ "$new_hash" != "$prev_hash" ]]; then
      log "⚠ hubo cambios en disco SIN marcador de cierre → hay trabajo a medias que la próxima"
      log "  iteración va a heredar sin saberlo. Revisá antes de reanudar."
      dirty="$(dirty_repos_since "$dirty_before")"
      untracked_now="$(untracked_service_dirs)"
      if [[ -n "$dirty" ]]; then
        log "  repos que ensució ESTA iteración: $dirty"
      fi
      # Un servicio recién scaffoldeado no aparece en ningún `git status`: se informa aparte.
      if [[ "$untracked_now" != "${untracked_before:-}" ]]; then
        log "  ⚠ servicios SIN repo git (scaffold a medias, invisible a git): $untracked_now"
        log "    Revisá antes de reanudar: la próxima iteración los hereda sin saber qué falta."
      fi
      if [[ -z "$dirty" && "$untracked_now" == "${untracked_before:-}" ]]; then
        log "  ningún repo cambió en esta iteración (el cambio de hash vino del roadmap/épicas)"
      fi
    fi
    # Una terminación anormal NUNCA cuenta como progreso, haya escrito o no.
    no_progress_streak=$((no_progress_streak + 1))

    # La muerte por turnos corta con su propio umbral: reintentarla es determinísticamente inútil.
    if is_max_turns "$output"; then
      max_turns_streak=$(( ${max_turns_streak:-0} + 1 ))
      if [[ "$max_turns_streak" -ge "$MAX_TURNS_THRESHOLD" ]]; then
        log "la tarea NO entra en $MAX_TURNS turnos → deteniendo sin reintentar."
        log "  Reintentar con el mismo presupuesto vuelve a agotarlo: el fallo es determinístico,"
        log "  no transitorio. Dos salidas:"
        log "    · subir el presupuesto:  --max-turns $((MAX_TURNS * 2))"
        log "    · trocear la tarea en la épica (skills/dev/atomic-session-planning)"
        log "  Si la tarea mezcla varias cosas con criterios de aceptación distintos, trocear es"
        log "  lo correcto — más presupuesto sólo compra un fallo más caro."
        log "  Traza: $ITER_LOG_DIR"
        prev_hash="$new_hash"
        write_iter_log
        break
      fi
    else
      max_turns_streak=0
    fi

    if [[ "$abnormal_streak" -ge "$ABNORMAL_THRESHOLD" ]]; then
      log "$ABNORMAL_THRESHOLD terminaciones anormales consecutivas → deteniendo."
      log "  Causa probable: crash del CLI o salida truncada. Revisá $ITER_LOG_DIR."
      prev_hash="$new_hash"
      break
    fi
    if [[ "$no_progress_streak" -ge "$NO_PROGRESS_THRESHOLD" ]]; then
      log "$NO_PROGRESS_THRESHOLD iteraciones consecutivas sin progreso → deteniendo"
      prev_hash="$new_hash"
      break
    fi
    prev_hash="$new_hash"
    continue
  fi

  abnormal_streak=0

  if [[ "$new_hash" == "$prev_hash" ]]; then
    no_progress_streak=$((no_progress_streak + 1))
    log "cerró limpio pero sin cambios en roadmap/épicas (racha: $no_progress_streak/$NO_PROGRESS_THRESHOLD)"
    if [[ "$no_progress_streak" -ge "$NO_PROGRESS_THRESHOLD" ]]; then
      log "$NO_PROGRESS_THRESHOLD iteraciones consecutivas sin progreso → deteniendo"
      break
    fi
  else
    no_progress_streak=0
    log "progreso confirmado (marcador NEXT-TASK + cambio de estado)"
  fi
  prev_hash="$new_hash"
done

log "loop finalizado tras $invocations invocación(es)"

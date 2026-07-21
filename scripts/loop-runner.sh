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
#                            [--provider anthropic|ollama] [--model <alias>] [--ollama-model <id>]
#                            [--max-iterations N] [--dry-run]
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
# --provider (opcional, default anthropic) elige el backing del loop SIN perder el modo original:
#   - anthropic (default): invoca `claude -p ...` contra el backend Anthropic nativo — comportamiento
#     histórico, intacto.
#   - ollama: invoca `ollama launch claude --model <OLLAMA_MODEL> -- -p ...`, que lanza Claude Code
#     apuntando al endpoint de Ollama con un modelo abierto (default kimi-k2.7-code:cloud). No consume
#     cupo Anthropic. --ollama-model overridea el modelo (ej. kimi-k2.6:cloud). Impacto de calidad/
#     ceremonia del backing global kimi (artefactos 'reforzado', L4 nunca auto-aprueba): ver la skill
#     provider-selector, sección "Excepción — fallback kimi".
#     NOTA: la espera por cuota (wait_for_quota_reset) es específica del bloqueo de Anthropic; bajo
#     ollama no aplica y un rate-limit de kimi-cloud hoy se contaría como no-progreso. Manejo dedicado
#     pendiente hasta tener un ejemplo del formato de error que devuelve kimi-cloud.
#
# --model (opcional, solo provider anthropic) fija el modelo del `claude -p` de cada iteración —
#   alias `opus`/`sonnet`/`haiku`/`fable` o nombre completo (`claude-sonnet-5`). SIN --model
#   (default) corre con el modelo de la config, comportamiento histórico intacto. Útil para correr
#   el loop en un modelo/pool distinto (ej. cuando el default se quedó "out of usage credits").
#   Para el provider ollama el modelo lo fija --ollama-model, no --model.
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
PROVIDER="anthropic"                  # backing del loop: anthropic (default) | ollama
MODEL=""                              # --model del CLI (solo anthropic): vacío = modelo default de la config
OLLAMA_MODEL="kimi-k2.7-code:cloud"   # modelo cuando --provider ollama (--ollama-model lo overridea)
MAX_ITERATIONS=0   # 0 = sin límite duro; el freno real es no_progress_threshold
MAX_TURNS=40
NO_PROGRESS_THRESHOLD=2
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
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

# --provider solo acepta anthropic|ollama; y si es ollama, el binario debe existir antes de iterar.
case "$PROVIDER" in
  anthropic|ollama) ;;
  *) echo "Provider desconocido: '$PROVIDER' (usar anthropic|ollama)" >&2; exit 1 ;;
esac
if [[ "$PROVIDER" == "ollama" ]] && ! command -v ollama >/dev/null 2>&1; then
  echo "--provider ollama pero 'ollama' no está en el PATH" >&2; exit 1
fi

log() { printf '[loop-runner] %s\n' "$1"; }

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
  if [[ "$PROVIDER" == "ollama" ]]; then
    log "provider=ollama — invocaría: ollama launch claude --model $OLLAMA_MODEL -- -p <PROMPT> --max-turns $MAX_TURNS --dangerously-skip-permissions"
  else
    log "provider=anthropic — invocaría: claude -p <PROMPT>${MODEL:+ --model $MODEL} --max-turns $MAX_TURNS --dangerously-skip-permissions"
  fi
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
  PROMPT="@meta-router next-task --roadmap $ROADMAP_GLOB"
  if [[ -n "$PROYECTO" ]]; then
    PROMPT="$PROMPT --proyecto $PROYECTO"
  fi
  if [[ -n "$EPICA" ]]; then
    PROMPT="$PROMPT --epica $EPICA"
  fi
  log "iteración $iteration — invocando '$PROMPT' (provider=$PROVIDER, contexto fresco, --max-turns $MAX_TURNS)"

  # Misma tarea, distinto backing. anthropic = comportamiento histórico (claude -p directo).
  # ollama = Claude Code lanzado por `ollama launch` apuntando al endpoint de Ollama; el `-p` viaja
  # como arg extra tras `--`, así que corre igual de headless y su stdout se captura igual.
  if [[ "$PROVIDER" == "ollama" ]]; then
    output="$(ollama launch claude --model "$OLLAMA_MODEL" -- -p "$PROMPT" --max-turns "$MAX_TURNS" --dangerously-skip-permissions 2>&1 || true)"
  elif [[ -n "$MODEL" ]]; then
    # --model fijado: comportamiento anthropic con modelo explícito (rama aparte para no romper
    # en bash 3.2 con set -u, donde un array vacío interpolado tira "unbound variable").
    output="$(claude -p "$PROMPT" --model "$MODEL" --max-turns "$MAX_TURNS" --dangerously-skip-permissions 2>&1 || true)"
  else
    output="$(claude -p "$PROMPT" --max-turns "$MAX_TURNS" --dangerously-skip-permissions 2>&1 || true)"
  fi
  echo "$output"

  # Créditos agotados: TERMINAL. A diferencia del session-limit no hay reset horario que esperar →
  # cortar limpio, sin dormir y sin sumar a la racha de no-progreso (que cortaría igual pero con un
  # mensaje engañoso de "sin cambios"). El owner recarga con /usage-credits o cambia de modelo con
  # /model y relanza el loop. Se chequea ANTES que is_quota_block (mensajes mutuamente excluyentes).
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

  # Con épica fijada, blocked es terminal: reiterar no puede desbloquearla (la dependencia
  # o el checkpoint que la frena requiere acción del owner, no otra pasada del loop).
  if [[ -n "$EPICA" ]] && echo "$output" | grep -q "NEXT-TASK: blocked"; then
    log "épica $EPICA bloqueada (ver handoff en Engram) → deteniendo"
    break
  fi

  new_hash="$(state_hash)"
  if [[ "$new_hash" == "$prev_hash" ]]; then
    no_progress_streak=$((no_progress_streak + 1))
    log "sin cambios en roadmap/épicas esta iteración (racha: $no_progress_streak/$NO_PROGRESS_THRESHOLD)"
    if [[ "$no_progress_streak" -ge "$NO_PROGRESS_THRESHOLD" ]]; then
      log "$NO_PROGRESS_THRESHOLD iteraciones consecutivas sin progreso → deteniendo"
      break
    fi
  else
    no_progress_streak=0
    log "progreso detectado (hash de estado cambió)"
  fi
  prev_hash="$new_hash"
done

log "loop finalizado tras $invocations invocación(es)"

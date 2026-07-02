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
#   ./scripts/loop-runner.sh [--proyecto <nombre>] [--roadmap path/a/roadmap.yaml]
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
# Permisos: corre con --dangerously-skip-permissions (override del owner, 2026-07-02 —
# supersede la mitigación original de PROP-008 de nunca usarlo sobre $HOME). Riesgo
# asumido explícitamente por el owner. El kill-switch (.loop-stop) es el freno manual
# principal; el guardrail L4-nunca-commitea-sin-sign-off sigue vigente e independiente.

set -euo pipefail

ROOT="$(pwd)"
ROADMAP_GLOB="${DEVY_ROADMAP_PATH:-$HOME/Projects/management/roadmap.yaml}"
PROYECTO=""        # vacío = dejar que @meta-router infiera el proyecto del cwd (ver --proyecto)
MAX_ITERATIONS=0   # 0 = sin límite duro; el freno real es no_progress_threshold
MAX_TURNS=40
NO_PROGRESS_THRESHOLD=2
KILL_SWITCH="$ROOT/.loop-stop"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --roadmap) ROADMAP_GLOB="$2"; shift 2 ;;
    --proyecto) PROYECTO="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

log() { printf '[loop-runner] %s\n' "$1"; }

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
  log "DRY RUN — no se ejecuta claude -p, solo se valida el driver"
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
  log "iteración $iteration — invocando '$PROMPT' (contexto fresco, --max-turns $MAX_TURNS)"

  output="$(claude -p "$PROMPT" --max-turns "$MAX_TURNS" --dangerously-skip-permissions 2>&1 || true)"
  echo "$output"

  if echo "$output" | grep -q "NEXT-TASK: empty"; then
    log "backlog vacío reportado por la skill → deteniendo"
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

#!/usr/bin/env bash
# harness-drift.sh — reporta divergencia entre la FUENTE del harness y su instalación.
#
# EL PROBLEMA QUE RESUELVE (2026-07-27)
#
# Hay tres copias de los agentes/skills, y es por diseño:
#   1. active/team-ai-harness/{agents,skills,config,rules}  ← FUENTE canónica (ADR-001)
#   2. management/{agents,skills,config,rules}              ← INSTALACIÓN (install-management.sh)
#   3. .claude/{agents,skills}                              ← GENERADO (sync-agents.sh, desde 2)
#
# El sync de 1→2 existe: `install-management.sh <target> --upgrade`. Pero su guard aborta si la
# instalación tiene cambios sin commitear en las rutas que va a sobrescribir — correcto, porque
# `--upgrade` pisa y git no lo recupera. En la práctica siempre hay algo sin commitear de alguna
# sesión, así que el upgrade nunca corre y la instalación queda atrás EN SILENCIO.
#
# Ese silencio es el bug real. Cuando se detectó (2026-07-27), `management/agents` estaba 5
# archivos atrás de la fuente, y `.claude/` — que es lo que el loop realmente ejecuta — se genera
# desde la instalación, no desde la fuente. O sea: el loop venía corriendo con agentes viejos.
# Mismo modo de fallo que el del 2026-07-26, cuando el loop corrió con la copia vieja de `.claude/`.
#
# Este script sólo LEE. Corre aunque ambos lados estén sucios, que es justamente cuando el
# `--upgrade` no puede correr y cuando más falta hace saber que hay drift.
#
# Uso:
#   ./scripts/harness-drift.sh          # reporta; exit 1 si hay drift
#   ./scripts/harness-drift.sh --quiet  # sólo el veredicto

set -euo pipefail

LAB_ROOT="${DEVY_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SOURCE="$LAB_ROOT/active/team-ai-harness"
INSTALL="$LAB_ROOT/management"
GENERATED="$LAB_ROOT/.claude"
QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

say() { [[ "$QUIET" == true ]] || printf '%s\n' "$1"; }

[[ -d "$SOURCE/agents" ]] || { echo "No encuentro la fuente: $SOURCE/agents" >&2; exit 2; }

drift_total=0

# --- 1. FUENTE vs INSTALACIÓN -------------------------------------------------------------
say "━━━ fuente (team-ai-harness) → instalación (management) ━━━"
for dir in agents skills config rules; do
  [[ -d "$SOURCE/$dir" && -d "$INSTALL/$dir" ]] || continue
  # --exclude de ruido que no forma parte del contrato del harness.
  diff_out="$(diff -rq --exclude='.DS_Store' --exclude='__pycache__' --exclude='*.pyc' \
    "$SOURCE/$dir" "$INSTALL/$dir" 2>/dev/null || true)"

  # Tres resultados distintos, y sólo dos son drift:
  #   "Files X and Y differ"  → DRIFT: la instalación quedó atrás (o adelante) de la fuente.
  #   "Only in <fuente>"      → DRIFT: algo de la fuente nunca se instaló.
  #   "Only in <instalación>" → NO es drift: contenido local de esta instancia del harness
  #                             (ej. rules/naming-conventions.md, propio del lab y no del
  #                             producto). Marcarlo como problema haría que el reporte se
  #                             llene de ruido y se termine ignorando.
  differ="$(printf '%s' "$diff_out" | grep '^Files .* differ$' || true)"
  missing="$(printf '%s' "$diff_out" | grep "^Only in $SOURCE" || true)"
  local_only="$(printf '%s' "$diff_out" | grep "^Only in $INSTALL" || true)"

  n_differ="$(printf '%s' "$differ" | grep -c . || true)"
  n_missing="$(printf '%s' "$missing" | grep -c . || true)"
  n_local="$(printf '%s' "$local_only" | grep -c . || true)"

  if [[ "$n_differ" -eq 0 && "$n_missing" -eq 0 ]]; then
    say "  ✓ $dir/$([[ "$n_local" -gt 0 ]] && echo " ($n_local archivo(s) sólo locales, ok)")"
  else
    drift_total=$((drift_total + n_differ + n_missing))
    say "  ✗ $dir/ — $((n_differ + n_missing)) divergencia(s):"
    [[ "$n_differ" -gt 0 ]] && say "$(printf '%s' "$differ" \
      | sed "s|Files $SOURCE/||; s| and $INSTALL/| ≠ |; s| differ$||; s|^|      distinto: |")"
    [[ "$n_missing" -gt 0 ]] && say "$(printf '%s' "$missing" \
      | sed "s|Only in $SOURCE/*|      sin instalar: |")"
    [[ "$n_local" -gt 0 ]] && say "$(printf '%s' "$local_only" \
      | sed "s|Only in $INSTALL/*|      (sólo local, ok): |")"
  fi
done

# --- 2. INSTALACIÓN vs GENERADO -----------------------------------------------------------
# `.claude/` es lo que el runtime ejecuta de verdad. Que esté al día importa más que el resto:
# un `.claude/` viejo hace que el loop corra con reglas que ya nadie cree vigentes.
say ""
say "━━━ instalación (management) → generado (.claude) ━━━"
stale=0
if [[ -d "$GENERATED/skills" ]]; then
  while IFS= read -r skill; do
    name="$(basename "$(dirname "$skill")")"
    target="$GENERATED/skills/$name/SKILL.md"
    if [[ -f "$target" ]] && ! diff -q "$skill" "$target" >/dev/null 2>&1; then
      stale=$((stale + 1))
      say "  ✗ skills/$name — .claude está desactualizado"
    fi
  done < <(find "$INSTALL/skills" -name SKILL.md 2>/dev/null)
fi
if [[ "$stale" -eq 0 ]]; then
  say "  ✓ skills sincronizadas"
else
  drift_total=$((drift_total + stale))
  say "  → correr: ./management/scripts/sync-agents.sh"
fi

# --- Veredicto ----------------------------------------------------------------------------
say ""
if [[ "$drift_total" -eq 0 ]]; then
  echo "harness-drift: OK — las tres copias coinciden."
  exit 0
fi
echo "harness-drift: $drift_total divergencia(s)."
say ""
say "Para cerrar fuente→instalación hace falta que AMBOS lados estén limpios en"
say "agents/skills/config/rules (el guard de install-management.sh --upgrade pisa sin"
say "posibilidad de recuperar). Commiteá lo pendiente de cada lado y después:"
say "  active/team-ai-harness/scripts/install-management.sh \"$LAB_ROOT\" --upgrade"
say "  ./management/scripts/sync-agents.sh"
exit 1

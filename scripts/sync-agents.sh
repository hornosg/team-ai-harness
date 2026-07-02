#!/usr/bin/env bash
# sync-agents.sh
# Genera archivos para Claude Code (.claude/agents/). OpenCode desactivado (ADR-001, 2026-07-02).
# a partir de los archivos canónicos en agents/
# Soporta múltiples providers: claude (Anthropic), codex (OpenAI), ollama (Ollama Cloud)
#
# Formato del campo model en archivos canónicos:
#   claude-*              → Anthropic  (sin prefijo, retrocompatible)
#   codex/<model-id>      → OpenAI Codex
#   ollama/<model-id>     → Ollama Cloud
#
# Fallbacks Claude Code (solo soporta Anthropic):
#   codex/* → claude-sonnet-5        (tareas de código)
#   ollama/* → claude-haiku-4-5-20251001 (ruteo/clasificación)
#
# Uso: ./scripts/sync-agents.sh [--dry-run]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANONICAL_DIR="$ROOT/agents"
CLAUDE_DIR="$ROOT/.claude/agents"
OPENCODE_DIR="$ROOT/.opencode/agents"
SKILLS_SRC="$ROOT/skills"
CLAUDE_SKILLS_DIR="$ROOT/.claude/skills"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[DRY RUN] No se escribirán archivos"
fi

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

generated=0
count_claude=0
count_codex=0
count_ollama=0
fallback_log=()

# Extrae un valor del frontmatter YAML (entre los delimitadores ---)
extract_frontmatter() {
  local file="$1" key="$2"
  awk '/^---/{c++; next} c==1 && /^'"$key"':/{gsub(/^'"$key"':[[:space:]]*/, ""); gsub(/^"/, ""); gsub(/"$/, ""); print; exit}' "$file"
}

# Extrae el body (todo lo que está después del segundo ---)
extract_body() {
  local file="$1"
  awk '/^---/{c++; next} c>=2' "$file"
}

# Extrae los ítems de la lista YAML `skills:` del frontmatter (uno por línea)
extract_skills_list() {
  awk '
    /^---/{c++; next}
    c==1 && /^skills:[[:space:]]*$/{ins=1; next}
    c==1 && ins && /^[[:space:]]*-[[:space:]]/{sub(/^[[:space:]]*-[[:space:]]*/,""); print; next}
    c==1 && ins && /^[^[:space:]-]/{ins=0}
  ' "$1"
}

# Resuelve, valida e instala las skills de un agente en .claude/skills/.
# Setea las globales: INSTALLED_SLUGS (array) y SKILLS_INJECT (bloque markdown).
resolve_and_install_skills() {
  local canonical_file="$1" agent_name="$2"
  INSTALLED_SLUGS=()
  SKILLS_INJECT=""
  local list slug ref src
  list="$(extract_skills_list "$canonical_file")"
  [[ -z "$list" ]] && return 0
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    slug="${ref##*/}"
    src=""
    if [[ -d "$SKILLS_SRC/$ref" ]]; then src="$SKILLS_SRC/$ref"
    elif [[ -d "$SKILLS_SRC/$slug" ]]; then src="$SKILLS_SRC/$slug"; fi
    if [[ -z "$src" || ! -f "$src/SKILL.md" ]]; then
      echo -e "  ${YELLOW}⚠ skill no encontrada:${NC} '$ref' (referenciada por $agent_name)"
      continue
    fi
    if [[ "$DRY_RUN" == false ]]; then
      mkdir -p "$CLAUDE_SKILLS_DIR/$slug"
      cp -R "$src/." "$CLAUDE_SKILLS_DIR/$slug/"
    fi
    INSTALLED_SLUGS+=("$slug")
  done <<< "$list"

  if [[ ${#INSTALLED_SLUGS[@]} -gt 0 ]]; then
    SKILLS_INJECT=$'\n\n## Skills habilitadas (auto-generado por sync — no editar a mano)\n\nInvocá estas skills con la tool `Skill`. Preferí estas para tu rol:\n'
    for slug in "${INSTALLED_SLUGS[@]}"; do
      SKILLS_INJECT+="- \`${slug}\`"$'\n'
    done
  fi
}

# Garantiza que `Skill` esté en la lista tools `[...]`
ensure_skill_tool() {
  local tools="$1"
  if [[ "$tools" == *Skill* ]]; then echo "$tools"; return; fi
  if [[ "$tools" == "[]" || -z "$tools" ]]; then echo "[Skill]"; return; fi
  echo "${tools%]}, Skill]"
}

# Detecta el provider a partir del campo model
#   claude-*  → claude
#   codex/*   → codex
#   ollama/*  → ollama
#   openai/*  → openai  (alias de codex)
parse_provider() {
  local model="$1"
  case "$model" in
    codex/*)  echo "codex"  ;;
    ollama/*) echo "ollama" ;;
    openai/*) echo "openai" ;;
    *)        echo "claude" ;;
  esac
}

# Extrae el model_id sin el prefijo provider/
parse_model_id() {
  local model="$1"
  if [[ "$model" == */* ]]; then
    echo "${model#*/}"
  else
    echo "$model"
  fi
}

# Modelo efectivo para Claude Code (solo acepta modelos Anthropic)
# Fallback por tipo de tarea inferido del provider original:
#   codex/openai → sonnet  (generación de código)
#   ollama       → haiku   (clasificación / ruteo)
claude_code_model() {
  local provider="$1" model_id="$2"
  case "$provider" in
    claude)        echo "$model_id" ;;
    codex|openai)  echo "claude-sonnet-5" ;;
    ollama)        echo "claude-haiku-4-5-20251001" ;;
    *)             echo "claude-sonnet-5" ;;
  esac
}

# Modelo efectivo para OpenCode (multi-provider)
#   claude → sin prefijo
#   codex  → openai/<model-id>
#   ollama → ollama/<model-id>
opencode_model() {
  local provider="$1" model_id="$2"
  case "$provider" in
    claude)        echo "$model_id" ;;
    codex|openai)  echo "openai/$model_id" ;;
    ollama)        echo "ollama/$model_id" ;;
    *)             echo "$model_id" ;;
  esac
}

# Valida que el model_id sea conocido para su provider; emite ⚠ si no
validate_model() {
  local provider="$1" model_id="$2" agent_name="$3"
  case "$provider" in
    claude)
      case "$model_id" in
        claude-opus-4-8|claude-sonnet-5|claude-haiku-4-5-20251001) return 0 ;;
        *) echo -e "  ${YELLOW}⚠ Modelo claude no reconocido:${NC} '$model_id' en $agent_name" ;;
      esac ;;
    codex|openai)
      case "$model_id" in
        codex-5.5|gpt-4o|gpt-4.1|o3|o3-mini) return 0 ;;
        *) echo -e "  ${YELLOW}⚠ Modelo codex/openai no reconocido:${NC} '$model_id' en $agent_name" ;;
      esac ;;
    ollama)
      case "$model_id" in
        llama3.1|qwen2.5-coder|deepseek-coder-v2|codestral) return 0 ;;
        *) echo -e "  ${YELLOW}⚠ Modelo ollama no reconocido:${NC} '$model_id' en $agent_name" ;;
      esac ;;
  esac
}

process_agent() {
  local canonical_file="$1"

  local name description model tools team
  name="$(extract_frontmatter "$canonical_file" "name")"
  description="$(extract_frontmatter "$canonical_file" "description")"
  model="$(extract_frontmatter "$canonical_file" "model")"
  tools="$(extract_frontmatter "$canonical_file" "tools")"
  team="$(extract_frontmatter "$canonical_file" "team")"

  local provider model_id
  provider="$(parse_provider "$model")"
  model_id="$(parse_model_id "$model")"

  validate_model "$provider" "$model_id" "$name"

  local cc_model oc_model
  cc_model="$(claude_code_model "$provider" "$model_id")"
  oc_model="$(opencode_model "$provider" "$model_id")"

  local body
  body="$(extract_body "$canonical_file")"

  echo -e "${BLUE}→${NC} $name ${CYAN}[$provider]${NC}"

  # ── Skills: resolver, validar, instalar en .claude/skills/ ───────────────
  resolve_and_install_skills "$canonical_file" "$name"
  local cc_tools body_with_skills
  body_with_skills="${body}${SKILLS_INJECT}"
  if [[ ${#INSTALLED_SLUGS[@]} -gt 0 ]]; then
    cc_tools="$(ensure_skill_tool "$tools")"
    echo -e "  ${GREEN}✓${NC} Skills      → ${#INSTALLED_SLUGS[@]} instaladas: ${INSTALLED_SLUGS[*]}"
  else
    cc_tools="$tools"
  fi

  # ── Claude Code (.claude/agents/) ────────────────────────────────────────
  local claude_content
  claude_content="---
name: ${name}
description: ${description}
model: ${cc_model}
tools: ${cc_tools}
---
${body_with_skills}"

  if [[ "$DRY_RUN" == false ]]; then
    echo "$claude_content" > "$CLAUDE_DIR/${name}.md"
  fi

  if [[ "$provider" != "claude" ]]; then
    echo -e "  ${GREEN}✓${NC} Claude Code → ${name}.md  ${YELLOW}↩ fallback ${model} → ${cc_model}${NC}"
    fallback_log+=("${name}: ${model} → ${cc_model}")
  else
    echo -e "  ${GREEN}✓${NC} Claude Code → ${name}.md"
  fi

  # ── OpenCode — DESACTIVADO (owner lo probó y lo descartó, ADR-001 2026-07-02) ──
  # Para reactivar: descomentar este bloque y el mkdir de OPENCODE_DIR más abajo.
  # local opencode_content
  # opencode_content="---
# mode: subagent
# description: ${description}
# model: ${oc_model}
# ---
# ${body_with_skills}"
  # if [[ "$DRY_RUN" == false ]]; then
  #   echo "$opencode_content" > "$OPENCODE_DIR/${name}.md"
  # fi
  # echo -e "  ${GREEN}✓${NC} OpenCode    → ${name}.md  (${oc_model})"

  case "$provider" in
    claude)        ((count_claude++)) || true ;;
    codex|openai)  ((count_codex++))  || true ;;
    ollama)        ((count_ollama++)) || true ;;
  esac

  ((generated++)) || true
}

# Asegurar directorios de destino
mkdir -p "$CLAUDE_DIR" "$CLAUDE_SKILLS_DIR"   # OPENCODE_DIR desactivado (ADR-001)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Agent Sync — Canonical → Plataformas"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

while IFS= read -r -d '' file; do
  process_agent "$file"
done < <(find "$CANONICAL_DIR" -name "*.md" -print0 | sort -z)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}✓ Completado${NC}: $generated agentes generados"
echo ""
echo "  Providers:"
echo -e "    claude  $count_claude agentes"
echo -e "    codex   $count_codex agentes"
echo -e "    ollama  $count_ollama agentes"

if [[ ${#fallback_log[@]} -gt 0 ]]; then
  echo ""
  echo "  Fallbacks Claude Code (provider externo → modelo Anthropic):"
  for entry in "${fallback_log[@]}"; do
    echo -e "    ${YELLOW}↩${NC} $entry"
  done
fi

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo -e "  ${YELLOW}(DRY RUN — no se escribió nada)${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

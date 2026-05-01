#!/usr/bin/env bash
# sync-agents.sh
# Genera archivos para Claude Code (.claude/agents/) y OpenCode (.opencode/agents/)
# a partir de los archivos canónicos en agents/
#
# Uso: ./scripts/sync-agents.sh [--dry-run]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANONICAL_DIR="$ROOT/agents"
CLAUDE_DIR="$ROOT/.claude/agents"
OPENCODE_DIR="$ROOT/.opencode/agents"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[DRY RUN] No se escribirán archivos"
fi

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

generated=0
skipped=0

# Herramienta para extraer valor del frontmatter YAML
extract_frontmatter() {
  local file="$1"
  local key="$2"
  # Extrae valor entre los delimitadores --- del frontmatter
  awk '/^---/{c++; next} c==1 && /^'"$key"':/{gsub(/^'"$key"':[[:space:]]*/, ""); gsub(/^"/, ""); gsub(/"$/, ""); print; exit}' "$file"
}

# Extrae el body (todo después del segundo ---)
extract_body() {
  local file="$1"
  awk '/^---/{c++; next} c>=2' "$file"
}

# Extrae frontmatter completo como texto
extract_frontmatter_block() {
  local file="$1"
  awk '/^---/{c++; if(c==2) exit; next} c==1{print}' "$file"
}

process_agent() {
  local canonical_file="$1"
  local filename
  filename="$(basename "$canonical_file")"

  # Leer valores del frontmatter canónico
  local name description model tools team
  name="$(extract_frontmatter "$canonical_file" "name")"
  description="$(extract_frontmatter "$canonical_file" "description")"
  model="$(extract_frontmatter "$canonical_file" "model")"
  tools="$(extract_frontmatter "$canonical_file" "tools")"
  team="$(extract_frontmatter "$canonical_file" "team")"

  local body
  body="$(extract_body "$canonical_file")"

  echo -e "${BLUE}→ Procesando:${NC} $name ($team)"

  # ── Claude Code ──────────────────────────────────────────────────────────
  local claude_file="$CLAUDE_DIR/${name}.md"
  local claude_content
  claude_content="---
name: ${name}
description: ${description}
model: ${model}
tools: ${tools}
---
${body}"

  if [[ "$DRY_RUN" == false ]]; then
    echo "$claude_content" > "$claude_file"
  fi
  echo -e "  ${GREEN}✓${NC} Claude Code → .claude/agents/${name}.md"

  # ── OpenCode ─────────────────────────────────────────────────────────────
  local opencode_file="$OPENCODE_DIR/${name}.md"
  local opencode_content
  opencode_content="---
mode: subagent
description: ${description}
model: ${model}
---
${body}"

  if [[ "$DRY_RUN" == false ]]; then
    echo "$opencode_content" > "$opencode_file"
  fi
  echo -e "  ${GREEN}✓${NC} OpenCode    → .opencode/agents/${name}.md"

  ((generated++)) || true
}

# Asegurar directorios de destino
mkdir -p "$CLAUDE_DIR" "$OPENCODE_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Agent Sync — Canonical → Plataformas"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Procesar todos los archivos canónicos
while IFS= read -r -d '' file; do
  process_agent "$file"
done < <(find "$CANONICAL_DIR" -name "*.md" -print0 | sort -z)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}✓ Completado${NC}: $generated agentes generados"
if [[ "$DRY_RUN" == true ]]; then
  echo -e "  ${YELLOW}(DRY RUN — no se escribió nada)${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

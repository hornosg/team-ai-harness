#!/usr/bin/env bash
# install-management.sh
# Instala el harness de agentes en management/ del proyecto destino.
#
# Uso:
#   ./install-management.sh [TARGET_DIR] [--upgrade]
#
#   TARGET_DIR  — directorio raíz del proyecto destino (default: directorio actual)
#   --upgrade   — actualiza agentes y skills sin tocar PROJECT.md ni CLAUDE.md del usuario
#
# Ejemplos:
#   ./install-management.sh                        # instala en el directorio actual
#   ./install-management.sh /path/to/my-project    # instala en un directorio específico
#   ./install-management.sh /path/to/my-project --upgrade  # actualiza

set -euo pipefail

# ─── Colores ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ─── Argumentos ───────────────────────────────────────────────────────────────
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET=""
UPGRADE=false
for arg in "$@"; do
  case "$arg" in
    --upgrade) UPGRADE=true ;;
    *) TARGET="$arg" ;;
  esac
done
TARGET="${TARGET:-$(pwd)}"
TARGET="$(cd "$TARGET" && pwd)"

MGMT_DIR="$TARGET/management"

# ─── Helpers ──────────────────────────────────────────────────────────────────
step()  { echo -e "\n${BLUE}▸ $*${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}  $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; exit 1; }

# ─── Validaciones ─────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Management Team AI — Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Source : $SOURCE"
echo "  Target : $TARGET"
echo "  Mode   : $([ "$UPGRADE" == true ] && echo 'UPGRADE' || echo 'INSTALL')"
echo ""

[[ -d "$TARGET" ]] || fail "El directorio destino no existe: $TARGET"
[[ -d "$SOURCE/agents" ]] || fail "Source inválido — no se encontró agents/ en: $SOURCE"

if [[ "$UPGRADE" == false && -d "$MGMT_DIR" ]]; then
  warn "management/ ya existe en $TARGET"
  warn "Usá --upgrade para actualizar agentes y skills, preservando PROJECT.md y CLAUDE.md"
  echo ""
  read -rp "  ¿Continuar igualmente? (s/N): " confirm
  [[ "$confirm" =~ ^[sS]$ ]] || { echo "  Instalación cancelada."; exit 0; }
fi

# ─── 1. Crear estructura ──────────────────────────────────────────────────────
step "Creando estructura en management/"
mkdir -p \
  "$MGMT_DIR/agents/dev" \
  "$MGMT_DIR/agents/product" \
  "$MGMT_DIR/agents/marketing" \
  "$MGMT_DIR/agents/orchestrators" \
  "$MGMT_DIR/skills/dev" \
  "$MGMT_DIR/skills/marketing" \
  "$MGMT_DIR/skills/shared" \
  "$MGMT_DIR/rules" \
  "$MGMT_DIR/config" \
  "$MGMT_DIR/scripts" \
  "$TARGET/.claude/agents" \
  "$TARGET/.opencode/agents"
ok "Directorios listos"

# ─── 2. Copiar agentes canónicos ──────────────────────────────────────────────
step "Copiando agentes canónicos"
for dir in dev product marketing orchestrators; do
  if [[ -d "$SOURCE/agents/$dir" ]]; then
    cp "$SOURCE/agents/$dir/"*.md "$MGMT_DIR/agents/$dir/" 2>/dev/null || true
    count=$(ls "$MGMT_DIR/agents/$dir/"*.md 2>/dev/null | wc -l | tr -d ' ')
    ok "$dir/ → $count agentes"
  fi
done

# ─── 3. Copiar skills ─────────────────────────────────────────────────────────
step "Copiando skills"
for dir in dev marketing shared; do
  if [[ -d "$SOURCE/skills/$dir" ]]; then
    cp "$SOURCE/skills/$dir/"*.md "$MGMT_DIR/skills/$dir/" 2>/dev/null || true
    count=$(ls "$MGMT_DIR/skills/$dir/"*.md 2>/dev/null | wc -l | tr -d ' ')
    ok "$dir/ → $count skills"
  fi
done

# ─── 4. Copiar config ─────────────────────────────────────────────────────────
step "Copiando configuración"
if [[ -d "$SOURCE/config" ]]; then
  cp "$SOURCE/config/"*.yaml "$MGMT_DIR/config/" 2>/dev/null || true
  ok "config/"
fi

# ─── 4b. Copiar rules/ ────────────────────────────────────────────────────────
step "Copiando rules/"
if [[ -d "$SOURCE/rules" ]]; then
  cp "$SOURCE/rules/"*.md "$MGMT_DIR/rules/" 2>/dev/null || true
  count=$(ls "$MGMT_DIR/rules/"*.md 2>/dev/null | wc -l | tr -d ' ')
  ok "rules/ → $count archivos (templates para completar)"
fi

# ─── 5. Generar sync-agents.sh adaptado ──────────────────────────────────────
step "Generando management/scripts/sync-agents.sh"
cat > "$MGMT_DIR/scripts/sync-agents.sh" << 'SYNC_EOF'
#!/usr/bin/env bash
# sync-agents.sh (management edition)
# Genera archivos para cada adapter configurado en ADAPTERS.
# Ejecutar desde cualquier lugar — resuelve paths relativos al script.
#
# Uso:
#   ./sync-agents.sh              # adapters default (claude + opencode)
#   ./sync-agents.sh --all        # todos los adapters
#   ./sync-agents.sh --dry-run    # sin escribir archivos

set -euo pipefail

MGMT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$MGMT_DIR/.." && pwd)"
CANONICAL_DIR="$MGMT_DIR/agents"
RULES_DIR="$MGMT_DIR/rules"

# ─── Adapters activos ────────────────────────────────────────────────────────
# Descomentar los que se quieran activar:
ADAPTERS=(claude opencode)
# ADAPTERS=(claude opencode cursor copilot)

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true; echo "[DRY RUN] No se escribirán archivos" ;;
    --all)     ADAPTERS=(claude opencode cursor copilot) ;;
  esac
done

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

generated=0

# ─── Helpers ─────────────────────────────────────────────────────────────────
extract_frontmatter() {
  local file="$1" key="$2"
  awk '/^---/{c++; next} c==1 && /^'"$key"':/{gsub(/^'"$key"':[[:space:]]*/, ""); gsub(/^"/, ""); gsub(/"$/, ""); print; exit}' "$file"
}
extract_body() { awk '/^---/{c++; next} c>=2' "$1"; }

# ─── Adapter: Claude Code ────────────────────────────────────────────────────
adapter_claude() {
  local name="$1" description="$2" model="$3" tools="$4" body="$5"
  local out="$ROOT/.claude/agents/${name}.md"
  [[ "$DRY_RUN" == false ]] && \
    printf -- '---\nname: %s\ndescription: %s\nmodel: %s\ntools: %s\n---\n%s' \
      "$name" "$description" "$model" "$tools" "$body" > "$out"
  echo -e "    ${GREEN}✓${NC} claude  → .claude/agents/${name}.md"
}

# ─── Adapter: OpenCode ───────────────────────────────────────────────────────
adapter_opencode() {
  local name="$1" description="$2" model="$3" body="$5"
  local out="$ROOT/.opencode/agents/${name}.md"
  [[ "$DRY_RUN" == false ]] && \
    printf -- '---\nmode: subagent\ndescription: %s\nmodel: %s\n---\n%s' \
      "$description" "$model" "$body" > "$out"
  echo -e "    ${GREEN}✓${NC} opencode → .opencode/agents/${name}.md"
}

# ─── Adapter: Cursor ─────────────────────────────────────────────────────────
# Agentes no soportados en Cursor — solo rules y skills vía .cursor/rules/
adapter_cursor_rules() {
  [[ ! -d "$RULES_DIR" ]] && return
  mkdir -p "$ROOT/.cursor/rules"
  while IFS= read -r -d '' rulefile; do
    local basename filename mdc_out
    basename="$(basename "$rulefile" .md)"
    filename="${basename}.mdc"
    mdc_out="$ROOT/.cursor/rules/${filename}"
    if [[ "$DRY_RUN" == false ]]; then
      printf -- '---\ndescription: "%s"\nglobs: []\nalwaysApply: true\n---\n' "$basename" > "$mdc_out"
      # body sin frontmatter
      awk '/^---/{c++; next} c>=2' "$rulefile" >> "$mdc_out" 2>/dev/null || cat "$rulefile" >> "$mdc_out"
    fi
    echo -e "    ${GREEN}✓${NC} cursor  → .cursor/rules/${filename}"
  done < <(find "$RULES_DIR" -name "*.md" -not -name "_*" -print0 | sort -z)
}

# ─── Adapter: Copilot ────────────────────────────────────────────────────────
adapter_copilot() {
  local name="$1" description="$2" model="$3" body="$5"
  mkdir -p "$ROOT/.github/agents"
  local out="$ROOT/.github/agents/${name}.agent.md"
  [[ "$DRY_RUN" == false ]] && \
    printf -- '---\nname: %s\ndescription: %s\nmodel: %s\n---\n%s' \
      "$name" "$description" "$model" "$body" > "$out"
  echo -e "    ${GREEN}✓${NC} copilot → .github/agents/${name}.agent.md"
}

adapter_copilot_instructions() {
  [[ ! -d "$RULES_DIR" ]] && return
  mkdir -p "$ROOT/.github/instructions"
  while IFS= read -r -d '' rulefile; do
    local basename out
    basename="$(basename "$rulefile" .md)"
    out="$ROOT/.github/instructions/${basename}.instructions.md"
    if [[ "$DRY_RUN" == false ]]; then
      printf -- '---\napplyTo: "**"\n---\n' > "$out"
      awk '/^---/{c++; next} c>=2' "$rulefile" >> "$out" 2>/dev/null || cat "$rulefile" >> "$out"
    fi
    echo -e "    ${GREEN}✓${NC} copilot → .github/instructions/${basename}.instructions.md"
  done < <(find "$RULES_DIR" -name "*.md" -not -name "_*" -print0 | sort -z)
}

# ─── Crear directorios de output ─────────────────────────────────────────────
for adapter in "${ADAPTERS[@]}"; do
  case "$adapter" in
    claude)   mkdir -p "$ROOT/.claude/agents" ;;
    opencode) mkdir -p "$ROOT/.opencode/agents" ;;
    cursor)   mkdir -p "$ROOT/.cursor/rules" ;;
    copilot)  mkdir -p "$ROOT/.github/agents" "$ROOT/.github/instructions" ;;
  esac
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Agent Sync — management → adapters"
echo "  Activos: ${ADAPTERS[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Procesar agentes ────────────────────────────────────────────────────────
while IFS= read -r -d '' file; do
  local_name description model tools team body
  local_name="$(extract_frontmatter "$file" "name")"
  description="$(extract_frontmatter "$file" "description")"
  model="$(extract_frontmatter "$file" "model")"
  tools="$(extract_frontmatter "$file" "tools")"
  team="$(extract_frontmatter "$file" "team")"
  body="$(extract_body "$file")"

  echo -e "${BLUE}→${NC} $local_name ($team)"
  for adapter in "${ADAPTERS[@]}"; do
    case "$adapter" in
      claude)   adapter_claude   "$local_name" "$description" "$model" "$tools" "$body" ;;
      opencode) adapter_opencode "$local_name" "$description" "$model" "$tools" "$body" ;;
      copilot)  adapter_copilot  "$local_name" "$description" "$model" "$tools" "$body" ;;
    esac
  done
  ((generated++)) || true
done < <(find "$CANONICAL_DIR" -name "*.md" -print0 | sort -z)

# ─── Rules: adapters que las soportan ────────────────────────────────────────
for adapter in "${ADAPTERS[@]}"; do
  case "$adapter" in
    cursor)  echo -e "\n${BLUE}→${NC} Rules (cursor)";  adapter_cursor_rules ;;
    copilot) echo -e "\n${BLUE}→${NC} Rules (copilot)"; adapter_copilot_instructions ;;
  esac
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}✓ Completado${NC}: $generated agentes generados"
echo "  Adapters: ${ADAPTERS[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SYNC_EOF
chmod +x "$MGMT_DIR/scripts/sync-agents.sh"
ok "management/scripts/sync-agents.sh"

# ─── 4c. Copiar adapters/ ────────────────────────────────────────────────────
step "Copiando adapters/"
if [[ -d "$SOURCE/adapters" ]]; then
  mkdir -p "$MGMT_DIR/adapters"
  cp -r "$SOURCE/adapters/"* "$MGMT_DIR/adapters/"
  ok "adapters/ → claude, opencode, cursor, copilot"
fi

# ─── 5b. Copiar roadmap/ ─────────────────────────────────────────────────────
step "Copiando roadmap/"
if [[ -d "$SOURCE/roadmap" ]]; then
  mkdir -p "$MGMT_DIR/roadmap/epicas" "$MGMT_DIR/roadmap/propuestas"
  cp "$SOURCE/roadmap/roadmap.yaml" "$MGMT_DIR/roadmap/"
  cp "$SOURCE/roadmap/README.md" "$MGMT_DIR/roadmap/"
  cp "$SOURCE/roadmap/epicas/_TEMPLATE.md" "$MGMT_DIR/roadmap/epicas/"
  cp "$SOURCE/roadmap/propuestas/_TEMPLATE.md" "$MGMT_DIR/roadmap/propuestas/"
  cp "$SOURCE/roadmap/propuestas/README.md" "$MGMT_DIR/roadmap/propuestas/"
  ok "roadmap/ → roadmap.yaml + templates de épicas y propuestas"
fi

# ─── 6. Copiar AGENTS.md ─────────────────────────────────────────────────────
step "Copiando AGENTS.md"
if [[ -f "$SOURCE/AGENTS.md" ]]; then
  cp "$SOURCE/AGENTS.md" "$MGMT_DIR/AGENTS.md"
  ok "AGENTS.md"
fi

# ─── 7. PROJECT.md — solo en install fresh ───────────────────────────────────
if [[ "$UPGRADE" == false || ! -f "$MGMT_DIR/PROJECT.md" ]]; then
  step "Creando management/PROJECT.md (template)"
  cp "$SOURCE/PROJECT.md" "$MGMT_DIR/PROJECT.md"
  ok "PROJECT.md — completar con datos del proyecto"
fi

# ─── 8. management/CLAUDE.md — solo en install fresh ─────────────────────────
if [[ "$UPGRADE" == false || ! -f "$MGMT_DIR/CLAUDE.md" ]]; then
  step "Creando management/CLAUDE.md"
  cat > "$MGMT_DIR/CLAUDE.md" << 'CLAUDE_EOF'
# Management Team AI

Este proyecto usa el harness de agentes multi-equipo.

## Invocación

`@meta-router` → punto de entrada para cualquier pedido. Clasifica y rutea.

Acceso directo:
- `@dev-orchestrator` — trabajo técnico
- `@product-orchestrator` — discovery, features, métricas
- `@marketing-orchestrator` — copy, campañas, SEO

## Comandos frecuentes

| Pedido | Resultado |
|--------|-----------|
| `@meta-router status` | Reporte de roadmap — épicas, propuestas, specs |
| `@meta-router crear epica [X]` | Genera PROP-NNN + epica si se aprueba |
| `@meta-router [pedido]` | Clasifica dominio y rutea al orchestrator correcto |

## Estructura

```
management/
├── PROJECT.md          # Fuente de verdad — COMPLETAR
├── AGENTS.md           # Índice de agentes
├── agents/             # 32 agentes canónicos
├── skills/
│   ├── dev/            # code-reviewer, owasp, conventional-commit, pr-workflow, memory-protocol
│   ├── marketing/      # market-audit, market-seo, market-copy, market-cro, market-competitors
│   └── shared/         # bmad-*, roadmap-management, roadmap-status
├── rules/              # architecture.md, api-standards.md, security.md
├── roadmap/
│   ├── roadmap.yaml    # Hitos + épicas + estado — COMPLETAR
│   ├── epicas/         # Detalle de cada épica
│   └── propuestas/     # Propuestas pendientes de aprobación
├── adapters/           # Formatos para Claude Code, OpenCode, Cursor, Copilot
├── config/
└── scripts/
    └── sync-agents.sh  # Genera adapters configurados
```

## Ceremony levels

- **L1** — Quick fix reversible (<30min, sin money/auth)
- **L2** — Feature con spec clara
- **L3** — Cambio arquitectural o migración
- **L4** — CRÍTICO: money/auth/compliance → @architect + @security obligatorio

## Adapters

El sync-agents.sh genera formatos para múltiples herramientas:
```bash
./management/scripts/sync-agents.sh           # default: claude + opencode
./management/scripts/sync-agents.sh --all     # + cursor + copilot
```

## Primer uso

1. Completar `management/PROJECT.md`
2. Completar `management/roadmap/roadmap.yaml` con hitos y épicas reales
3. `@meta-router status` para ver el estado inicial
4. `@meta-router [cualquier pedido]` para empezar a trabajar

## Memoria persistente (Engram)

Agentes Opus/Sonnet guardan decisiones entre sesiones via Engram MCP.
Ver `management/skills/dev/memory-protocol.md`.
CLAUDE_EOF
  ok "management/CLAUDE.md"
fi

# ─── 9. Root CLAUDE.md ────────────────────────────────────────────────────────
step "Configurando CLAUDE.md en raíz del proyecto"
ROOT_CLAUDE="$TARGET/CLAUDE.md"

if [[ -f "$ROOT_CLAUDE" ]]; then
  # Ya existe — verificar si ya tiene el import
  if grep -q "@management/CLAUDE.md" "$ROOT_CLAUDE" 2>/dev/null; then
    ok "CLAUDE.md ya referencia management/CLAUDE.md — sin cambios"
  else
    # Agregar import al principio
    EXISTING_CONTENT="$(cat "$ROOT_CLAUDE")"
    printf '@management/CLAUDE.md\n\n%s\n' "$EXISTING_CONTENT" > "$ROOT_CLAUDE"
    ok "CLAUDE.md actualizado — import agregado al inicio"
  fi
else
  # Crear CLAUDE.md mínimo
  cat > "$ROOT_CLAUDE" << 'ROOT_EOF'
@management/CLAUDE.md
ROOT_EOF
  ok "CLAUDE.md creado"
fi

# ─── 10. Sync inicial ─────────────────────────────────────────────────────────
step "Ejecutando sync inicial de agentes"
bash "$MGMT_DIR/scripts/sync-agents.sh"

# ─── Resumen ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}✓ Instalación completa${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  management/PROJECT.md   ← completar con datos del proyecto"
echo "  management/CLAUDE.md    ← personalizar si hace falta"
echo ""
echo "  Próximos pasos:"
echo "  1. Editar management/PROJECT.md"
echo "  2. Abrir Claude Code y usar @meta-router"
echo ""

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
    --upgrade|--update) UPGRADE=true ;;
    --*) ;;  # ignorar flags desconocidos
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
    cp -R "$SOURCE/skills/$dir/." "$MGMT_DIR/skills/$dir/" 2>/dev/null || true
    count=$(find "$MGMT_DIR/skills/$dir" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
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
SKILLS_SRC="$MGMT_DIR/skills"
CLAUDE_SKILLS_DIR="$ROOT/.claude/skills"

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
# Setea globales: INSTALLED_SLUGS (array) y SKILLS_INJECT (bloque markdown).
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
      echo -e "    ${YELLOW}⚠ skill no encontrada:${NC} '$ref' (referenciada por $agent_name)"
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
  name="" description="" model="" tools="" team="" body=""
  name="$(extract_frontmatter "$file" "name")"
  description="$(extract_frontmatter "$file" "description")"
  model="$(extract_frontmatter "$file" "model")"
  tools="$(extract_frontmatter "$file" "tools")"
  team="$(extract_frontmatter "$file" "team")"
  body="$(extract_body "$file")"

  echo -e "${BLUE}→${NC} $name ($team)"

  # Skills: resolver, validar, instalar en .claude/skills/ + inyectar en el body
  resolve_and_install_skills "$file" "$name"
  local_body="${body}${SKILLS_INJECT}"
  cc_tools="$tools"
  if [[ ${#INSTALLED_SLUGS[@]} -gt 0 ]]; then
    cc_tools="$(ensure_skill_tool "$tools")"
    echo -e "    ${GREEN}✓${NC} skills  → ${#INSTALLED_SLUGS[@]} instaladas: ${INSTALLED_SLUGS[*]}"
  fi

  for adapter in "${ADAPTERS[@]}"; do
    case "$adapter" in
      claude)   adapter_claude   "$name" "$description" "$model" "$cc_tools" "$local_body" ;;
      opencode) adapter_opencode "$name" "$description" "$model" "$cc_tools" "$local_body" ;;
      copilot)  adapter_copilot  "$name" "$description" "$model" "$cc_tools" "$local_body" ;;
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

# ─── 4d. Copiar helper de merge de settings.local.json ───────────────────────
step "Copiando helper de settings.local.json"
if [[ -f "$SOURCE/scripts/merge-claude-settings.py" ]]; then
  cp "$SOURCE/scripts/merge-claude-settings.py" "$MGMT_DIR/scripts/"
  chmod +x "$MGMT_DIR/scripts/merge-claude-settings.py"
  ok "management/scripts/merge-claude-settings.py"
fi

# ─── 4c. Copiar adapters/ ────────────────────────────────────────────────────
step "Copiando adapters/"
if [[ -d "$SOURCE/adapters" ]]; then
  mkdir -p "$MGMT_DIR/adapters"
  cp -r "$SOURCE/adapters/"* "$MGMT_DIR/adapters/"
  ok "adapters/ → claude, opencode, cursor, copilot"
fi

# ─── 5b. Copiar roadmap/ ─────────────────────────────────────────────────────
# roadmap.yaml es CONTENIDO DEL USUARIO (hitos/épicas reales): igual que PROJECT.md,
# NO se pisa en --upgrade. Solo se copia en install fresh o si no existe. Los
# templates (_TEMPLATE.md, README.md) sí se refrescan siempre (no son contenido).
step "Copiando roadmap/"
if [[ -d "$SOURCE/roadmap" ]]; then
  mkdir -p "$MGMT_DIR/roadmap/epicas" "$MGMT_DIR/roadmap/propuestas"
  if [[ "$UPGRADE" == false || ! -f "$MGMT_DIR/roadmap/roadmap.yaml" ]]; then
    cp "$SOURCE/roadmap/roadmap.yaml" "$MGMT_DIR/roadmap/"
    ok "roadmap.yaml (template) — completar con hitos y épicas reales"
  else
    warn "roadmap.yaml preservado (--upgrade no pisa contenido del usuario)"
  fi
  cp "$SOURCE/roadmap/README.md" "$MGMT_DIR/roadmap/"
  cp "$SOURCE/roadmap/epicas/_TEMPLATE.md" "$MGMT_DIR/roadmap/epicas/"
  cp "$SOURCE/roadmap/propuestas/_TEMPLATE.md" "$MGMT_DIR/roadmap/propuestas/"
  cp "$SOURCE/roadmap/propuestas/README.md" "$MGMT_DIR/roadmap/propuestas/"
  ok "roadmap/ → templates de épicas y propuestas refrescados"
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
│   ├── dev/            # code-reviewer, owasp, conventional-commit, pr-workflow, memory-protocol, atomic-session-planning
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
    ├── sync-agents.sh          # Genera adapters configurados
    └── merge-claude-settings.py # Configura Engram MCP si se instala después
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

## Planes atómicos

Para iniciativas que requieran varias sesiones o afecten más de un servicio, usá `skills/dev/atomic-session-planning/SKILL.md`.

- Planes cross-project: `~/Projects/management/plans/<proyecto>/YYYY-MM-DD_<slug>.md`
- Índice local: `.claude/plans/INDEX.md`

Una sola tarea `in_progress` por sesión; el handoff se guarda en Engram.

## Memoria persistente (Engram)

Agentes Opus/Sonnet guardan decisiones entre sesiones via Engram MCP.
Ver `management/skills/dev/memory-protocol/SKILL.md`.

Si Engram no estaba instalado al correr el installer, instalalo con `brew install gentleman-programming/tap/engram` y luego ejecutá:

```bash
python3 management/scripts/merge-claude-settings.py .
```
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

# ─── 9b. Configurar Engram MCP ─────────────────────────────────────────────────
step "Configurando Engram MCP"
if command -v engram &> /dev/null; then
  ENGRAM_VERSION="$(engram --version 2>/dev/null || echo 'desconocida')"
  ok "Engram detectado ($ENGRAM_VERSION)"
  if [[ -f "$MGMT_DIR/scripts/merge-claude-settings.py" ]]; then
    python3 "$MGMT_DIR/scripts/merge-claude-settings.py" "$TARGET"
    ok "MCP Engram registrado en .claude/settings.local.json"
  else
    warn "Helper merge-claude-settings.py no encontrado — MCP no configurado"
  fi
else
  warn "Engram no está en PATH"
  warn "Para activar la memoria persistente, instalalo con:"
  warn "  brew install gentleman-programming/tap/engram"
  warn "Luego ejecutá: python3 management/scripts/merge-claude-settings.py ."
fi

# ─── 9c. Crear índice local de planes atómicos ─────────────────────────────────
step "Creando índice de planes atómicos"
PROJECT_SLUG="$(basename "$TARGET")"
mkdir -p "$TARGET/.claude/plans"
cat > "$TARGET/.claude/plans/INDEX.md" << 'INDEX_EOF'
# Planes atómicos vinculados a este proyecto

Los planes concretos viven en `~/Projects/management/plans/PROJECT_SLUG/`.
Este archivo es solo un índice local.

## Planes activos

| Plan | Archivo | Descripción | Estado |
|------|---------|-------------|--------|
| —    | —       | —           | —      |

## Cómo agregar un plan

1. Crear `~/Projects/management/plans/PROJECT_SLUG/YYYY-MM-DD_<slug>.md`.
2. Seguir `skills/dev/atomic-session-planning/SKILL.md`.
3. Actualizar la tabla de este índice.
INDEX_EOF
sed -i '' "s/PROJECT_SLUG/${PROJECT_SLUG}/g" "$TARGET/.claude/plans/INDEX.md"
ok ".claude/plans/INDEX.md"

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
if command -v engram &> /dev/null; then
  echo "  .claude/settings.local.json ← MCP Engram activado"
else
  echo "  ⚠ Engram no instalado — memoria persistente desactivada"
fi
echo ""
echo "  Próximos pasos:"
echo "  1. Editar management/PROJECT.md"
echo "  2. Abrir Claude Code y usar @meta-router"
echo ""

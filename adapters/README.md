# Adapter Matrix

Cada adapter transforma los assets canónicos de `management/` al formato nativo de cada herramienta de IA. El sync-agents.sh genera todos los adapters configurados.

## Capacidades por adapter

| Adapter | Agentes | Rules | Skills | Context file | MCP config |
|---------|---------|-------|--------|--------------|-----------|
| **Claude Code** | `.claude/agents/*.md` | — | vía CLAUDE.md | `CLAUDE.md → @management/CLAUDE.md` | `.claude/settings.local.json` |
| **OpenCode** | `.opencode/agents/*.md` | — | vía CLAUDE.md | — | — |
| **Cursor** | — | `.cursor/rules/*.mdc` | `.cursor/rules/*.mdc` | `.cursorrules` | `.cursor/mcp.json` |
| **Copilot** | `.github/agents/*.agent.md` | `.github/instructions/*.instructions.md` | — | `.github/copilot-instructions.md` | `.github/copilot-mcp.json` |

## Transformaciones de formato

| Asset canónico | Claude Code | Cursor | Copilot |
|---------------|-------------|--------|---------|
| `management/agents/*.md` | `.claude/agents/*.md` (frontmatter: name/description/model/tools) | N/A | `.github/agents/*.agent.md` (frontmatter: name/description/model) |
| `management/rules/*.md` | vía `@management/CLAUDE.md` | `.cursor/rules/*.mdc` (frontmatter: description/globs/alwaysApply) | `.github/instructions/*.instructions.md` (frontmatter: applyTo) |
| `management/skills/*.md` | vía `@management/CLAUDE.md` | `.cursor/rules/skills/*.mdc` | vía copilot-instructions.md |

## Activar adapters

En `management/scripts/sync-agents.sh`, descomentar los adapters deseados:

```bash
ADAPTERS=(claude opencode)     # default
# ADAPTERS=(claude opencode cursor copilot)  # todos
```

## Adapter: Claude Code (default)

Output: `.claude/agents/[name].md`

```yaml
---
name: dev-architect
description: [description]
model: claude-opus-4-6
tools: [Read, Grep, Glob]
---
[body]
```

## Adapter: OpenCode (default)

Output: `.opencode/agents/[name].md`

```yaml
---
mode: subagent
description: [description]
model: claude-opus-4-6
---
[body]
```

## Adapter: Cursor

Output: `.cursor/rules/[name].mdc`

Rules y skills se convierten a formato Cursor MDC:

```yaml
---
description: [description del rule/skill]
globs: ["**/*.ts", "**/*.tsx"]   # archivos donde aplica, o vacío para global
alwaysApply: true                # true para rules siempre activas
---
[body]
```

Agentes: Cursor no tiene soporte nativo de subagentes — las instrucciones van en `.cursorrules`.

## Adapter: Copilot

Output: `.github/instructions/[name].instructions.md`

```markdown
---
applyTo: "**"          # glob de archivos donde aplica
---
[body]
```

Agentes: `.github/agents/[name].agent.md`

```markdown
---
name: [name]
description: [description]
model: [model]
---
[body]
```

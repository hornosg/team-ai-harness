---
name: engram-setup
description: Configura Engram (memoria persistente para agentes AI) en un proyecto. Usar cuando el usuario pide "configurá engram en este proyecto", "agregá engram", "integrá la memoria persistente", "quiero que el agente recuerde entre sesiones", "configurá el MCP de engram", o cuando se detecta que un proyecto no tiene `.engram/config.json` ni el MCP de engram en su settings de Claude Code / VS Code / Cursor. Requiere engram instalado globalmente (`engram version`). Soporta Claude Code, VS Code, Cursor y OpenCode.
---

# engram-setup

Pipeline: verificación → identidad del proyecto → MCP por agente → `.engram/config.json` → `.gitignore` → Memory Protocol en CLAUDE.md → validación.

Engram es un servidor MCP + CLI en Go (SQLite + FTS5) que da memoria persistente entre sesiones a los agentes AI. Se instala una sola vez a nivel global; la configuración por proyecto es mínima.

## Prerequisito global

```bash
engram version
```

Si falla → el binario no está en PATH. Instalar con:
```bash
brew install gentleman-programming/tap/engram
# o:
go install github.com/Gentleman-Programming/engram/cmd/engram@latest
```

No continuar hasta que `engram version` responda. Esta skill no instala engram — solo configura proyectos.

## Execution scope

- Pedido completo → todas las fases en orden.
- Pedido parcial ("solo el MCP", "solo el CLAUDE.md") → siempre Fase 0 + la fase pedida.
- Fase 4 (git sync) es **opcional** — preguntar antes de activar si no fue pedida explícitamente.
- Fase 5 (env vars extra) solo si el proyecto usa Docker Compose, CI, o WSL.

## Convenciones

- Nunca modificar `engram.db` ni el directorio global `~/.engram` — son datos del usuario.
- Registrar cada archivo creado o modificado antes de escribirlo.
- Si el proyecto ya tiene parte de la configuración, completar lo que falta — no sobreescribir lo que existe.
- Nunca commitear. El usuario decide cuándo.

---

## Fase 0 — Discovery (siempre corre)

1. Verificar instalación global:
   ```bash
   engram version
   ```

2. Identificar el nombre del proyecto según la precedencia de engram:
   ```bash
   # ¿Existe .engram/config.json?
   cat .engram/config.json 2>/dev/null || echo "no existe"

   # ¿Cuál sería el nombre inferido por git?
   git remote get-url origin 2>/dev/null || basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
   ```

3. Detectar qué agentes / editores usa el proyecto:
   ```bash
   ls .claude/ .vscode/ .cursor/ opencode.json 2>/dev/null
   ```

4. Verificar si ya hay MCP de engram configurado:
   ```bash
   # Claude Code (proyecto)
   grep -l "engram" .claude/settings.json .claude/settings.local.json 2>/dev/null
   # VS Code
   grep -l "engram" .vscode/mcp.json 2>/dev/null
   # Cursor
   grep -l "engram" .cursor/mcp.json 2>/dev/null
   ```

5. Verificar `.gitignore`:
   ```bash
   grep -E "engram\.db|\.engram/chunks" .gitignore 2>/dev/null || echo "falta en .gitignore"
   ```

6. Verificar si `CLAUDE.md` existe y si ya tiene sección de Memory Protocol:
   ```bash
   grep -l "mem_context\|engram\|Engram" CLAUDE.md .claude/CLAUDE.md 2>/dev/null || echo "no tiene memory protocol"
   ```

Salida: resumen de estado antes de continuar:

| Componente | Estado | Acción |
|-----------|--------|--------|
| `engram version` | OK / FALLA | (parar si falla) |
| Nombre de proyecto | `<nombre>` detectado / ambiguo | Crear config.json / confirmar |
| MCP Claude Code | configurado / falta | Configurar |
| MCP VS Code | configurado / falta / no aplica | Configurar / skip |
| `.engram/config.json` | existe / falta | Crear |
| `.gitignore` | correcto / falta entrada | Agregar |
| Memory Protocol | presente / falta | Agregar a CLAUDE.md |

---

## Fase 1 — Nombre del proyecto

Confirmar con el usuario el nombre canónico antes de escribir cualquier archivo.

Criterios para elegir el nombre:
- Preferir el nombre semántico del dominio sobre el nombre del directorio git si difieren (ej. `mercado-cercano` en lugar de `saas-mt-pim-service`).
- En monorepos: usar nombres distintos por submódulo (ej. `mc-iam`, `mc-pim`) en lugar del nombre raíz del repo.
- Minúsculas, guiones, sin espacios.

Si el nombre detectado en Fase 0 es correcto → usarlo directamente, sin preguntar.  
Si hay ambigüedad o el directorio git tiene un nombre de slug opaco → preguntar al usuario.

---

## Fase 2 — Archivo `.engram/config.json`

Crear en la raíz del proyecto (o en el subdirectorio del módulo si es monorepo):

```json
{
  "project_name": "<nombre-confirmado>"
}
```

En monorepos con módulos independientes, crear un `config.json` por módulo:
```
backend/.engram/config.json   → { "project_name": "mc-iam" }
frontend/.engram/config.json  → { "project_name": "mc-frontend" }
```

No crear `.engram/config.json` en la raíz del monorepo si cada módulo tiene el suyo — evita el error `ambiguous_project`.

---

## Fase 3 — MCP por agente

Configurar el servidor MCP según los agentes detectados en Fase 0. El bloque MCP es idéntico para todos:

```json
{
  "command": "engram",
  "args": ["mcp"]
}
```

### 3a. Claude Code (proyecto)

Agregar en `.claude/settings.json` (crea el archivo si no existe):

```json
{
  "mcpServers": {
    "engram": {
      "command": "engram",
      "args": ["mcp"]
    }
  }
}
```

Si `.claude/settings.json` ya existe con otras claves, hacer merge quirúrgico — no sobreescribir el archivo completo. Agregar solo la clave `engram` dentro de `mcpServers`.

> **Nota**: si el usuario tiene el plugin `engram` instalado globalmente en Claude Code (`claude plugin install engram`), el MCP ya está activo y esta fase es redundante para Claude Code. Detectar con `claude plugin list 2>/dev/null | grep engram`. Si está instalado → skip 3a, anotar en reporte.

### 3b. VS Code

Crear o actualizar `.vscode/mcp.json`:

```json
{
  "servers": {
    "engram": {
      "command": "engram",
      "args": ["mcp"]
    }
  }
}
```

### 3c. Cursor

Crear o actualizar `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "engram": {
      "command": "engram",
      "args": ["mcp"]
    }
  }
}
```

### 3d. OpenCode

Si existe `opencode.json` en la raíz:

```bash
engram setup opencode
```

Este comando escribe la config en `~/.config/opencode/plugins/engram.ts` y agrega el MCP a `opencode.json`. No ejecutar sin confirmación del usuario ya que modifica archivos globales.

---

## Fase 4 — `.gitignore`

Agregar al `.gitignore` del proyecto (o crearlo si no existe):

```
# Engram
.engram/engram.db
.engram/*.db-*
```

**No** agregar `.engram/chunks/` al gitignore — si el usuario quiere git sync (Fase 5), los chunks se versionar. Si no usa git sync, los chunks no se crean.

Si `.gitignore` ya existe, buscar si hay alguna entrada de engram antes de agregar. Agregar al final del archivo.

---

## Fase 5 — Git sync (opcional)

Preguntar al usuario antes de activar si no fue pedida explícitamente.

Git sync exporta las memorias del proyecto como chunks JSONL comprimidos dentro de `.engram/chunks/`. Permite compartir memoria entre máquinas y colaboradores vía git.

Activar la primera vez:
```bash
engram sync
```

Esto crea `.engram/manifest.json` y el primer chunk en `.engram/chunks/`. Versionar todo en git:
```bash
git add .engram/manifest.json .engram/chunks/
git commit -m "chore: init engram git sync"
```

Flujo de trabajo posterior:
```bash
# Antes de cambiar de máquina o al terminar una sesión larga:
engram sync
git add .engram/ && git commit -m "chore: sync engram memories"

# Al retomar en otra máquina tras un pull:
engram sync --import
```

Si **no** se quiere git sync (opción más simple): no hacer nada. Las memorias viven solo en `~/.engram/engram.db` (global, por máquina).

---

## Fase 6 — Memory Protocol en CLAUDE.md

Agregar al `CLAUDE.md` del proyecto (crear si no existe) una sección de Memory Protocol para que Claude Code sepa cuándo y cómo usar Engram:

```markdown
## Memoria persistente (Engram)

Tenés acceso a memoria persistente entre sesiones vía las herramientas MCP de Engram (`mem_save`, `mem_search`, `mem_context`, etc.).

**Cuándo guardar** — sin esperar que te lo pidan:
- Al resolver un bug no trivial: síntoma, causa raíz, fix aplicado.
- Al tomar una decisión de diseño: qué se decidió y por qué.
- Al descubrir un patrón o convención del proyecto que no está documentada.
- Al completar una feature o refactor significativo: qué cambió y dónde.

**Cuándo buscar** — antes de empezar cualquier tarea:
- `mem_context` al inicio de sesión o tras una compaction para recuperar el estado anterior.
- `mem_search` cuando el usuario menciona algo que puede tener historial ("el bug de autenticación", "la migración de la semana pasada").

**Al cerrar sesión**: llamar `mem_session_summary` para dejar un resumen recuperable.
```

Si `CLAUDE.md` ya tiene una sección de Engram o Memory Protocol, no duplicarla — completarla si le falta algún punto.

---

## Fase 7 — Variable `ENGRAM_PROJECT` (si aplica)

Solo necesaria cuando el proceso MCP de engram no hereda el directorio de trabajo correcto: Docker, CI, WSL, o VS Code Dev Containers.

### Docker Compose

Agregar a los servicios que corren agentes AI (no a los servicios de app):

```yaml
services:
  mi-agente:
    environment:
      - ENGRAM_PROJECT=<nombre-del-proyecto>
```

### CI (GitHub Actions / GitLab CI)

```yaml
env:
  ENGRAM_PROJECT: <nombre-del-proyecto>
```

### `.env` local

Si el proyecto usa un `.env` o `.env.local`:

```bash
ENGRAM_PROJECT=<nombre-del-proyecto>
```

Verificar que `.env` esté en `.gitignore` antes de agregar.

---

## Fase 8 — Validación

```bash
# 1. Verificar que engram detecta el nombre correcto
#    (correr desde la raíz del proyecto o del submódulo)
engram projects list | grep "<nombre-esperado>"

# 2. Verificar que el MCP responde (Claude Code)
#    Desde una sesión de Claude Code en el proyecto:
#    → llamar mem_current_project
#    → debe devolver "<nombre-esperado>"

# 3. Verificar .gitignore
grep "engram" .gitignore

# 4. Si se activó git sync:
engram sync --status
```

Errores comunes:

| Síntoma | Causa probable | Fix |
|---------|---------------|-----|
| `ambiguous_project` en monorepo | Múltiples `.git` sin `config.json` por módulo | Crear `.engram/config.json` en cada submódulo |
| `mem_current_project` devuelve nombre del directorio, no el esperado | `config.json` no se creó o está en el lugar incorrecto | Verificar ruta del `config.json` relativa al `git root` |
| Herramientas MCP no aparecen en Claude Code | El MCP no está en `.claude/settings.json` o el plugin no está instalado | Revisar Fase 3a |
| Memorias de otro proyecto aparecen mezcladas | `ENGRAM_PROJECT` no está seteado en el entorno que corre el MCP | Agregar la variable (Fase 7) |
| `engram sync` no encuentra chunks al importar | Olvidaron hacer `git add .engram/` en la máquina origen | Correr `engram sync && git add .engram/ && git commit` en origen |

---

## Reporte final

1. **Archivos creados / modificados** — lista con ruta y cambio aplicado
2. **Nombre de proyecto registrado** — el valor en `config.json`
3. **Agentes configurados** — cuáles tienen el MCP activo (Claude Code, VS Code, Cursor…)
4. **Git sync** — activado / no activado (con comando para activarlo si quedó pendiente)
5. **Pendiente** — cualquier fase no ejecutada con el motivo y el comando para activarla

Factual y sin relleno.

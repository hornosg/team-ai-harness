# Cableado Agente ↔ Skill

No existe un "front controller" nativo en Claude Code que mapee agente→skill: las
skills se auto-descubren desde `.claude/skills/` y quedan disponibles para
cualquier actor que tenga la tool `Skill`. El mapa "qué skills usa cada agente" lo
formalizamos nosotros de forma **declarativa**.

## Fuente de verdad: frontmatter del agente

Cada agente canónico (`agents/**/*.md`) declara sus skills en el frontmatter:

```yaml
---
name: dev-senior-backend
tools: [Read, Grep, Glob, Edit, Write, Bash, Skill]   # Skill habilita la invocación
skills:
  - dev/hexagonal-go
  - dev/conventional-commit
  - dev/pr-workflow
---
```

- `skills:` — lista `area/slug` relativa a `skills/`. Es el mapa.
- `Skill` en `tools:` — sin esta tool el agente no puede invocar ninguna skill.

## Herramientas

### `wire-skills.py` — seeder / validador
Deriva el `skills:` inicial desde las referencias en prosa del cuerpo del agente
(`skills/<area>/<slug>`), garantiza `Skill` en `tools`, y valida que cada skill
exista. Idempotente.

```bash
./scripts/wire-skills.py <agents_dir> <skills_dir> [--dry-run]
```

Una vez sembrado, el frontmatter `skills:` es la fuente de verdad: editalo a mano
para cambiar el cableado (agregar/quitar líneas). El cuerpo del agente NO es el mapa.

### `sync-agents.sh` — materializador
Por cada agente, al generar el adapter de Claude Code:
1. **Valida** que cada skill referenciada exista en `skills/` (⚠ si falta).
2. **Instala** la `SKILL.md` (y archivos vecinos) en `.claude/skills/<slug>/` —
   esto es lo que hace que Claude Code efectivamente las cargue.
3. **Garantiza** `Skill` en el `tools:` generado.
4. **Inyecta** un bloque "Skills habilitadas" en el prompt del agente (soft-scoping:
   le dice al agente cuáles preferir, aunque nativamente vería todas).

```bash
./scripts/sync-agents.sh            # genera .claude/agents + .claude/skills (OpenCode desactivado, ADR-001)
```

## Notas

- Las skills no se "asignan" a un solo agente a nivel runtime: nativamente todo
  agente con `Skill` ve todas las skills instaladas. El `skills:` del frontmatter +
  el bloque inyectado son **scoping declarativo y por prompt**, no un sandbox.
- La validación es por árbol: cada repo valida `skills:` contra su propio inventario
  (`provider-selector` existe en el harness pero no en management, p.ej.).

---

# Cableado ADR ↔ Skill

Un ADR (decisión) siempre necesita dos tipos de skill: una para **llevarlo a cabo**
y otra para **controlar que se cumpla**. Eso se declara en el frontmatter del ADR.

## Frontmatter del ADR

```yaml
---
adr: ADR-002
status: accepted
skills:
  implement:          # skills que materializan la decisión
    - dev/hexagonal-go
    - dev/prometheus
  verify:             # skills que auditan/controlan el cumplimiento
    - dev/go-hex-audit
    - dev/code-reviewer
---
# ADR-002: Metrics Recording
```

- `implement` y `verify` son **listas** (`area/slug`), 0..N cada una.
- `pending` (opcional) — skills **deseadas que todavía no existen**. El validador las
  reporta como info (ℹ), no como error. Al crear la skill, se mueve de `pending` a
  `verify`/`implement`. La vista consolidada de gaps vive en `PROP-001` del roadmap.
- El cuerpo en prosa del ADR no cambia; el frontmatter va antes del `# ADR-NNN`.

## Taxonomía de skills

- **implement** → skills de construcción: `hexagonal-go/python/flutter`, `prometheus`,
  `loki`, `tracing`, `kong`, `digital-ocean`, `observability-stack`.
- **verify** → skills de control: `go-hex-audit`, `code-reviewer`, `owasp-top10`,
  `pre-commit-review`.

## `wire-adrs.py` — validador

No siembra (un ADR no referencia skills en prosa): el mapa se cura a mano. El script
sólo valida que cada skill exista y reporta ADRs sin cablear o referencias rotas.

```bash
./scripts/wire-adrs.py <adr_dir> <skills_dir>
```

Cableados: 3 ADRs globales (`vault/adr/` + `mercado-cercano/docs/adr/`, idénticos) y
los 17 de servicios (`services/*/docs/adr/`). Validan con 0 referencias rotas.

**Estado de pending (2026-06-12)**: de las 9 skills originalmente en `pending`, 4 se crearon
en la primera tanda (PROP-001 completada) + 1 `control-orchestrator`:

- ✅ `dev/postgres-data-modeling` — JSONB, GIN, pgvector, migraciones, snapshots
- ✅ `dev/concurrency-transactions` — SELECT FOR UPDATE, atomicidad, compensación
- ✅ `dev/event-driven` — EventBus, EventPublisherAdapter, naming, idempotencia
- ✅ `dev/inter-service-contracts` — DTOs, deserialización tolerante, reglas BFF
- ✅ `dev/control-orchestrator` — meta-skill orquestadora (dual-mode)

**Backlog** (5 skills aún en `pending` en sus ADRs): `dev/python-hex-audit`,
`dev/ai-agent-patterns`, `dev/llm-output-contract`, `dev/api-error-contract`,
`dev/ddd-tactical`. Ver `PROP-001` para contexto.

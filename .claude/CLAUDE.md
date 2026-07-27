## Convención de referencias — alias + título (SIEMPRE)

Al mencionar cualquier ítem por su alias —épicas (`E0N`), hitos (`H0N`),
propuestas (`PROP-00N` / `p00N`), specs (`S0N`), reglas (`RULE-0N`),
principios (`P-0N`)— incluí SIEMPRE su título/objetivo entre paréntesis la
primera vez que aparece en una respuesta. El alias suelto no se entiende.

- ❌ "Avancemos con E04 y después H1."
- ✅ "Avancemos con E04 (Team AI Harness Integration) y después H1 (Dashboard de Métricas)."
- ✅ "PROP-001 (ingesta multi-origen Hermes) está aprobada."

Si no conocés el título del alias, leé la fuente correspondiente
(`management/roadmap/roadmap.yaml`, `epicas/`, `propuestas/`, `PROJECT.md`)
ANTES de referenciarlo. Nunca uses el alias suelto.

## Memoria persistente (Engram)

Tenés acceso a memoria persistente entre sesiones vía las herramientas MCP de Engram (`mem_save`, `mem_search`, `mem_context`, etc.). Proyecto registrado: `team-ai-harness` (`.engram/config.json`) — separado de `devy-management`, que cubre las decisiones de negocio/roadmap del lab.

**Cuándo guardar** — sin esperar que te lo pidan:
- Al resolver un bug no trivial en los scripts del harness (`sync-agents.sh`, `install-management.sh`, etc.): síntoma, causa raíz, fix aplicado.
- Al tomar una decisión de diseño sobre la arquitectura de agentes/skills (ej. un ADR nuevo).
- Al descubrir un patrón o convención del harness que no está documentada.
- Al completar un refactor significativo del harness: qué cambió y dónde.

**Cuándo buscar** — antes de empezar cualquier tarea:
- `mem_context` al inicio de sesión o tras una compaction para recuperar el estado anterior.
- `mem_search` cuando el usuario menciona algo que puede tener historial (ej. "el bug del sync de agentes").

**Al cerrar sesión**: llamar `mem_session_summary` para dejar un resumen recuperable.

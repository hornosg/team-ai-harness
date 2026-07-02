# hornosg-team-ai — Harness de Agentes

Stack: Claude Code · OpenSpec · Engram (OpenCode dado de baja — docs/adr/ADR-001)

## Arquitectura

```
Owner
  └── @meta-router              ← único punto de entrada
        ├── @dev-orchestrator   ← L1-L4, equipo de desarrollo
        ├── @product-orchestrator
        └── @marketing-orchestrator
```

## Cómo usar

### Claude Code
```
@meta-router [pedido]
```

El meta-router clasifica, decide el ceremony level (dev), y arma la cadena de agentes.

## Equipos

### Orquestación (4 agentes)
| Agente | Rol |
|--------|-----|
| `meta-router` | Entry point. Clasifica dominio, rutea |
| `dev-orchestrator` | L1-L4 ceremony levels para dev |
| `product-orchestrator` | Ruteo por etapa de ciclo de producto |
| `marketing-orchestrator` | Ruteo por funnel |

### Dev (11 agentes)
| Agente | Rol |
|--------|-----|
| `dev-project-leader` | Qué y cuándo. Roadmap, épicas, prioridades |
| `dev-architect` | Decisiones estructurales, ADRs, patrones |
| `dev-technical-leader` | Cómo día a día. Reviews, mentoría |
| `dev-devops` | Plataforma. CI/CD, infra, secretos |
| `dev-security` | Threat modeling. **Obligatorio en L4** |
| `dev-senior-backend` | Features complejas E2E |
| `dev-junior-backend` | Features acotadas con guía |
| `dev-senior-frontend` | Flows complejos de cliente |
| `dev-junior-frontend` | Pantallas y componentes con specs |
| `dev-qa` | Calidad funcional. Sign-off antes de prod |
| `dev-monitoreo` | Producción: métricas, logs, alertas, SLOs |

### Producto (7 agentes)
| Agente | Rol |
|--------|-----|
| `product-leader` | Visión, roadmap, OKRs |
| `product-strategist` | Research, competencia, JTBD |
| `product-owner` | Backlog, historias, ACs |
| `product-ux-researcher` | Discovery, entrevistas, validación |
| `product-senior-designer` | Flows complejos, design system |
| `product-junior-designer` | Variaciones, mocks, adaptaciones |
| `product-analyst` | Métricas, funnels, retención |

### Marketing (10 agentes)
| Agente | Rol |
|--------|-----|
| `marketing-leader` | Estrategia, canales, presupuesto |
| `marketing-brand-strategist` | Posicionamiento, tono, mensajes core |
| `marketing-content-strategist` | Calendario, pilares, SEO de contenido |
| `marketing-senior-copywriter` | Landing, ads, onboarding, secuencias |
| `marketing-junior-copywriter` | Posts, captions, variaciones A/B |
| `marketing-senior-creative` | Piezas hero, video IA, dirección de arte |
| `marketing-junior-designer` | Adaptaciones por formato |
| `marketing-growth-marketer` | Paid media, SEO técnico, CRO |
| `marketing-community-manager` | Redes, respuestas, escucha social |
| `marketing-marketing-analyst` | Atribución, CAC, LTV, ROAS |

## Modelos por agente

Cada agente declara su modelo en el frontmatter (`model:`) y justifica la elección en una línea al inicio de su cuerpo (`> **Modelo:** ...`). Política: el modelo **necesario**, ni sub- ni sobredimensionado.

| Modelo | Cuándo | Agentes |
|--------|--------|---------|
| `claude-opus-4-8` | Razonamiento profundo (decisiones casi irreversibles, blast radius máximo) y juicio técnico/estratégico, análisis y escritura de alto impacto | `dev-architect`, `dev-security`, `dev-technical-leader`, `dev-project-leader`, `dev-devops`, `dev-qa`, `dev-monitoreo`, todos los leaders, strategists, analysts, owners, designers senior, copywriters/creatives senior |
| `codex/codex-5.5` | Generación de código (seniors y juniors de dev). Fallback Claude Code: `claude-sonnet-4-6` (Sonnet más nuevo disponible) | `dev-senior-backend`, `dev-senior-frontend`, `dev-junior-backend`, `dev-junior-frontend` |
| `claude-haiku-4-5-20251001` | Clasificación/ruteo, tareas acotadas Read-only, alto volumen y baja complejidad | `meta-router`, los 3 orchestrators, `product-junior-designer`, `marketing-junior-copywriter`, `marketing-junior-designer`, `marketing-community-manager` |

**Criterio:** los agentes que **escriben código** corren en `codex/codex-5.5`, con fallback a Claude `claude-sonnet-4-6` y override a Claude en L3/L4. Los juniors de diseño/copy de bajo riesgo usan haiku. Toda la capa de seniors no-código, leaders, TL, `dev-devops`, `dev-qa`, `dev-monitoreo`, analysts, strategists y owners usa `claude-opus-4-8`: el modelo más capaz para juicio técnico y estratégico, análisis cuantitativo y escritura de alto impacto.

`sync-agents.sh` valida que todo `model:` esté en la allowlist vigente y avisa si encuentra un string desconocido.

## SDD: proceso y artefacto

En este repo **SDD significa ambas cosas y se refuerzan mutuamente**:

| Sigla | Significado | Rol en el workflow |
|---|---|---|
| **SDD (proceso)** | **Specification-Driven Development** — primero se define el contrato/comportamiento, luego se programa. | Filosofía de trabajo: ninguna implementación L2+ arranca sin spec aprobada. |
| **SDD (artefacto)** | **System Design Document** — documento con contexto, arquitectura, decisiones y contratos. | La memoria externa del sistema: ADRs, `tasks.md`, plan atómico (`skills/dev/atomic-session-planning/SKILL.md`), workflow. |

Para un solo desarrollador con agentes, esta combinación evita *scope creep* y programar "de memoria". El agente actúa como implementador, pero la spec la decidimos antes.

## Flujo de Documentos

Quién genera qué. Cada documento tiene un dueño único.

```
Owner
  │
  ▼
[meta-router]
  ├─ DEV ──────────────────────────────────────────────────────────────────────────┐
  │                                                                                │
  │                                                                    PRODUCTO / CROSS
  │                                                              [product-orchestrator]
  │                                                                       │
  │                                                               [product-owner]
  │                                                               PROP-NNN.md ←── Spec de alto nivel
  │                                                                       │           │
  │                                                                  aprobada    rechazada
  ▼                                                                       │
[dev-orchestrator]                                                        │
  │ prerequisite validation                                               │
  │ (L4 sin spec → STOP)                                                  │
  │                                                                       ▼
  │                                                              [dev-orchestrator]
  │                                                              ENN epic en roadmap.yaml
  │                                                              roadmap/epicas/ENN-*.md
  │                                                                       │
  │                                  Story opcional (impacto de usuario)  │
  │                                  roadmap/stories/STOR-NNN.md          │
  │                                                                       │
  ├─ L3/L4 → [architect] ◄──────────────────────────────────────────────┘
  │            ADR-XX.md (docs/adr/)                                     │
  │            openspec/changes/[name]/tasks.md                          │
  │              └─ FILE-IDs (F-001…) + contratos                        │
  │              └─ TEST-IDs (T-001…) + security cases                   │
  │              └─ Documentation Plan                                   │
  │              └─ AI Context (L4)                                      │
  │                     │ entrega plan a                                  │
  │                     ▼                                                 │
  ├─ L2/L3 → [technical-leader] ◄──────────────────────────────────────┘
  │            openspec/changes/[name]/tasks.md
  │              └─ FILE-IDs (clave en L2, completo en L3)
  │              └─ TEST-IDs (happy paths en L2, completo en L3)
  │
  ▼
[senior-backend / senior-frontend]
  implementa FILE-IDs en orden:
  Domain → Application → Infrastructure → Presentation
  │
  ▼
[qa]
  verifica TEST-IDs: existen en código + pasan
  coverage matrix contra plan
  TEST-ID faltante → Critical → no merge
  │
  ▼
[technical-leader]
  code review 7 dimensiones (skills/dev/code-reviewer/SKILL.md)
  D1: FILE-IDs creados según plan
  D3: TEST-IDs implementados
  D4: layer boundaries respetadas
  D6: security checks
  Score /35 → APPROVED ≥30 | REVISIONS <25
  │
  └─ L4 → [security]
             OWASP Gate (skills/dev/owasp-top10/SKILL.md)
             contract boundaries
             threat model validado
             │
             ▼
            merge
```

### Ownership de documentos

| Documento | Dueño | Cuándo |
|-----------|-------|--------|
| `PROP-NNN.md` | `product-owner` | Discovery / idea nueva. Spec de alto nivel: problema, para quién, criterios de aceptación. |
| `roadmap/epicas/ENN-*.md` | `dev-orchestrator` / `product-orchestrator` | Propuesta aprobada. Spec de alcance: objetivo, stories opcionales, dependencias, ceremony level. |
| `roadmap/stories/STOR-NNN.md` | `product-owner` / `dev-orchestrator` | Cuando la épica impacta comportamiento observable del usuario. Opcional para trabajo técnico puro. |
| `roadmap/roadmap.yaml` | orchestrators | Al crear / actualizar épica |
| `docs/adr/ADR-XX.md` | `architect` | Decisión estructural L3/L4 |
| `openspec/changes/[name]/tasks.md` | `architect` (L3/L4) / `technical-leader` (L2/L3) | Antes de codear |
| `management/plans/<project>/<timestamp>_<slug>.md` | `dev-orchestrator` / owner | Plan atómico cross-project o multi-servicio (`skills/dev/atomic-session-planning/SKILL.md`). Vinculado desde épica/tasks. |
| FILE-IDs (F-NNN) | `architect` / `technical-leader` | En tasks.md |
| TEST-IDs (T-NNN) | `architect` / `technical-leader` | En tasks.md |
| Código | `senior-backend` / `senior-frontend` | Implementación |
| Reporte QA | `qa` | Antes del sign-off |
| Code Review | `technical-leader` | Cada PR L2+ |
| Security Report | `security` | L4 obligatorio |
| `PROJECT.md` | Owner (con ayuda de agentes) | Setup inicial + updates |

## Ceremony Levels (Dev)

| Nivel | Descripción | Agentes requeridos |
|-------|-------------|-------------------|
| L1 | Quick fix, reversible, < 30min | TL (opcional) + Junior |
| L2 | Feature estándar, patrones conocidos | TL + Senior + QA |
| L3 | Cambio arquitectural, migraciones | Architect + TL + Senior + QA + Monitoreo |
| L4 | Money / Auth / Compliance | **Architect + Security** + TL + Senior + QA + Monitoreo |

**Regla de oro**: L4 no se negocia. Keywords que lo fuerzan: pago, auth, token, wallet, BCRA, PCI.

## Pipelines Cross-Domain

```yaml
Feature Launch:  Product → Dev → Product (validation) → Marketing → Dev (deploy) → Product (measure)
Growth:         Product → Dev → Marketing → Product (measure)
Incident:       Dev (fix) → Product (impact) → Marketing (comms, si aplica)
New Segment:    Product (research) → Marketing (messaging) → Dev (gaps) → Marketing (campaign)
```

## Archivos

```
agents/           ← fuente canónica (editá aquí)
  orchestrators/
  dev/
  product/
  marketing/
.claude/agents/   ← generado (no editar directamente)
config/
  routing-rules.yaml
  ceremony-levels.yaml
  cross-domain-pipelines.yaml
openspec/
  changes/        ← specs en progreso (/opsx:propose)
  archive/        ← specs completadas
scripts/
  sync-agents.sh  ← re-genera plataformas desde canonical
```

## Workflows

### Modificar un agente
```bash
# 1. Editar el archivo canónico
vim agents/dev/architect.md

# 2. Sincronizar a Claude Code
./scripts/sync-agents.sh
```

### Nueva feature con OpenSpec
```
/opsx:propose [descripción de la feature]
```
Crea `openspec/changes/[nombre]/` con `proposal.md`, `specs/`, `design.md`, `tasks.md`.

## Memoria (Engram)

Instalación:
```bash
# macOS
brew install gentleman-programming/tap/engram

# Claude Code
claude plugin marketplace add Gentleman-Programming/engram && claude plugin install engram
```

Engram provee memoria persistente compartida entre todos los agentes y sesiones.
Los agentes usan `mem_save` para persistir decisiones importantes, ADRs, y contexto de proyecto.

## Documentos clave del workflow

- `docs/sdd-specification-driven.md` — marco SDD (proceso + artefacto) y Story.
- `docs/workflow-hexagonal-ddd.md` — flujo Go con `go-hex-audit`.
- `skills/dev/hexagonal-workflow/SKILL.md` — skill canónica del flujo Go.
- `.hermes/plans/INDEX.md` — planes atómicos vinculados.

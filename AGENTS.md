# hornosg-team-ai — Harness de Agentes

Stack: Claude Code · OpenCode · OpenSpec · Engram

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

### OpenCode
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
  │                                                               PROP-NNN.md ──── borrador
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
  code review 7 dimensiones (skills/dev/code-reviewer.md)
  D1: FILE-IDs creados según plan
  D3: TEST-IDs implementados
  D4: layer boundaries respetados
  D6: security checks
  Score /35 → APPROVED ≥30 | REVISIONS <25
  │
  └─ L4 → [security]
             OWASP Gate (skills/dev/owasp-top10.md)
             contract boundaries
             threat model validado
             │
             ▼
            merge
```

### Ownership de documentos

| Documento | Dueño | Cuándo |
|-----------|-------|--------|
| `PROP-NNN.md` | `product-owner` | Discovery / idea nueva |
| `roadmap/epicas/ENN-*.md` | `dev-orchestrator` / `product-orchestrator` | Propuesta aprobada |
| `roadmap/roadmap.yaml` | orchestrators | Al crear / actualizar épica |
| `docs/adr/ADR-XX.md` | `architect` | Decisión estructural L3/L4 |
| `openspec/changes/[name]/tasks.md` | `architect` (L3/L4) / `technical-leader` (L2/L3) | Antes de codear |
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
.opencode/agents/ ← generado (no editar directamente)
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

# 2. Sincronizar a Claude Code + OpenCode
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

# OpenCode
engram setup opencode
```

Engram provee memoria persistente compartida entre todos los agentes y sesiones.
Los agentes usan `mem_save` para persistir decisiones importantes, ADRs, y contexto de proyecto.

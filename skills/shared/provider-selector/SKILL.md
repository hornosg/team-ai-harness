---
name: provider-selector
description: Selecciona el provider y modelo óptimo (claude/codex/ollama) para un agente y tarea dados. Invocar cuando el ceremony level es L1/L2 ambiguo o cuando el meta-router necesita confirmar el provider antes de despachar.
triggers:
  - "/provider-selector"
  - "qué provider usar"
  - "qué modelo usar para"
  - "elegir provider"
  - "seleccionar modelo"
---

# Provider Selector

Determina el provider y modelo óptimo para una tarea, aplicando las reglas de `config/routing-rules.yaml → provider_routing` con su sistema de precedencia.

## Cuándo invocar

**Invocar cuando:**
- Ceremony level es L1 o L2 y el tipo de tarea no es obvio
- Meta-router necesita confirmar provider antes de despachar
- Tarea en dominio nuevo sin antecedentes en routing-rules
- Owner pide override explícito de provider

**NO invocar cuando:**
- Level es L3 o L4 → siempre Claude (bloqueado por `ceremony_overrides`)
- Keywords de money/auth/compliance presentes → `claude/claude-opus-4-8` inamovible
- Provider ya fue determinado por `ceremony_overrides` (L3/L4)

## Paso 1 — Leer configuración

```
config/routing-rules.yaml → sección provider_routing
```

Si no existe o no tiene `provider_routing`: usar defaults Claude (opus para L4, sonnet para L2/L3, haiku para L1 y orquestadores).

## Paso 2 — Clasificar tipo de tarea

| Tipo | Señales / keywords |
|------|--------------------|
| `code_generation` | nuevo endpoint, CRUD, feature, implementar, escribir código, refactor, fix de bug |
| `architecture` | diseño, ADR, bounded context, patrón, estructura, modelos de datos, diagrama |
| `security_review` | threat modeling, vulnerabilidad, superficie, PCI, OAuth, auth, credenciales |
| `classification` | rutear, clasificar, decidir qué agente, priorizar, categorizar |
| `analysis` | métricas, análisis, reporte, investigar, discovery, funnel, dashboard |
| `content` | copy, texto, descripción, documentación, PRD, landing, campaign |
| `infra` | deploy, CI/CD, Dockerfile, pipeline, secretos, cloud, DNS |

## Paso 3 — Aplicar precedencia

```
1. ¿Hay ceremony_override para este nivel + agente?
   → SÍ: usar ese modelo, saltar al Paso 5

2. ¿Hay agent_providers para este agente?
   → SÍ: usar ese provider como base, continuar al Paso 4

3. ¿Hay task_type_routing para este tipo de tarea?
   → SÍ y override:true  → obligatorio, saltar al Paso 5
   → SÍ y sin override   → preferido, puede ser sobreescrito por agent_provider
   → NO                  → usar claude como default
```

## Paso 4 — Seleccionar tier del modelo

Dado provider y complejidad de la tarea:

| Provider | Tier | Modelo | Cuándo |
|----------|------|--------|--------|
| claude | high | claude-opus-4-8 | L4, arquitectura irreversible, security |
| claude | medium | claude-sonnet-4-6 | L2/L3, análisis, reviews, estrategia |
| claude | low | claude-haiku-4-5-20251001 | L1, clasificación, ruteo |
| codex | default | codex-5.5 | cualquier task de `code_generation` |
| ollama | general | llama3.1 | clasificación, borradores, ruteo |
| ollama | code | qwen2.5-coder | fixes simples si se prefiere Ollama sobre Codex |

## Paso 5 — Emitir recomendación

```
PROVIDER:             [claude | codex | ollama]
MODEL:                [model-id — ej: codex-5.5 | llama3.1 | claude-sonnet-4-6]
CLAUDE_CODE_FALLBACK: [modelo Anthropic si provider != claude]
NIVEL_CONFIRMADO:     [L1 | L2]
TASK_TYPE:            [tipo detectado]
REASONING:            [una línea — por qué este provider/modelo para esta tarea]
ALTERNATIVA:          [provider/modelo si el principal no está disponible]
```

## Tabla de decisión rápida

| Tarea | Agente | Provider | Modelo |
|-------|--------|----------|--------|
| Nuevo CRUD / endpoint | senior-backend, junior-backend | codex | codex-5.5 |
| Fix de bug simple | junior-backend | codex | codex-5.5 |
| Nuevo componente / pantalla | senior-frontend, junior-frontend | codex | codex-5.5 |
| Refactor de módulo | senior-backend | codex | codex-5.5 |
| Diseño de arquitectura | architect | claude | claude-opus-4-8 |
| Clasificar pedido / ruteo | meta-router, orchestrators | ollama | llama3.1 |
| Review de PR | technical-leader | claude | claude-sonnet-4-6 |
| Diseño de tests | qa | claude | claude-sonnet-4-6 |
| Infra / CI/CD | devops | claude | claude-sonnet-4-6 |
| Análisis de métricas | product-analyst | claude | claude-sonnet-4-6 |
| Discovery / UX | ux-researcher, product-strategist | claude | claude-sonnet-4-6 |
| Copy estratégico | senior-copywriter, brand-strategist | claude | claude-sonnet-4-6 |
| Posts / captions / borrador | junior-copywriter, community-manager | ollama | llama3.1 |

## Casos edge

**Provider no disponible:**
Jerarquía de fallback: `codex → claude-sonnet-4-6 → ollama/llama3.1`.
Indicar en `ALTERNATIVA` y notificar al owner.

**Tarea mixta — código + decisiones de arquitectura:**
Separar en dos pedidos. La parte de arquitectura siempre va a `claude/claude-opus-4-8`, aunque el resto sea codex.

**Override manual del owner:**
Aceptar. Documentar en `REASONING: override manual por owner — [razón]`. No bloquear.

**Sin `provider_routing` en routing-rules.yaml:**
Usar defaults Claude: orchestrators → `claude-haiku-4-5-20251001`, implementadores → `claude-sonnet-4-6`, decisiones críticas → `claude-opus-4-8`.

**Tarea L1 con urgencia y Ollama no disponible:**
Fallback a `claude-haiku-4-5-20251001`. No degradar a un provider sin disponibilidad confirmada.

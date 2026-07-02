# ADR-001: Instalación única del harness a nivel laboratorio (DEVY_PATH)

**Estado:** Aceptada
**Fecha:** 2026-07-02
**Decisor:** owner (hornosg)
**Contexto de origen:** sesión de reorganización post-E33 (Loops autónomos) y post-consolidación
del roadmap único (2026-07-02)

## Contexto

Hasta hoy el harness se instalaba **por repositorio** (`install-management.sh` copiaba
`management/` + `.claude/agents/` + `.opencode/agents/` dentro de cada proyecto). Eso produjo:

- **Drift**: 6 copias del harness (iteye, mercado-cercano, iam-service, riotless, whatsappAgent,
  más la instancia del lab) desincronizadas entre sí y respecto de la fuente canónica.
- **Repos de código sucios**: artefactos generados (`.claude/agents/`, `.opencode/`) y directorios
  de gestión (`management/`) y marketing (`marketing/`) versionados dentro de repos de producto —
  exactamente el problema que PROP-006 intentaba resolver por proceso.
- **Roadmaps fragmentados**: un `roadmap.yaml` por proyecto (ya resuelto el 2026-07-02 con el
  roadmap único multi-proyecto).
- **Ambigüedad de scope por cwd**: el piloto de E33/T7 demostró que inferir el proyecto desde el
  working directory falla cuando el loop corre dentro del repo de un servicio.

Además el owner probó **OpenCode** como runtime alternativo y decidió descartarlo.

## Decisión

### 1. Una sola instalación, en la raíz del laboratorio

El harness se instala **una única vez** en `$DEVY_PATH` (hoy `/Users/hornosg/Projects`).
Ningún repo de proyecto vuelve a tener `management/`, `marketing/`, `.claude/agents/` ni
`.opencode/` propios. Toda sesión de trabajo (interactiva o loop) se lanza desde `$DEVY_PATH`.

### 2. Tres variables de entorno como contrato de ubicación

Definidas en `~/.zshrc`; todo agente/skill/script del harness resuelve rutas a través de ellas,
nunca hardcodeadas:

| Variable | Valor actual | Qué es |
|----------|--------------|--------|
| `DEVY_PATH` | `~/Projects` | Raíz del lab; el harness vive en `$DEVY_PATH/.claude/` (generado) |
| `DEVY_ROADMAP_PATH` | `~/Projects/management/roadmap.yaml` | Roadmap ÚNICO multi-proyecto (cada hito/épica lleva `proyecto:`) |
| `DEVY_MARKETING_PATH` | `~/Projects/marketing` | Marketing ÚNICO multi-proyecto (`<proyecto>/` por subdirectorio) |

### 3. Dos fuentes de verdad centralizadas (repos privados)

- **Gestión** → `hornosg/devy-management` (`$DEVY_PATH/management/`): roadmap único, PROJECT.md
  del lab, instancia del harness (agents/skills/config/rules), y por proyecto:
  `projects/<nombre>/{PROJECT.md, epicas/, propuestas/, specs/, plans/, docs/}`.
- **Marketing** → `hornosg/devy-marketing` (`$DEVY_PATH/marketing/`): un subdirectorio por
  proyecto con todo su material de marketing (personas, copy, brand, assets, legal, templates).

**Regla operativa anti-SPOF (elegida por el owner):** ambos repos concentran todo el estado de
gestión/marketing del lab — la mitigación es **disciplina de commit + push constante**, no
estructura. Un incidente real de pérdida de datos (2026-07-02, `git checkout` sobre contenido
sin commitear) motivó esta regla.

### 4. Carga de contexto por cadena de punteros

`management/projects/<nombre>/PROJECT.md` es la pieza nueva: declara **dónde vive el código** del
proyecto (hoy `$DEVY_PATH/active/<p>`, mañana `~/develop/<p>` — se edita solo ahí), el **índice de
componentes/subrepos** (ej. mercado-cercano → pim, sales, stock, … con path y puerto), y el
puntero a su marketing. El meta-router nunca infiere ubicaciones: las lee.

```
claude   (lanzado desde $DEVY_PATH; sin tokens Anthropic: claude --model kimi-k2.7-code:cloud)
  │
  ├─ /lab-status ────────► lee $DEVY_ROADMAP_PATH → árbol hitos→épicas por proyecto
  │
  └─ @meta-router <pedido> | next-task --proyecto <p>
       │
       Paso 0 — contexto por punteros (nunca copias):
       ① management/PROJECT.md                    identidad lab, RULE/SVC/STACK
       ② $DEVY_ROADMAP_PATH                       roadmap único → filtrar proyecto:
       ③ si proyecto ≠ platform:
       │    management/projects/<p>/PROJECT.md    → dónde vive el código, índice de
       │                                            componentes/subrepos, puntero marketing
       ④ épica activa → archivo: → tareas atómicas [ ]
       ⑤ clasifica dominio y rutea:
       │    dev       → @dev-orchestrator (ceremony L1-L4)
       │    marketing → @marketing-orchestrator → trabaja en $DEVY_MARKETING_PATH/<p>/
       │    producto  → @product-orchestrator
       ⑥ implementación: opera sobre el código en el path que declaró el PROJECT.md del proyecto
       ⑦ cierre: [x] en épica + estado en roadmap único + mem_session_summary (Engram)
```

### 5. Árbol objetivo

```
$DEVY_PATH = ~/Projects                        ← harness instalado UNA sola vez acá
├── CLAUDE.md                                  ← guía del lab
├── .claude/                                   ← GENERADO por sync (agents + skills + /lab-status)
├── management/            [hornosg/devy-management — GESTIÓN única]
│   ├── roadmap.yaml       ← $DEVY_ROADMAP_PATH — índice ÚNICO (proyecto: en cada hito/épica)
│   ├── PROJECT.md         ← identidad del lab Devy (P/G/RULE/STACK/SVC)
│   ├── agents/ skills/ config/ rules/ scripts/   ← instancia del harness (fuente de ../.claude/)
│   ├── platform/          ← epicas/ propuestas/ docs/adr/ plans/ del lab
│   └── projects/<nombre>/
│       ├── PROJECT.md     ← puntero al código + índice de componentes + puntero marketing
│       └── epicas/ propuestas/ specs/ plans/ docs/
├── marketing/             [hornosg/devy-marketing — MARKETING único]
│   ├── README.md
│   └── <proyecto>/        ← mercado-cercano/ whatsapp-agent/ riotless/ …
├── active/ platform/ pocs/ infra/ observability/
│   └── <repos de código LIMPIOS>
└── active/team-ai-harness/    [fuente canónica upstream + este ADR]
```

### 6. Política de modelos (Anthropic-first, kimi como fallback manual)

| Tier | Modelo | Agentes |
|------|--------|---------|
| Ruteo | `claude-haiku-4-5-20251001` | meta-router, orquestadores, juniors de marketing/diseño, community-manager |
| Implementación | `claude-sonnet-5` | seniors y juniors de dev (backend/frontend) |
| Crítico | `claude-opus-4-8` | architect, security, technical-leader, leaders, estrategia, QA, monitoreo |

Codex (OpenAI) sale de la matriz. Ollama queda SOLO como **fallback manual de emergencia**: cuando
el owner agota tokens Anthropic, relanza con
`claude --dangerously-skip-permissions --model kimi-k2.7-code:cloud` — el backing pasa a ser
global (kimi) y el detalle de ejecución de los artefactos sube a `reforzado`
(ver `config/routing-rules.yaml → capability_tiers`). L4 nunca se auto-ejecuta sobre ese backing.

### 7. Baja de OpenCode

El adapter OpenCode deja de generarse (`sync-agents.sh` default `ADAPTERS=(claude)`); los
`.opencode/` existentes se eliminan. El código del adapter queda en el script como opción
comentada por si se retoma.

## Consecuencias

**Beneficios**: cero drift (una sola copia que actualizar); repos de código limpios (resuelve
PROP-006 por construcción); una sesión ve todo el lab — ideal para operación unipersonal;
contexto barato por punteros; los `CLAUDE.md` anidados de cada repo se siguen cargando lazy
porque `$DEVY_PATH` es ancestro de todos.

**Costos**: `devy-management`/`devy-marketing` como SPOF (mitigación: commit+push constante);
historia git entrelazada entre proyectos (extraíble por path si un proyecto se independiza);
assets binarios de marketing engordan el repo (evaluar Git LFS si crece).

**Riesgos asumidos por el owner**: sesión única con acceso a todo el lab +
`--dangerously-skip-permissions` en loops = blast radius total (decisión explícita, ver E33);
el cwd deja de ser señal de proyecto → `--proyecto` explícito obligatorio en loops.

**Efectos sobre el roadmap**: H3 (Gobernanza operativa del lab) queda para revisión — PROP-005 y
PROP-006 probablemente resueltas por construcción con este ADR.

## Referencias

- E33 (Loops autónomos de agentes) — `devy-management: platform/epicas/E33-agent-loops-harness.md`
- ADR-001 de devy-management (estructura de gestión centralizada, 2026-06-30) — antecedente directo
- PROP-005 / PROP-006 (gobernanza, probablemente superseded)
- Consolidación del roadmap único (2026-07-02, commit `e6c752f` de devy-management)

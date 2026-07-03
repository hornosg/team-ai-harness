# Team AI Harness

> A multi-team AI agent harness for development, product, and marketing — built for Claude Code.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-compatible-blue)](https://claude.ai/code)

---

## What is this?

A ready-to-use harness of **32 specialized AI agents** organized across three teams (Dev, Product, Marketing) with a central routing layer. You install it ONCE at the root of your multi-project workspace and get:

- A single entry point (`@meta-router`) that classifies every request and routes it to the right agent chain
- Ceremony levels (L1–L4) that enforce appropriate rigor based on risk — L4 for anything touching money, auth, or compliance is non-negotiable
- Spec-driven development with FILE-ID / TEST-ID traceability from plan to code to test
- Persistent memory across sessions via [Engram](https://github.com/Gentleman-Programming/engram)
- Canonical source in `agents/` generates Claude Code format (`.claude/agents/`); non-Claude adapters are not maintained

---

## Architecture

```
Owner
  └── @meta-router                  ← single entry point
        ├── @dev-orchestrator        ← L1–L4 ceremony levels
        │     ├── @dev-architect
        │     ├── @dev-technical-leader
        │     ├── @dev-senior-backend / @dev-senior-frontend
        │     ├── @dev-qa
        │     └── @dev-security      ← mandatory on L4
        ├── @product-orchestrator
        │     ├── @product-owner
        │     ├── @product-strategist
        │     └── @product-analyst
        └── @marketing-orchestrator
              ├── @marketing-senior-copywriter
              ├── @marketing-growth-marketer
              └── @marketing-brand-strategist
```

**32 agents total.** See [AGENTS.md](AGENTS.md) for the full roster with roles, models, and tools.

---

## Key Features

- **Ceremony levels** — L1 (quick fix) to L4 (money/auth/compliance). Each level defines which agents are required, what planning is mandatory, and what can't be skipped.
- **FILE-ID / TEST-ID system** — every planned file gets a traceable ID. Every test maps to a FILE-ID. The code reviewer verifies this mechanically before merge.
- **Cross-domain pipelines** — launch a feature, run a growth initiative, or manage an incident across Product → Dev → Marketing with a single `@meta-router` command.
- **Roadmap integration** — agents read the single multi-project `management/roadmap.yaml` (`$DEVY_ROADMAP_PATH`) to contextualize requests. `@meta-router status` crosses roadmap + proposals + specs into one report.
- **Adapter sync** — one canonical source in `agents/` generates Claude Code output (`.claude/agents/`).
- **Persistent memory** — all senior agents use [Engram](https://github.com/Gentleman-Programming/engram) to persist architectural decisions, bug resolutions, and session context across conversations. The installer wires Engram MCP into `.claude/settings.local.json` automatically.
- **Atomic session planning** — multi-step or cross-service work is broken into single-session, verifiable tasks with explicit dependencies and Engram handoffs (`skills/dev/atomic-session-planning/SKILL.md`).
- **Emergency fallback** — when Anthropic tokens run out, relaunch on Kimi K2 (Ollama Cloud) without code changes. Artifact granularity auto-adjusts via `Detalle de ejecución`.

---

## Model policy + emergency fallback (kimi)

Default policy (ADR-001): **Anthropic-first** — haiku for routing, sonnet for implementation, opus for critical/L3-L4 (`config/routing-rules.yaml → agent_providers`). When Anthropic tokens run out, relaunch the session with `claude --model kimi-k2.7-code:cloud`; the backing becomes global (kimi) and artifact detail rises to `reforzado`.

### Capability tiers

| Tier | Models | Artifact detail |
|------|--------|-----------------|
| `frontier` | `claude-opus-4-8`, `claude-sonnet-5`, `claude-haiku-4-5-20251001` | `estándar` — model fills in reasonable context |
| `open_mid` | `kimi-k2.7-code:cloud` (manual emergency fallback) | `reforzado` — tasks must be atomic and self-contained |

**Rule**: the lower the model capacity, the higher the artifact explicitness. `reforzado` means every epic task must include an `Objetivo:` (exact path), a `Hecho cuando:` (observable result), and optionally a `Contrato:` (exact signature, required in L3/L4).

### Detalle de ejecución

Epics and proposals carry a `Detalle de ejecución: estándar | reforzado` field. This is orthogonal to ceremony level:

- **`estándar`** — frontier models (Claude opus/sonnet/haiku). Natural language tasks are fine; the model fills context gaps.
- **`reforzado`** — open-model fallback (kimi). Every task is atomic:

```markdown
- [ ] **T1 · [verb + concrete object]**
      Objetivo: `exact/path/to/file`
      Hecho cuando: `go test ./...` → green (or observable check)
      Depende de: ninguna
      Contrato: `func Name(ctx context.Context, id string) (Entity, error)`  ← L3/L4 only
```

### Runtime behavior

Under Claude Code with the native Anthropic backend, each agent's frontmatter `model:` is
respected — the haiku/sonnet/opus matrix applies per agent. Under the kimi fallback
(`claude --model kimi-k2.7-code:cloud`) the backing model is GLOBAL: every agent runs kimi,
per-agent routing is ignored, and quality depends on artifact self-sufficiency (`reforzado`).

**L4 on the kimi fallback**: architect and security require frontier reasoning — L4 does NOT
auto-execute; it is flagged and escalated to the human operator.

---

## Loop mode

The harness can run **unattended iterations** — a driver that repeatedly invokes
`@meta-router next-task` with fresh context per iteration, until the backlog is exhausted
or a safety limit is hit.

### When to use it

- **Mechanical work with an already-designed pattern** — e.g. applying the same security
  retrofit across a fleet of services, one epic per service, same checklist. The epics/tasks
  already exist in `roadmap.yaml`; the loop just executes them one at a time.
- Tasks must already be atomic (`skills/dev/atomic-session-planning`) with a verifiable
  `Hecho cuando` — the loop does not invent scope.

### When NOT to use it

- **Learning-by-doing work** — e.g. a Kubernetes migration where the explicit goal is that the
  user learns the tooling by doing it. A loop that generates the manifests destroys that
  value. Check the epic/proposal for this kind of intent before looping over it.
- Work without a clear atomic breakdown yet — plan first (`atomic-session-planning`), loop
  second.

### How it works

1. `scripts/loop-runner.sh` invokes `claude -p "@meta-router next-task" --max-turns 40` in a
   loop, each call starting with **fresh context** (no conversation history carried over).
2. `next-task` (`skills/shared/loop-next-task/SKILL.md`) picks the first unblocked `[ ]` task
   of the active epic, executes it per its ceremony level, verifies `Hecho cuando`, marks
   `[x]`, updates `roadmap.yaml`, and closes with `mem_session_summary`.
3. The runner stops on any of:
   - Backlog empty (`NEXT-TASK: empty` reported by the skill).
   - Kill-switch file `.loop-stop` present in the target repo root.
   - **2 consecutive iterations with no `[x]` change** in `roadmap.yaml`/epic files — checked
     by hashing those files between iterations, not by trusting agent self-report.

### Budget — governed by context, not iteration count

- **One task per iteration, always.** On task close: checkpoint (`mem_session_summary` +
  epic state on disk) and restart with clean context, even if the context window still had
  headroom.
- **Checkpoint at ~50% of the context window (≈100k tokens)** if the task hasn't closed: a
  structured intermediate summary (done / missing / concrete next step); the next iteration
  resumes from there.
- **`--max-turns 40`** is the runner-side proxy for this budget.
- **Anti-insistence**: if the same task survives 3 iterations without closing, it wasn't
  atomic — the loop returns it to replanning (`atomic-session-planning`) instead of grinding
  on it further.

### L4 semantics in loop mode — never unattended

`config/routing-rules.yaml → loop_mode` is the source of truth. Summary: an L4 task
(`l4_keywords` — money, auth, identity, compliance) is implemented up to the gate
(build/test green), the escalation is written to `management/escalations/YYYY-MM-DD_<slug>.md`
+ Engram, and **the iteration does not commit without explicit human sign-off**. This is
"escalate and continue" — the loop does not halt the whole run, it just moves to the next
unblocked task on the next iteration.

### Permissions — required before running

The loop runs `claude -p` unattended. By default it expects a non-interactive environment where
permission prompts would stall execution, so the caller must explicitly opt into unattended
operation. Risk is assumed by the human operator, not auto-decided by the loop.

- The kill-switch (`touch .loop-stop` in the target repo root) is the manual emergency stop —
  check it works before leaving a loop unattended for long stretches.
- L4 tasks still never commit unattended (see `loop_mode` above) — that guardrail stays in
  force regardless of the permission mode.

### Plugins in loop mode

User-level Claude Code plugins (superpowers, code-review, context7, engram, playwright, …)
inject their hooks and skills into every headless iteration too — they can't be turned off
per-iteration, so they are governed by policy instead. Source of truth:
`config/routing-rules.yaml → loop_mode.plugins`. Summary:

- **Precedence**: the loop protocol (`loop-next-task`) overrides any plugin mandate —
  including superpowers' "invoke skills before any response" when the skill is interactive.
- **Allowed**: `engram` (required — the inter-iteration handoff depends on it), `context7`
  (one-shot library doc lookups), passive guidance skills, and superpowers' non-interactive
  process skills (`verification-before-completion`, `systematic-debugging`,
  `test-driven-development`).
- **Forbidden**: anything that dialogues with the user (`superpowers:brainstorming`),
  spawns subagents (`dispatching-parallel-agents`, `subagent-driven-development` — they blow
  the `--max-turns 40` budget), or opens a browser (`playwright`, `claude-in-chrome` — hang
  risk in headless).
- **Overlap**: when a plugin duplicates a harness skill (`code-review` vs `code-reviewer`,
  `security-guidance` vs `owasp-top10`), the harness skill always wins — it's the one the
  ceremony gates reference.
- **Interactive attempt = blocked task**: checkpoint and continue; never wait for input.

### Usage

```bash
cd /path/to/target-repo   # must have management/<scope>/roadmap.yaml
/path/to/team-ai-harness/scripts/loop-runner.sh --dry-run   # validates driver, no execution
/path/to/team-ai-harness/scripts/loop-runner.sh              # runs until stop condition
touch .loop-stop                                              # emergency stop
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Node.js | ≥ 20.19.0 | [nodejs.org](https://nodejs.org) |
| Claude Code | latest | `npm install -g @anthropic-ai/claude-code` |
| OpenSpec | latest | `npm install -g @fission-ai/openspec@latest` |
| Engram | latest | `brew install gentleman-programming/tap/engram` |

### Engram MCP setup

Engram es el motor de memoria persistente del harness. **Instalalo una sola vez** en la máquina:

```bash
brew install gentleman-programming/tap/engram
```

Luego, `./scripts/install-management.sh /path/to/project` configura automáticamente el MCP de Engram en `.claude/settings.local.json` del proyecto destino. Si instalás Engram después del harness, ejecutá:

```bash
python3 management/scripts/merge-claude-settings.py .
```

---

## Quick Start

> **Installation model (ADR-001, 2026-07-02): ONE install per lab, not per repo.**
> The harness is installed a single time at the root of your multi-project lab (`$DEVY_PATH` —
> the directory that contains all your project repos). Code repos stay clean: no `management/`,
> no generated `.claude/agents/` inside them. All work sessions launch from `$DEVY_PATH`;
> `@meta-router` resolves the target project and loads its context via pointers
> (`management/projects/<name>/PROJECT.md` → code location). See
> [`docs/adr/ADR-001-instalacion-unica-lab-level.md`](docs/adr/ADR-001-instalacion-unica-lab-level.md).

### Install at the lab root

```bash
git clone https://github.com/<your-org>/team-ai-harness
cd team-ai-harness
./scripts/install-management.sh /path/to/your-lab-root   # e.g. ~/Projects
```

This creates a `management/` folder at the lab root with all agents, skills, rules, the single
multi-project roadmap template, and a root `CLAUDE.md` that points to `management/CLAUDE.md`.
Then define the environment contract in your shell profile:

```bash
export DEVY_PATH="$HOME/Projects"                                   # lab root
export DEVY_ROADMAP_PATH="$DEVY_PATH/management/roadmap.yaml"       # single roadmap
export DEVY_MARKETING_PATH="$DEVY_PATH/marketing"                   # single marketing repo
```

Then open Claude Code at the lab root:

```bash
cd $DEVY_PATH && claude
```

```
@meta-router I need to add payment processing to the checkout flow
```

---

## First Steps After Install

1. **Fill in `management/PROJECT.md`** — project identity, stack, services, principles. Agents read this as ground truth.
2. **Complete `management/roadmap.yaml`** — the single multi-project roadmap (every milestone/epic carries a `proyecto:` field; see docs/adr/ADR-001). Ask `@meta-router crear epica [X]` if you're starting fresh.
3. **Check the status** — `@meta-router status` gives a full report crossing roadmap + proposals + specs.

---

## Ceremony Levels

| Level | When | Required agents |
|-------|------|----------------|
| L1 | Quick fix, reversible, < 30 min | Junior + TL (optional) |
| L2 | Standard feature, known patterns | TL + Senior + QA |
| L3 | Architectural change, DB migration | Architect + TL + Senior + QA + Monitoring |
| **L4** | **Money / Auth / Compliance** | **Architect + Security (both, non-negotiable)** + TL + Senior + QA + Monitoring |

**L4 triggers** (hardcoded, can't be downgraded): payment, auth, token, wallet, session, PCI, compliance.

---

## Document Flow

Each document has exactly one owning agent:

| Document | Owner agent | When |
|----------|-------------|------|
| `PROP-NNN.md` (proposal) | `product-owner` | New idea / discovery |
| `roadmap/epicas/ENN-*.md` | orchestrators | Proposal approved |
| `docs/adr/ADR-XX.md` | `architect` | Structural decision L3/L4 |
| `openspec/changes/[name]/tasks.md` | `architect` (L3/L4) / `technical-leader` (L2/L3) | Before coding |
| FILE-IDs (F-NNN) + TEST-IDs (T-NNN) | same as tasks.md owning agent | Inside tasks.md |
| Code | `senior-backend` / `senior-frontend` | Implementation |
| QA report | `qa` | Before sign-off |
| Code review | `technical-leader` | Every PR L2+ |
| Security report | `security` | L4 mandatory |

See [AGENTS.md](AGENTS.md) for the full flow diagram.

---

## FILE-ID / TEST-ID System

Every planned file gets a unique FILE-ID. Every test maps to a FILE-ID. The code reviewer verifies mechanically before merge.

```markdown
## FILE-ID Table
| FILE-ID | Path | Action | Layer | Description |
|---------|------|--------|-------|-------------|
| F-001   | src/domain/model/order.ts | CREATE | Domain | Order aggregate |
| F-002   | src/application/usecase/place-order.ts | CREATE | Application | Place order use case |

## TEST-ID Table
| TEST-ID | FILE-ID | Type | Scenario | Expected |
|---------|---------|------|----------|----------|
| T-001 | F-001 | Unit | Create order with valid data | Order with UUID |
| T-002 | F-001 | Unit | Create with invalid amount | ValidationError |
| T-003 | F-002 | Unit | Execute with duplicate | ConflictError |
```

If T-NNN doesn't exist in code → Critical finding → no merge.

---

## Cross-Domain Pipelines

```
@meta-router launch feature [X]
```

Runs automatically: `Product (define) → Dev (implement) → Marketing (launch) → Product (measure)`

| Pipeline | Sequence |
|----------|----------|
| Feature launch | Product → Dev → Product (validation) → Marketing → Dev (deploy) → Product (metrics) |
| Growth initiative | Product → Dev → Marketing → Product (measure) |
| Production incident | Dev (fix) → Product (impact) → Marketing (comms if needed) |
| New segment | Product (research) → Marketing (messaging) → Dev (gaps) → Marketing (campaign) |

---

## Modifying Agents

Canonical sources live in `agents/`. Generated files in `.claude/agents/` are **never edited directly**.

```bash
# Edit canonical source
vim agents/dev/architect.md

# Sync to Claude Code
./scripts/sync-agents.sh

# Dry run
./scripts/sync-agents.sh --dry-run
```

---

## Repository Structure

```
team-ai-harness/
├── agents/                        ← canonical source (edit here)
│   ├── orchestrators/             ← meta-router, dev/product/marketing orchestrators
│   ├── dev/                       ← 11 dev agents
│   ├── product/                   ← 7 product agents
│   └── marketing/                 ← 10 marketing agents
├── skills/                        ← cada skill es un directorio con SKILL.md
│   ├── dev/                       ← code-reviewer/, planner/, owasp-top10/, hexagonal-{go,python,flutter}/,
│   │                                 kong/, prometheus/, grafana/, loki/, tracing/, observability-stack/, digital-ocean/, ...
│   ├── marketing/                 ← market-audit/, market-seo/, market-copy/, ...
│   └── shared/                    ← bmad-*/, roadmap-management/, roadmap-status/
├── rules/                         ← architecture, api-standards, security (adapter-ready)
├── adapters/                      ← format transforms per AI tool
├── roadmap/
│   ├── roadmap.yaml               ← milestones + epics
│   ├── epicas/                    ← ENN-*.md templates
│   └── propuestas/                ← PROP-NNN-*.md templates
├── config/
│   ├── routing-rules.yaml
│   ├── ceremony-levels.yaml
│   └── cross-domain-pipelines.yaml
├── scripts/
│   ├── sync-agents.sh             ← generates adapter outputs
│   ├── install-management.sh      ← installer for any project
│   └── validate-artifacts.py      ← conformance checker (routing + templates + reforzado epics)
├── .claude/agents/                ← generated for Claude Code
├── AGENTS.md                      ← full agent roster + flow diagram
└── PROJECT.md                     ← project identity template
```

---

## Validation

`scripts/validate-artifacts.py` checks harness conformance without running any agent. It requires only Python 3 (and optionally PyYAML for richer YAML checks).

```bash
# Validate the canonical harness (config + templates + all reforzado epics found)
python3 scripts/validate-artifacts.py

# Validate a specific installed management/ folder
python3 scripts/validate-artifacts.py /path/to/project/management

# Validate specific epic files only
python3 scripts/validate-artifacts.py --epics roadmap/epicas/E10.md roadmap/epicas/E18.md
```

**What it checks:**

| Check | What passes |
|-------|-------------|
| `config/routing-rules.yaml` | Has `model_resolution`, `capability_tiers`, and declares `hermes` + `kimi` under ollama |
| Epic template | Has `## Contexto a cargar`, `Detalle de ejecución`, and `Hecho cuando` |
| Proposal template | Has `Detalle de ejecución` |
| Reforzado epics | Every task in `## Tareas` has `Objetivo:` and `Hecho cuando:` |

Exit 0 = all pass. Exit 1 = one or more failures (CI-safe).

---

## Skills Reference

| Category | Skill | Purpose |
|----------|-------|---------|
| Dev | `planner` | Generate FILE-IDs + TEST-IDs before coding |
| Dev | `code-reviewer` | 7-dimension PR review with score /35 |
| Dev | `conventional-commit` | Commit format and enforcement |
| Dev | `pr-workflow` | PR best practices and size limits |
| Dev | `owasp-top10` | OWASP Top 10:2021 gate + audit |
| Dev | `memory-protocol` | When and how to use Engram |
| Marketing | `market-audit` | Full market analysis via WebFetch |
| Marketing | `market-competitors` | Competitor scanning + comparison matrix |
| Marketing | `market-seo` | SEO checklist + local optimization |
| Marketing | `market-copy` | Copy review and improvement |
| Marketing | `market-landing-cro` | Landing page conversion optimization |
| Shared | `bmad-brainstorming` | 100+ ideas, anti-bias rotation |
| Shared | `bmad-distillator` | Lossless document compression |
| Shared | `bmad-party-mode` | Multi-agent discussion simulation |
| Shared | `bmad-editorial-review-structure` | Document structure analysis |
| Shared | `bmad-editorial-review-prose` | Clinical copy editing |
| Shared | `bmad-review-adversarial` | Cynical reviewer, minimum 10 findings |
| Shared | `roadmap-management` | Create proposals, epics, update roadmap |
| Shared | `roadmap-status` | Full status report: roadmap + proposals + specs |
| Shared | `provider-selector` | Select optimal provider+model for any agent/task combination |
| Hexagonal | `hexagonal-go` | Hexagonal + DDD para Go (Chi/pgx/Wire) |
| Hexagonal | `hexagonal-python` | Hexagonal + DDD para Python (FastAPI/SQLAlchemy async) |
| Hexagonal | `hexagonal-flutter` | Clean Architecture + DDD para Flutter (BLoC/Riverpod) |
| Stack | `kong` | API Gateway: routing declarativo (decK), plugins, DB-less, seguridad del borde |
| Stack | `prometheus` | Métricas, golden signals, PromQL, alerting |
| Stack | `grafana` | Dashboards, SLOs, dashboards-as-code, correlación de señales |
| Stack | `loki` | Logging estructurado (JSON), LogQL, pipeline de ingestión |
| Stack | `observability-stack` | Visión integral Prometheus + Grafana + Loki; flujo de diagnóstico |
| Stack | `tracing` | Tracing distribuido: OpenTelemetry + Grafana Tempo, propagación W3C |
| Stack | `digital-ocean` | Deploy e infra: App Platform/Droplets, doctl, VPC, managed DB, Spaces, costos |

---

## Credits

### Engram — Persistent Memory for AI Agents

This harness relies on **[Engram](https://github.com/Gentleman-Programming/engram)** by **[Gentleman Programming](https://github.com/Gentleman-Programming)** for persistent memory across agent sessions and chat compactions.

Engram provides a single binary (zero dependencies) backed by SQLite + FTS5, exposed as an MCP server. It enables any MCP-compatible agent — Claude Code, Cursor, Copilot, Gemini CLI — to remember architectural decisions, bug resolutions, and session context indefinitely.

```bash
brew install gentleman-programming/tap/engram
```

> Give them a star: [github.com/Gentleman-Programming/engram](https://github.com/Gentleman-Programming/engram)

### OpenSpec

Spec-driven development framework by [Fission AI](https://github.com/fission-ai). Provides the `openspec/changes/` structure used by the planner skill and all L2+ ceremony workflows.

```bash
npm install -g @fission-ai/openspec@latest
```

### Claude Code

Agent runtime by [Anthropic](https://anthropic.com). The `.claude/agents/` format and subagent invocation pattern (`@agent-name`) are Claude Code conventions.

---

## Contributing

Contributions welcome. A few conventions to keep the harness portable:

- **No project-specific content in agents** — agents must work for any project. Project identity lives in `PROJECT.md`, not in agent files.
- **Skills are documents, not commands** — skills live in `skills/<name>/SKILL.md` and are read by agents. They don't go in `.claude/commands/`.
- **Canonical source in `agents/`** — never edit generated files in `.claude/agents/` directly.
- **L4 is non-negotiable** — don't add exceptions or workarounds for money/auth/compliance ceremony requirements.

To add a new agent:

```bash
# 1. Create canonical file
vim agents/dev/my-new-agent.md   # with proper frontmatter

# 2. Sync
./scripts/sync-agents.sh

# 3. Add to AGENTS.md roster table
```

---

## License

MIT © 2025 hornosg

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

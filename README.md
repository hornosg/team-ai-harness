# Team AI Harness

> A multi-team AI agent harness for development, product, and marketing — built for Claude Code, OpenCode, Cursor, and GitHub Copilot.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-compatible-blue)](https://claude.ai/code)
[![OpenCode](https://img.shields.io/badge/OpenCode-compatible-green)](https://opencode.ai)

---

## What is this?

A ready-to-use harness of **32 specialized AI agents** organized across three teams (Dev, Product, Marketing) with a central routing layer. You install it once into any project's `management/` folder and get:

- A single entry point (`@meta-router`) that classifies every request and routes it to the right agent chain
- Ceremony levels (L1–L4) that enforce appropriate rigor based on risk — L4 for anything touching money, auth, or compliance is non-negotiable
- Spec-driven development with FILE-ID / TEST-ID traceability from plan to code to test
- Persistent memory across sessions via [Engram](https://github.com/Gentleman-Programming/engram)
- Multi-adapter sync: same canonical agents generate Claude Code, OpenCode, Cursor, and Copilot formats

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
- **Roadmap integration** — agents read `roadmap/roadmap.yaml` to contextualize requests. `@meta-router status` crosses roadmap + proposals + OpenSpec specs into one report.
- **Multi-adapter sync** — one canonical source in `agents/` generates outputs for Claude Code (`.claude/agents/`), OpenCode (`.opencode/agents/`), Cursor (`.cursor/rules/`), and Copilot (`.github/agents/`).
- **Persistent memory** — all senior agents use [Engram](https://github.com/Gentleman-Programming/engram) to persist architectural decisions, bug resolutions, and session context across conversations.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Node.js | ≥ 20.19.0 | [nodejs.org](https://nodejs.org) |
| Claude Code | latest | `npm install -g @anthropic-ai/claude-code` |
| OpenCode | latest | `npm install -g opencode-ai` |
| OpenSpec | latest | `npm install -g @fission-ai/openspec@latest` |
| Engram | latest | `brew install gentleman-programming/tap/engram` |

### Install Engram MCP plugin

```bash
# Claude Code
claude plugin marketplace add Gentleman-Programming/engram
claude plugin install engram

# OpenCode
engram setup opencode
```

---

## Quick Start

### Option A — Install into an existing project

```bash
curl -fsSL https://raw.githubusercontent.com/<your-org>/team-ai-harness/main/scripts/install-management.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/<your-org>/team-ai-harness
cd team-ai-harness
./scripts/install-management.sh /path/to/your-project
```

This creates a `management/` folder inside your project with all agents, skills, rules, roadmap templates, and a root `CLAUDE.md` that points to `management/CLAUDE.md`.

### Option B — Use this repo directly

```bash
git clone https://github.com/<your-org>/team-ai-harness
cd team-ai-harness
./scripts/sync-agents.sh   # generates .claude/agents/ and .opencode/agents/
```

Then open Claude Code or OpenCode in the repo root:

```bash
claude
```

```
@meta-router I need to add payment processing to the checkout flow
```

---

## First Steps After Install

1. **Fill in `management/PROJECT.md`** — project identity, stack, services, principles. Agents read this as ground truth.
2. **Complete `management/roadmap/roadmap.yaml`** — milestones and epics. Ask `@meta-router crear epica [X]` if you're starting fresh.
3. **Check the status** — `@meta-router status` gives a full report crossing roadmap + proposals + specs.

---

## Ceremony Levels

| Level | When | Required agents |
|-------|------|----------------|
| L1 | Quick fix, reversible, < 30 min | Junior + TL (optional) |
| L2 | Standard feature, known patterns | TL + Senior + QA |
| L3 | Architectural change, DB migration | Architect + TL + Senior + QA + Monitoring |
| **L4** | **Money / Auth / Compliance** | **Architect + Security (both, non-negotiable)** + TL + Senior + QA + Monitoring |

**L4 triggers** (hardcoded, can't be downgraded): payment, auth, token, wallet, session, PCI, BCRA, compliance.

---

## Document Flow

Each document has exactly one owner:

| Document | Owner agent | When |
|----------|-------------|------|
| `PROP-NNN.md` (proposal) | `product-owner` | New idea / discovery |
| `roadmap/epicas/ENN-*.md` | orchestrators | Proposal approved |
| `docs/adr/ADR-XX.md` | `architect` | Structural decision L3/L4 |
| `openspec/changes/[name]/tasks.md` | `architect` (L3/L4) / `technical-leader` (L2/L3) | Before coding |
| FILE-IDs (F-NNN) + TEST-IDs (T-NNN) | same as tasks.md owner | Inside tasks.md |
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

Canonical sources live in `agents/`. Generated files in `.claude/agents/` and `.opencode/agents/` are **never edited directly**.

```bash
# Edit canonical source
vim agents/dev/architect.md

# Sync to all configured adapters
./scripts/sync-agents.sh

# Sync to all adapters (Claude, OpenCode, Cursor, Copilot)
./scripts/sync-agents.sh --all

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
├── skills/
│   ├── dev/                       ← planner, code-reviewer, owasp-top10, memory-protocol, ...
│   ├── marketing/                 ← market-audit, market-seo, market-copy, ...
│   └── shared/                    ← bmad-*, roadmap-management, roadmap-status
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
│   └── install-management.sh      ← installer for any project
├── .claude/agents/                ← generated for Claude Code
├── .opencode/agents/              ← generated for OpenCode
├── AGENTS.md                      ← full agent roster + flow diagram
└── PROJECT.md                     ← project identity template
```

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
| Hexagonal | `hexagonal-go` | Hexagonal + DDD patterns for Go (Chi/pgx/Wire) |
| Hexagonal | `hexagonal-python` | Hexagonal + DDD patterns for Python (FastAPI/SQLAlchemy async) |
| Hexagonal | `hexagonal-flutter` | Clean Architecture + DDD patterns for Flutter (BLoC/Riverpod) |
| Hexagonal | `hexagonal-node` | Hexagonal + DDD patterns for Node.js/TypeScript (NestJS/Zod) |
| Hexagonal | `hexagonal-java-springboot` | Hexagonal + DDD patterns for Java (Spring Boot 3.x/MapStruct/ArchUnit) |

---

## Credits

### Engram — Persistent Memory for AI Agents

This harness relies on **[Engram](https://github.com/Gentleman-Programming/engram)** by **[Gentleman Programming](https://github.com/Gentleman-Programming)** for persistent memory across agent sessions and chat compactions.

Engram provides a single binary (zero dependencies) backed by SQLite + FTS5, exposed as an MCP server. It enables any MCP-compatible agent — Claude Code, OpenCode, Gemini CLI, VS Code Copilot — to remember architectural decisions, bug resolutions, and session context indefinitely.

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
- **Skills are documents, not commands** — skills live in `skills/` and are read by agents. They don't go in `.claude/commands/`.
- **Canonical source in `agents/`** — never edit generated files in `.claude/agents/` or `.opencode/agents/` directly.
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

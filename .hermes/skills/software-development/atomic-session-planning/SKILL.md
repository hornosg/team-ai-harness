---
name: atomic-session-planning
description: "Meta-router methodology: break work into atomic, single-session tasks with minimal context and clear handoffs."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [planning, atomic-tasks, single-session, meta-router, work-breakdown]
    related_skills: [plan, s2s-auth-scoped-keys, go-hex-audit]
---

# Atomic Session Planning (Meta-Router)

Use this skill when the user asks to plan work, especially multi-service or multi-step work, and wants it broken into atomic tasks that can each be resolved in a single session.

## Core Principle

**One task = one session = one concrete deliverable.**

A task is atomic when:
- It has a single, clear goal.
- It can be completed start-to-finish without starting other tasks.
- It needs minimal external context (read it from Engram/session if needed, don't assume the agent has it).
- It ends with verifiable output: code changes, tests passing, a saved Engram entry, or a decision.
- It has explicit prerequisites that must already be done.

## Meta-Router Concept

Think of the work as a graph. The meta-router's job is to find the smallest node that can be executed next and route the session to it. The agent is not the implementer of the whole graph; it is the router and executor of one node at a time.

## Rules

### 1. Break by service, then by concern

- **Bad:** "Migrate all services to S2S scoped keys" (too big, multi-session, ambiguous).
- **Good:** "Audit S2S usage in notification-service" (one session, one deliverable).

For each service, break further by concern:
- Audit only.
- IAM policy change only.
- Client change only.
- Hexagonal normalization only.
- Docs/env only.
- Tests/verification only.

### 2. Each task carries its own context

At the start of the task, load only what is needed:
- `mcp_engram_mem_context` for project state.
- `mcp_engram_mem_search` for related past decisions.
- `skill_view` for relevant skills.

Don't rely on the agent carrying context from previous sessions in the same chat.

### 3. Dependencies are explicit

Each task must list prerequisites. Example:

```markdown
**Prerequisites:**
- [ ] Task A.1 done (audit of notification-service completed).
- [ ] Task I.2 done (IAM registry updated with notification-service scopes).
```

The router should not schedule a task until prerequisites are marked done.

### 4. Deliverable is verifiable

Every task ends with one of:
- `go test ./...` passing.
- A file saved and reviewed.
- An Engram entry saved.
- A decision written down and approved by the user.

No hand-wavy "continue in next session" endings. If a task is too big, split it before starting.

### 5. Update the task list after every session

Use `todo` to mark one task in_progress and the rest pending/completed. Never leave multiple tasks in_progress.

### 6. Save to Engram at session boundaries

At the end of every atomic task, save the outcome to Engram with `mcp_engram_mem_save` or `mcp_engram_mem_session_summary`. This is the handoff mechanism between sessions.

## Plan Format

Atomic plans use a flat, numbered task list with dependencies. Avoid nested subtasks.

```markdown
# Plan: [Goal]

## Phase 1: Foundation (no dependencies)

### Task F.1: Audit S2S usage in notification-service
- **Goal:** Identify all uses of `system:admin`, `S2S_API_KEY`, and hexagonal violations in notification-service.
- **Files:** `services/notification-service/src/**/infrastructure/client/*.go`, `src/main.go`, `go.mod`
- **Commands:** `grep -R ...`, `go test ./...`
- **Deliverable:** Markdown audit report saved under `.hermes/plans/findings/`
- **Prerequisites:** none
- **Estimated:** 1 session

### Task F.2: Audit S2S usage in pim-service
...

## Phase 2: IAM Authority (depends on Phase 1)

### Task I.1: Define scopes for notification-service in IAM
- **Goal:** Add `ServicePolicy["notification-service"]` with the minimum scopes identified in F.1.
- **Files:** `iam-service/src/auth/infrastructure/s2s/registry.go`, `registry_test.go`
- **Deliverable:** Registry updated, tests passing, Engram saved.
- **Prerequisites:** F.1 done
- **Estimated:** 1 session
```

## When to Split a Task

Split if any of these are true:
- The task would require more than ~15 tool calls.
- It touches more than 3 unrelated concerns.
- It cannot be fully verified in one session.
- It depends on a decision that isn't made yet.

## When to Combine Tasks

Combine only if two tasks are trivial and sequential, and both fit in one session with <10 tool calls.

## Handoff Between Sessions

At the end of each session, produce a short summary:

```text
Done: [task id] — [one-line result]
Next ready: [task id] (prerequisites met)
Blocked: [task id] (waiting for [what])
```

Save this to Engram so the next session starts with context.

## Execution Mode

When the user says "let's do task X", the agent:
1. Loads skill `atomic-session-planning`.
2. Reads the plan file.
3. Marks task X in_progress in `todo`.
4. Executes only task X.
5. Verifies, saves Engram, marks task X completed.
6. Suggests the next ready task.

## Remember

- Atomic = single session = concrete deliverable.
- One in_progress task at a time.
- Engram is the handoff.
- The meta-router routes, it doesn't do everything at once.

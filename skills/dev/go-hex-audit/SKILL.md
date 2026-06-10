---
name: go-hex-audit
description: Audit pipeline for Go services built with hexagonal architecture and DDD. Use whenever the user asks to audit, review, validate or check a Go project — its architecture, layer coupling, hexagonal/DDD compliance, test coverage, OpenAPI spec — or wants automated API verification with Postman/newman. Triggers on "auditá el proyecto", "audit this Go service", "revisá la arquitectura", "check hexagonal violations", "chequeá el coverage", "enforce coverage", "complete the openapi", "generate postman collection", "verificá la funcionalidad de la API". Supports running the full pipeline or individual phases.
---

# Go Hexagonal/DDD Audit

Pipeline: compile → architecture audit → coverage enforcement → OpenAPI completion → Postman collection → newman functional test (SQLite-backed) → `AUDIT.md` report.

## Execution scope

- Full audit request ("auditá el proyecto") → all phases in order.
- Partial request ("chequeá el coverage", "completá el openapi") → run **Phase 0 + Phase 1 + the requested phase(s)**. Phases 0 and 1 are never skipped; everything else gates on them.
- Phase dependency: 5 needs 4; 6 needs 5.

## Model routing (Claude Code subagents)

When running in Claude Code, delegate phases to subagents via the Task tool with the cheapest model that can honestly do the job. If subagents aren't available, run inline and ignore this section.

| Phase | Model | Why |
|-------|-------|-----|
| 0 Discovery | sonnet | Inferences here propagate to every phase; a wrong layering read poisons the audit |
| 1 Compile | haiku | Mechanical: run commands, fix trivial import/type errors |
| 2 Architecture audit | sonnet | Judgment-heavy DDD reasoning; the core value of the audit |
| 3a Coverage measurement + gate script | haiku | Run, parse, emit script from template below |
| 3b Writing missing tests | sonnet | Meaningful domain tests need understanding the invariants |
| 4 OpenAPI completion | haiku | Transcription of routes/DTOs into a spec; the structure is fully specified below. Escalate to sonnet only if routes are built dynamically (reflection, route registration loops) |
| 5 Postman collection | haiku | Derivation from the completed spec; ordering rules are explicit below |
| 6 e2e run + debugging | sonnet | When newman fails, root-causing app bugs is real debugging |
| Report assembly | haiku | Synthesis from already-structured findings |

Orchestrator stays on whatever model the session runs. Do not use opus anywhere — nothing here requires it.

## Conventions and defaults

- **Stated defaults, all overridable by the user**: coverage thresholds 80% total / 90% domain+application / 70% adapters; e2e port 8081; SQLite driver `modernc.org/sqlite`.
- **No unrequested work**: don't add Makefile targets, CI workflows, linters or hooks unless the user asked or approves when offered. Offer once, in the report's pending-debt section if declined.
- **Git hygiene**: if the working tree is dirty, ask before touching anything. Do all work on a branch `audit/go-hex-audit` unless told otherwise. Never commit unless asked.
- Respect existing project conventions (router, error format, naming, file layout) over your own preferences.
- Never weaken a check to make it pass: no lowering thresholds, skipping failing tests, or deleting assertions.

## Phase 0 — Discovery (always runs)

1. Locate `go.mod` (module, Go version). Multiple modules → ask which one.
2. Map layering: find where domain / application / adapters live (`domain`, `app`, `usecase`, `core`, `adapters`, `infra`, `ports`, `handlers`, `repository`...). 
   - **If the project does not look hexagonal at all** (flat MVC, everything in `main`, handlers calling SQL directly with no layering intent): stop and tell the user. Auditing MVC against hexagonal rules produces 100% noise. Offer either (a) audit against what it actually is, or (b) a migration plan toward hexagonal — different job, confirm first.
3. Identify HTTP framework and auth mechanism (JWT/API key/session, which middleware, which routes are public) — feeds Phases 4–5.
4. Identify the persistence stack **now**, because Phase 6 depends on it:
   - `database/sql` + portable SQL → SQLite path is viable.
   - GORM/sqlx/pgx with Postgres-specific SQL (jsonb, `RETURNING`, arrays, `ON CONFLICT` variants) → SQLite is NOT viable without invasive changes. Flag it immediately and agree with the user on the Phase 6 strategy (dockerized Postgres, or skip) instead of discovering it at the end.
5. Note whether HTTP DTOs exist separate from domain entities. If handlers serialize domain entities directly, record it as a Phase 2 finding and use those structs as the schema source in Phase 4.
6. Check for existing OpenAPI spec, Makefile, CI config, migrations.

Output: a short discovery summary (layering map, auth, persistence verdict, DTO situation) shown to the user before proceeding.

## Phase 1 — Compile (hard gate)

```bash
go mod tidy
go vet ./...
go build ./...
gofmt -l .
```

- Build fails → fix only what's needed to compile (imports, obvious type errors). No refactors. List every fix.
- Can't compile without a design decision → stop and ask.
- `gofmt -l` output → fix (free), list files.

## Phase 2 — Hexagonal / DDD coupling audit

Dependency rule: domain imports nothing of yours except domain; application imports domain + its own ports; adapters import application/domain — never the reverse.

Mechanical pass:

```bash
go list -f '{{.ImportPath}}{{range .Imports}}{{"\n  "}}{{.}}{{end}}' ./...
```

Flag:
- **CRITICAL** — dependency rule inverted: domain importing adapters/infra/handlers, DB drivers (`database/sql`, gorm, sqlx, pgx), or HTTP frameworks; application importing concrete adapters instead of its own port interfaces.
- **HIGH** — infra leakage into the model: persistence tags on domain entities (`gorm:"..."`, `db:"..."`), handlers serializing domain entities directly, adapters calling adapters laterally (HTTP handler → repo, skipping application).
- **MEDIUM** — god-packages (`models`, `utils`, `common`) crossing layers; ports defined on the producer side instead of the consumer side.
- **LOW** — smells: anemic domain (pure-data entities, all behavior in services), `encoding/json` tags in domain (note only).

Severity drives action:
- CRITICAL/HIGH → propose concrete fix with file-level diff sketch; apply only with user approval (or if the original request explicitly said "fix").
- MEDIUM → propose, don't sketch diffs unless asked.
- LOW → list in report only.

Findings table:

| # | Severity | File | Violation | Why it breaks hex/DDD | Suggested fix |
|---|----------|------|-----------|----------------------|---------------|

## Phase 3 — Test coverage enforcement

```bash
go test ./... -coverprofile=coverage.out -covermode=atomic
go tool cover -func=coverage.out
```

- Per-package compare against thresholds (defaults above). Packages already above threshold: skip, report numbers, write nothing.
- Below threshold → write the missing tests, priority order: domain invariants → use cases → adapters. Table-driven, stdlib (+ `testify` only if already a dependency). Tests must assert behavior, not exercise lines.
- Enforcement script `scripts/check-coverage.sh` (offer before creating; wire into CI only if asked):

```bash
#!/usr/bin/env bash
set -euo pipefail
THRESHOLD=${1:-80}
go test ./... -coverprofile=coverage.out -covermode=atomic
total=$(go tool cover -func=coverage.out | awk '/^total:/ {gsub("%","",$3); print $3}')
echo "total coverage: ${total}% (threshold ${THRESHOLD}%)"
awk -v t="$total" -v th="$THRESHOLD" 'BEGIN { exit (t+0 < th+0) }'
```

## Phase 4 — Complete the OpenAPI spec

1. Enumerate routes from the router code — never trust the existing spec. Dynamic registration → trace it (this is the sonnet-escalation case).
2. Diff real routes vs spec. For each missing/incomplete endpoint add: path, method, summary, tag per bounded context, request/response schemas derived from the structs the handlers actually serialize (DTOs if they exist; flagged domain entities otherwise), error responses (400/401/403/404/409/422/500 as applicable) with one shared `Error` schema, and per-endpoint `security` matching the real middleware (public routes from Phase 0 get none).
3. `components.securitySchemes` matching the real auth.
4. Validate: `npx -y @redocly/cli lint openapi.yaml` — must pass clean.

Output where the project already keeps its spec; repo root if none.

## Phase 5 — Postman collection ordered by auth flow

Build `postman/collection.json` (v2.1) by hand from the completed spec — ordering is the point, blind converters lose it:

1. Health/public endpoints
2. Auth bootstrap: register → login; login test script stores the token:
   ```javascript
   pm.collectionVariables.set("token", pm.response.json().token);
   ```
   (adjust the JSON path to the real login response)
3. Authenticated flows in entity-dependency order (parents before children)
4. Negative cases: no token → 401; invalid payload → 4xx
5. Cleanup: deletes in reverse dependency order

Variables: `{{baseUrl}}`, `{{token}}`, `{{<resource>Id}}` per created entity. Every request gets `pm.test` assertions: status, key response fields, ID chaining. Also emit `postman/environment.local.json` with the project's real port.

## Phase 6 — Newman functional run (SQLite)

Strategy was settled in Phase 0. SQLite path: add driver selection behind config (`DB_DRIVER`/`DB_DSN`) touching only the persistence adapter wiring — if it requires touching domain or application, the change is wrong, fall back to the agreed alternative.

`scripts/e2e.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DB_FILE=$(mktemp -u /tmp/e2e-XXXX.db)
export DB_DRIVER=sqlite DB_DSN="file:${DB_FILE}?_pragma=foreign_keys(1)"
export PORT=${PORT:-8081}

[ -x ./scripts/migrate.sh ] && ./scripts/migrate.sh

go build -o /tmp/app ./cmd/...
/tmp/app & APP_PID=$!
trap 'kill $APP_PID 2>/dev/null; rm -f "$DB_FILE"' EXIT

for i in $(seq 1 30); do
  curl -sf "http://localhost:${PORT}/health" >/dev/null && break
  sleep 0.5
done

npx -y newman run postman/collection.json \
  -e postman/environment.local.json \
  --env-var "baseUrl=http://localhost:${PORT}" \
  --reporters cli,json --reporter-json-export newman-report.json
```

Adapt env var names, health path and build path to the project. Run it; app bugs surfaced here are findings (fix only with approval, same rule as Phase 2). The script must end green or the report says exactly why not.

## Final report — `AUDIT.md`

1. **Resumen ejecutivo** — one paragraph, pass/fail per executed phase
2. Compilation fixes applied
3. Architecture findings table + refactor plan ordered by severity
4. Coverage before/after per package; enforcement mechanism (added or declined)
5. OpenAPI endpoints added/corrected
6. Postman/newman: requests, assertions, final result
7. **Deuda pendiente** — everything not fixed and why, including offers the user declined

Factual and terse. No filler.

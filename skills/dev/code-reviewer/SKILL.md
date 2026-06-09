---
name: code-reviewer
description: Read-only 7-dimension code review with FILE-ID/TEST-ID verification. Produces a remediation plan with severity and assignments.
triggers:
  - "review this code"
  - "code review"
  - "/review"
  - "check my implementation"
---

# Code Reviewer

Comprehensive, read-only code review across 7 quality dimensions.

## Activation

After implementation is complete (all FILE-IDs done) or upon explicit request. **READ-ONLY — nunca modifica código.**

## Proceso

### Step 1: Load Context

Leer:
- El plan (FILE-ID table, TEST-ID table, contratos) — si usa OpenSpec, está en `openspec/changes/[nombre]/tasks.md`
- Todos los archivos implementados
- Todos los archivos de tests
- Reglas de arquitectura del proyecto (ver `PROJECT.md` si existe)

### Step 2: FILE-ID Verification

Para cada FILE-ID en el plan:

| FILE-ID | Path | Status | Contract Match | Notes |
|---------|------|--------|----------------|-------|
| F-001   | src/.../feature.ts | EXISTS | MATCH | — |
| F-002   | src/.../repo.ts | EXISTS | PARTIAL | Falta método `delete` |

**Light mode (L3):** file exists + key methods present
**Formal mode (L4):** verify every field, method signature, error type

### Step 3: TEST-ID Verification

| TEST-ID | FILE-ID | Status | Quality | Notes |
|---------|---------|--------|---------|-------|
| T-001   | F-001   | PASS | GOOD | Clear AAA, meaningful assert |
| T-002   | F-001   | PASS | WEAK | Tests existence only |
| T-003   | F-003   | MISSING | — | Not implemented |

### Step 4: 7-Dimension Review

Score cada dimensión 1-5:

#### D1: Plan Fidelity
- FILE-IDs creados/modificados según el plan
- Contratos implementados según spec
- Sin scope creep no autorizado

#### D2: Functional Correctness
- Lógica de negocio maneja escenarios esperados
- Edge cases cubiertos (empty, max, concurrent)
- Error propagation correcto

#### D3: Test Coverage
- TEST-IDs todos implementados
- Tests son de comportamiento, no de implementación
- Coverage targets cumplidos por capa

#### D4: Architecture Compliance
- Layer boundaries respetados
- Dependency direction correcta (domain no depende de nada, app solo de domain)
- Patterns coinciden con el codebase existente

#### D5: Code Quality
- Funciones < 30 líneas
- Naming claro
- Sin code smells (magic numbers, god objects, deep nesting)
- SOLID principles aplicados

#### D6: Security
- Input validation en boundaries
- Sin PII en logs
- Access control correcto
- Sin secretos hardcodeados

#### D7: Documentation
- Public APIs documentadas
- Decisiones no obvias explicadas en comentarios
- API spec actualizado si aplica

### Step 5: Generate Report

```markdown
## Code Review Report

**Change:** [nombre]
**Ceremony Level:** L[1-4]
**Date:** [fecha]

### Scorecard

| Dimension | Score | Status |
|-----------|-------|--------|
| Plan Fidelity | X/5 | OK/WARNING |
| Functional | X/5 | |
| Test Coverage | X/5 | |
| Architecture | X/5 | |
| Code Quality | X/5 | |
| Security | X/5 | |
| Documentation | X/5 | |

**Overall: XX/35 ([APPROVED / APPROVED WITH CONDITIONS / REVISIONS REQUIRED / REJECTED])**

### FILE-ID Verification
[tabla del Step 2]

### TEST-ID Verification
[tabla del Step 3]

### Findings

| ID | Dimension | Severity | File | Description |
|----|-----------|----------|------|-------------|
| R-001 | Test Coverage | HIGH | F-003 | Missing T-003 |

### Remediation Plan

| ID | Severity | Role | Action | Acceptance |
|----|----------|------|--------|------------|
| R-001 | HIGH | dev | Implement T-003 | Test passes |
```

## Approval Thresholds

| Score | Status |
|-------|--------|
| 30-35 | APPROVED |
| 25-29 | APPROVED WITH CONDITIONS |
| 20-24 | REVISIONS REQUIRED |
| <20   | REJECTED |

## Guardrails

- NUNCA editar archivos — read-only
- NUNCA aprobar sin verificar TODOS los FILE-IDs y TEST-IDs
- Findings CRITICAL y HIGH siempre generan remediation items
- Si no hay plan (L1), saltear FILE-ID/TEST-ID y evaluar D2-D7
- Si el plan usa OpenSpec, buscar en `openspec/changes/[nombre]/tasks.md`

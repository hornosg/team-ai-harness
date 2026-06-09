---
name: pr-workflow
description: Ciclo completo de PR — branch creation, staging, conventional commits, y PR submission.
triggers:
  - "create a PR"
  - "submit PR"
  - "commit and push"
  - "/pr"
---

# PR Workflow

Flujo completo desde creación de branch hasta PR submission.

## Stage 1: Branch Setup

### Naming Convention

```
<type>/<scope>-<short-description>

# Ejemplos:
feat/auth-social-login
fix/api-token-refresh
refactor/config-simplify
docs/api-openapi-update
```

| Type | Cuando |
|------|--------|
| feat | Nueva feature o capacidad |
| fix  | Bug fix |
| refactor | Reestructuración, sin cambio de comportamiento |
| docs | Solo documentación |
| test | Additions o fixes de tests |
| chore | Build, CI, tooling |

### Proceso

```bash
git branch --show-current
git checkout -b <type>/<scope>-<description>
```

Si ya estás en un feature branch, quedate.

## Stage 2: Smart Staging

```bash
git status
git diff --stat
```

### Staging Rules

- Stage archivos relacionados juntos
- **Nunca stagear**: `.env`, credenciales, `node_modules/`, build artifacts
- Verificar: sin debug code, sin TODOs, sin commented-out blocks
- Splitear si los cambios cubren concerns diferentes

```bash
git add src/domain/
git add src/application/
# O archivos específicos
git add path/to/specific/file.ts
```

## Stage 3: Conventional Commit

Ver `skills/dev/conventional-commit.md` para formato completo.

```bash
git commit -m "$(cat <<'EOF'
feat(products): add variant management

Products can now have multiple variants with independent SKUs and prices.

Refs: FILE-IDs F-001 through F-006
EOF
)"
```

## Stage 4: Push + PR

```bash
git push -u origin HEAD
```

### Crear PR con gh CLI

```bash
gh pr create --title "<type>(<scope>): <subject>" --body "$(cat <<'EOF'
## Summary
- [qué cambió]
- [por qué]
- [decisión técnica clave]

## Type of Change
- [ ] Nueva feature
- [ ] Bug fix
- [ ] Refactoring
- [ ] Documentación
- [ ] Tests

## FILE-IDs Implementados
| FILE-ID | Status |
|---------|--------|
| F-001   | Done |

## Testing
- [ ] Unit tests pasan
- [ ] Integration tests pasan (si aplica)
- [ ] Smoke test manual realizado

## Checklist
- [ ] Código sigue reglas de arquitectura
- [ ] Tests cubren happy path + error paths
- [ ] Sin PII en logs
- [ ] API docs actualizados (si aplica)
- [ ] Sin breaking changes (o documentados en footer)
EOF
)"
```

## Multi-Commit Strategy

Para features grandes, commitear incrementalmente:
1. Domain layer (models, ports)
2. Application layer (use cases, DTOs)
3. Infrastructure layer (adapters, controllers)
4. Presentation layer (UI components)
5. Tests + documentación

Cada commit debe ser self-contained y passing.

## Guardrails

- NUNCA pushear directamente a main/master
- NUNCA force-push sin pedido explícito
- NUNCA commitear `.env`, secrets, o build artifacts
- NUNCA crear empty commits
- Siempre verificar que los tests pasan antes de pushear
- PR description debe incluir qué cambió y por qué
- Si el PR tiene >500 líneas de diff, sugerir splitear

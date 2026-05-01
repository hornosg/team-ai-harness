---
name: conventional-commit
description: Enforce Conventional Commits format for consistent, parseable commit messages.
triggers:
  - "format commit"
  - "write commit message"
  - "conventional commit"
---

# Conventional Commits

## Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer(s)]
```

## Types

| Type     | Cuando | En Changelog |
|----------|--------|-------------|
| feat     | Nueva feature para el usuario | Sí |
| fix      | Bug fix para el usuario | Sí |
| refactor | Reestructuración, sin cambio de comportamiento | No |
| test     | Agregar o arreglar tests | No |
| docs     | Solo documentación | No |
| chore    | Build, CI, tooling, dependencias | No |
| ci       | Cambios en pipeline CI/CD | No |
| perf     | Mejora de performance | Sí |
| style    | Formato, whitespace (sin cambio de código) | No |
| revert   | Reverting un commit previo | Sí |

## Scope

El módulo, servicio, o área afectada:
- Usar el nombre del módulo principal (ej: `auth`, `api`, `core`, `ui`)
- Usar `repo` si el cambio es a nivel de proyecto
- Scopes cortos y consistentes en todo el proyecto

## Subject Rules

- Modo imperativo: "add" no "adds" ni "added"
- Minúscula al inicio
- Sin punto al final
- Max 72 caracteres
- Completar la oración: "This commit will... [subject]"

## Ejemplos

```
feat(auth): add social login flow

fix(api): handle token refresh errors

refactor(core): extract JWT validation to middleware

test(payments): add unit tests for retry logic

docs(api): update OpenAPI spec with new endpoints

chore(deps): upgrade base image to latest LTS

perf(db): add index on products.sku column
```

## Body (Opcional)

Explicar POR QUÉ, no QUÉ (el diff muestra el qué):

```
feat(products): add variant management endpoints

Products can now have multiple variants with independent SKUs and prices.
Enables stores to sell different sizes/colors without separate product entries.

Implements FILE-IDs F-001 through F-006.
```

## Footer (Opcional)

```
BREAKING CHANGE: ProductResponse now includes `variants` array field

Refs: #123
Closes: #456
```

## Breaking Changes

Agregar `!` después de type/scope O usar footer `BREAKING CHANGE:`:

```
feat(api)!: change product response format to include variants

BREAKING CHANGE: `price` field moved to `variants[].price`
```

## Workflow

1. `git status` y `git diff` para ver cambios
2. Identificar el tipo de cambio dominante
3. Elegir scope claro
4. Redactar subject en modo imperativo
5. Agregar body si el "por qué" no es obvio

## Guardrails

- NUNCA usar pasado en el subject ("added", "fixed")
- NUNCA superar 72 chars en el subject
- NUNCA commitear sin tipo
- Si no estás seguro del tipo: `feat` para comportamiento nuevo, `fix` para correcciones, `refactor` para reestructura
- Un cambio lógico por commit — no mezclar feat + fix

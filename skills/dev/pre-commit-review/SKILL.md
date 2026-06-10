---
name: pre-commit-review
description: Revisa los cambios staged para asegurar que el código que entra al historial es correcto, limpio y consistente con los estándares del proyecto. Usar cuando el usuario pide "revisá antes de commitear", "chequeá el diff", "está listo para commitear?", "revisá el código nuevo", o cuando Claude detecta que está a punto de ejecutar `git commit`. El objetivo es código bien escrito desde el primer commit — no deuda acumulada. Devuelve veredicto GO / NO-GO con hallazgos accionables.
---

# pre-commit-review

Objetivo: que cada commit que entra al historial sea correcto, limpio y consistente — sin deuda de calidad desde el primer día.

Pipeline: discovery → seguridad → compilación → calidad de código → arquitectura → tests → engram → veredicto.

Integra estándares de [`go-hex-audit`](../go-hex-audit/SKILL.md) (arquitectura hexagonal), [`engram-setup`](../engram-setup/SKILL.md) (memoria del ecosistema) y [`docs-organize`](../../shared/docs-organize/SKILL.md) (señal de ADR). Analiza **solo el diff staged** — no opina sobre código preexistente.

## Modos

| Modo | Cuándo usar | Fases |
|------|-------------|-------|
| **Completo** (default) | El usuario pide review antes de commitear | 0 → 7 |
| **Hook** (bash) | Instalado como `.git/hooks/pre-commit` | 0 + 1 + 2 — mecánico, sin Claude |

## Severidades

| Nivel | Criterio | Veredicto |
|-------|----------|-----------|
| **BLOCKER** | El commit rompe algo o expone un secreto | NO-GO obligatorio |
| **HIGH** | El código nuevo tiene un problema real que no debería entrar | NO-GO; el usuario puede forzar con justificación explícita |
| **MEDIUM** | Deuda razonable para un follow-up | GO con advertencia |
| **LOW** | Sugerencia menor o informativo | GO |

## Convenciones

- Solo el diff staged (`git diff --staged`). El código preexistente no staged es deuda anterior — no es el scope de este review.
- No modificar archivos durante el review. Si hay un fix fácil (ej. `gofmt`), ofrecerlo como acción posterior, nunca aplicarlo sin avisar.
- No correr la suite completa de tests — demasiado lento. Solo compilación y `go vet` en los paquetes tocados.
- No bloquear por estilo subjetivo. Solo por correctitud, seguridad y estándares ya acordados en el proyecto.

---

## Fase 0 — Discovery (siempre corre)

```bash
git diff --staged --name-only   # lista de archivos
git diff --staged --stat        # resumen del cambio
git diff --staged               # diff completo para análisis
git branch --show-current && git log -1 --oneline
```

Si no hay nada staged → terminar: "No hay cambios staged."

Construir mapa del diff:

| Archivo | Capa | Tipo de cambio |
|---------|------|---------------|
| `domain/user/entity.go` | Dominio | Nuevo archivo |
| `adapters/http/user_handler.go` | Adaptador | Modificado |
| ... | | |

Capas reconocidas para Go hexagonal: `domain/`, `application/` o `usecase/`, `adapters/` o `infrastructure/` o `handlers/`.

---

## Fase 1 — Seguridad (BLOCKER) — siempre corre

### Archivos que nunca deben commitearse

```bash
git diff --staged --name-only | grep -iE \
  '\.env$|\.env\.|\.pem$|\.key$|\.p12$|\.pfx$|id_rsa|id_ed25519|credentials\.json'
```

Cualquier match → BLOCKER. La presencia del archivo es suficiente; no hace falta leer el contenido.

### Secretos hardcodeados en el contenido

Analizar líneas añadidas (`+`) del diff buscando asignaciones de valor literal a variables sensibles:

```bash
git diff --staged | grep -E '^\+' | grep -iE \
  '(password|passwd|secret|api_key|apikey|token|bearer)\s*[:=]\s*["'"'"'][^"'"'"']{6,}'
```

**No reportar** como secreto:
- Líneas en `*_test.go` con valores claramente ficticios (`"test-password"`, `"fake-token"`, `"secret123"`).
- Referencias a variables de entorno: `os.Getenv("SECRET")`, `${SECRET}`, `process.env.TOKEN`.
- Constantes que son nombres/claves, no valores: `const SecretKey = "SECRET_KEY"`.

Match real → BLOCKER. Reportar archivo y número de línea, sin mostrar el valor completo.

---

## Fase 2 — Compilación (BLOCKER) — siempre corre

```bash
# Paquetes Go afectados por el diff
git diff --staged --name-only | grep '\.go$' | grep -v '_test\.go' | \
  xargs -I{} dirname {} | sort -u | xargs -I{} go list ./{} 2>/dev/null
```

Para cada paquete identificado:

```bash
go build ./paquete/...
go vet ./paquete/...
gofmt -l archivos_staged.go
```

- `go build` falla → BLOCKER con el error exacto.
- `go vet` reporta → HIGH con el output completo.
- `gofmt -l` devuelve archivos → MEDIUM ("Correr `gofmt -w <archivo>` antes de commitear").
- Cambios en `go.mod` o `go.sum` staged → verificar que estén sincronizados:
  ```bash
  go mod verify
  ```
  Error → MEDIUM.

---

## Fase 3 — Calidad del código nuevo

Foco en las líneas añadidas (`+`). El objetivo es que el código nuevo sea correcto y legible desde el primer commit.

### 3a. Código nuevo — correctitud básica

Para cada función o método añadido en los archivos staged:
- ¿Maneja errores? Líneas que retornan un `error` y el llamador lo ignora con `_` → HIGH.
- ¿Retorna `nil` en casos de error antes de inicializar recursos que requieren limpieza? → HIGH.
- ¿Usa `context.Context` cuando llama a I/O, DB, o HTTP? Si no → MEDIUM para código nuevo en capas de aplicación/adaptadores.

### 3b. Código nuevo — legibilidad

Solo señalar cuando impacta en la comprensión, no por estilo:
- Función añadida con más de ~40 líneas que hace cosas conceptualmente distintas → MEDIUM ("podría dividirse").
- Variable o parámetro añadido con nombre de una sola letra fuera de un loop (`i`, `j` en loops son OK) → LOW.
- Comentario añadido que solo repite el nombre de la función (`// GetUser returns the user`) → LOW.

### 3c. Migraciones SQL staged

Si hay archivos de migración en el diff:
- ¿Tiene `UP` y `DOWN`? Si solo hay `UP` → MEDIUM.
- ¿Algún `DROP TABLE`, `DROP COLUMN` o `TRUNCATE` sin un `IF EXISTS`? → HIGH.
- ¿Agrega columna `NOT NULL` sin `DEFAULT` en una tabla que puede tener filas? → HIGH ("migración destructiva potencial en producción").

---

## Fase 4 — Arquitectura hexagonal

Aplicar las reglas de `go-hex-audit` Fase 2 **únicamente sobre las líneas añadidas** del diff.

### BLOCKER — dependencia invertida
Archivos bajo `domain/` que en las líneas añadidas importan:
- Paquetes de `adapters/`, `infrastructure/`, `handlers/`.
- Drivers de DB/HTTP: `database/sql`, `gorm`, `pgx`, `gin`, `net/http`, `sqlx`.

### HIGH — leakage de infraestructura
- Struct en `domain/` con tags ORM añadidos (`gorm:"..."`, `db:"..."`).
- Handler que en las líneas añadidas accede directamente a un repositorio sin pasar por un use case.
- Use case que importa un adaptador concreto en lugar de la interfaz de su puerto.

### MEDIUM — señales de mal diseño
- Código nuevo en `domain/` con nombres que sugieren persistencia (`Save`, `Find`, `Query`, `Load`) implementados como métodos de entidad.
- Package `utils/`, `common/` o `helpers/` con lógica de negocio añadida.

Para cada hallazgo: archivo, línea en el diff, regla violada, fix concreto sugerido.

---

## Fase 5 — Tests del código nuevo

Para cada archivo de producción staged bajo `domain/` o `application/`:

```bash
# ¿Hay un _test.go correspondiente en el diff staged?
PROD_FILES=$(git diff --staged --name-only | grep '\.go$' | grep -v '_test\.go' | grep -E 'domain/|application/|usecase/')
TEST_FILES=$(git diff --staged --name-only | grep '_test\.go')
```

- Archivo nuevo en `domain/` o `application/` sin `_test.go` correspondiente en el diff → HIGH. El código de dominio entra con tests o no entra.
- Modificación de lógica existente en `domain/` sin cambios en tests → MEDIUM. Puede ser que los tests existentes ya cubran el cambio, pero vale señalarlo.
- Código nuevo en `adapters/` o `infrastructure/` sin tests → LOW (recomendado pero no bloqueante).

No correr `go test`. Solo verificar presencia en el diff.

---

## Fase 6 — Engram: contexto del ecosistema

Si el proyecto tiene `.engram/config.json`:

```bash
cat .engram/config.json
```

Buscar en memoria por las áreas tocadas en el diff:

```
mem_search "<módulo o entidad principal del diff>"
mem_search "bug <módulo>"
mem_search "decisión <área>"
```

Los resultados se incluyen como **CONTEXT** en el veredicto — no son hallazgos bloqueantes. Ejemplos de contexto útil:
- "Hay un bug conocido con la validación de JWT en este módulo — chequeá que el cambio no lo reactiva."
- "Se decidió en sesión anterior no usar `gorm` en este bounded context — el diff parece ir en esa dirección."
- "Este patrón ya se implementó en `iam-service`, podría extraerse a `go-shared`."

Si el diff encapsula una decisión nueva relevante para el ecosistema → sugerir guardarla con `mem_save` después del commit.

---

## Fase 7 — Veredicto

### Tabla de hallazgos

```
| # | Nivel   | Fase | Ubicación            | Problema                              | Fix sugerido                        |
|---|---------|------|----------------------|---------------------------------------|-------------------------------------|
| 1 | BLOCKER | Seg  | config.go:42         | Secret hardcodeado (token=)           | Mover a variable de entorno         |
| 2 | HIGH    | Arq  | user_repo.go:18      | domain/ importa gorm                  | Definir interfaz Repository en domain/ |
| 3 | HIGH    | Test | user_usecase.go      | Lógica nueva en domain/ sin tests     | Agregar user_usecase_test.go        |
| 4 | MEDIUM  | Cal  | handler.go:55        | Error ignorado con _                  | Manejar o propagar el error         |
```

### Resultado

**NO-GO** (uno o más BLOCKER o HIGH):
```
❌ NO-GO — resolver antes de commitear:
  1. [acción concreta]
  2. [acción concreta]
```

**GO con advertencias** (solo MEDIUM / LOW):
```
✅ GO — N advertencia(s) para follow-up:
  1. [descripción]
```

**GO limpio**:
```
✅ GO
```

Si Engram devolvió contexto relevante, incluirlo al final como "**Contexto del ecosistema**".

---

## Setup del hook git (opcional)

Corre las fases mecánicas (seguridad + compilación) automáticamente antes de cada `git commit`, sin Claude:

```bash
cat > .git/hooks/pre-commit << 'HOOK'
#!/usr/bin/env bash
set -euo pipefail
# pre-commit — seguridad + build (modo hook de pre-commit-review)
# Review completo: pedile a Claude "revisá antes de commitear"

echo "▶ [pre-commit] Seguridad..."

FORBIDDEN=$(git diff --staged --name-only | grep -iE \
  '\.env$|\.env\.|\.pem$|\.key$|id_rsa|id_ed25519|credentials\.json' || true)
[ -n "$FORBIDDEN" ] && echo "❌ BLOCKER: archivos sensibles staged:" && echo "$FORBIDDEN" && exit 1

SECRETS=$(git diff --staged | grep -E '^\+' | grep -iE \
  '(password|secret|api_key|token)\s*[:=]\s*["'"'"'][^"'"'"']{6,}' \
  | grep -vE '(_test\.go|Getenv|os\.Environ)' || true)
[ -n "$SECRETS" ] && echo "❌ BLOCKER: posibles secretos en el diff" && echo "$SECRETS" | head -3 && exit 1

echo "▶ [pre-commit] Build..."

PKGS=$(git diff --staged --name-only | grep '\.go$' | grep -v '_test\.go' | \
  xargs -I{} dirname {} 2>/dev/null | sort -u | \
  xargs -I{} go list ./{} 2>/dev/null | tr '\n' ' ' || true)

if [ -n "$PKGS" ]; then
  go build $PKGS   || { echo "❌ BLOCKER: build falla"; exit 1; }
  go vet $PKGS     || { echo "❌ HIGH: go vet reporta problemas"; exit 1; }
fi

echo "✅ [pre-commit] OK — para review completo: pedile a Claude 'revisá antes de commitear'"
HOOK
chmod +x .git/hooks/pre-commit
echo "Hook instalado."
```

Para desinstalar: `rm .git/hooks/pre-commit`.  
Para saltear puntualmente (solo con razón justificada): `git commit --no-verify`.

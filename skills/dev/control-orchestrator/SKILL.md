---
name: control-orchestrator
description: Meta-skill que orquesta la verificación de cumplimiento de ADRs para un servicio o cambio concreto. Dado un ADR o un path de servicio, descubre los ADRs aplicables, lee sus skills.verify del frontmatter, invoca cada skill en cadena y consolida hallazgos en un reporte único con veredicto GO/NO-GO por ADR. Usar ante: pre-merge de un cambio que toca un servicio con ADRs, post-implementación de un ADR, pre-deploy, o auditoría on-demand. Triggers: "verificá los ADRs del servicio", "audit ADR compliance", "corrés el orquestador de controles", "run control orchestrator", "verificá el cumplimiento de los ADRs", "pre-merge ADR check", "ADR compliance check".
---

# Control Orchestrator

Meta-skill que **lee el cableado ADR↔skill ya hecho** en el ecosistema y dispara las skills de `verify` correspondientes de forma orquestada. El resultado es un reporte unificado con veredicto GO/NO-GO por ADR y por servicio.

## Diferencia con `pre-commit-review`

| | `pre-commit-review` | `control-orchestrator` |
|--|--------------------|-----------------------|
| Scope | Diff staged genérico | Cumplimiento de ADRs específicos |
| Input | Cambios en git staging | ADR, path de servicio, o diff de rama |
| Cuándo | Antes de cada commit | Pre-merge, post-ADR-implementación, pre-deploy, on-demand |
| Qué verifica | Calidad, seguridad, arquitectura hexagonal general | Decisiones de arquitectura ya tomadas y documentadas en ADRs |
| Output | Veredicto commit GO/NO-GO | Veredicto por ADR + reporte de cumplimiento |

Son **complementarios, no solapados**: `pre-commit-review` cuida la calidad de cada commit; `control-orchestrator` cuida que los ADRs se cumplan a lo largo del tiempo.

## Modos

| Modo | Cuándo usar | Fases |
|------|-------------|-------|
| **Completo** (default) | El usuario pide auditar un servicio o ADR — invoca Claude | 0 → 5 |
| **Hook** (bash) | Instalado en pre-merge/pre-push — detección ligera, sin Claude | 0 + 1 — lista los ADRs aplicables, no ejecuta las skills |

---

## Modo Completo — Pipeline

### Fase 0 — Resolución de entrada

Puede recibir:
1. **Un ADR concreto** — ej. `services/sales-service/docs/adr/ADR-001-operacion-atomica-stock.md`
2. **Un path de servicio** — ej. `services/sales-service/` → descubrir todos sus ADRs
3. **Un diff de rama o commit** — ej. `git diff main...HEAD` → descubrir qué servicios toca y sus ADRs

```bash
# Caso 2: descubrir ADRs de un servicio
find services/sales-service/docs/adr/ -name "*.md" | sort

# Caso 3: servicios tocados en un diff
git diff main...HEAD --name-only | grep "^services/" | cut -d/ -f1-2 | sort -u
# → services/sales-service
# → services/stock-service
```

### Fase 1 — Parseo de skills.verify del frontmatter

Para cada ADR descubierto, leer su frontmatter YAML y extraer `skills.verify`:

```bash
# Extraer skills.verify de un ADR (requiere yq o parsing manual)
grep -A10 "^skills:" services/sales-service/docs/adr/ADR-001-operacion-atomica-stock.md | \
  grep -A5 "verify:" | grep "    - " | sed 's/.*- //'
```

Construir el plan de ejecución:

| ADR | skills.verify a ejecutar |
|-----|-------------------------|
| sales/ADR-001 (operación atómica) | `dev/go-hex-audit`, `dev/code-reviewer`, `dev/concurrency-transactions` |
| sales/ADR-002 (snapshots) | `dev/go-hex-audit`, `dev/code-reviewer`, `dev/postgres-data-modeling` |
| stock/ADR-001 (transacciones atómicas) | `dev/go-hex-audit`, `dev/code-reviewer`, `dev/concurrency-transactions` |

Si `skills.pending` tiene entradas → reportar que el ADR tiene skills de verificación pendientes de crear; continuar con las ya disponibles.

### Fase 2 — Ejecución de skills en cadena

Para cada ADR y cada skill de su `skills.verify`:

1. Invocar la skill sobre el código del servicio correspondiente.
2. Registrar los hallazgos con su severidad.
3. Continuar con la siguiente skill aunque la anterior haya dado hallazgos (no abortar en el primer problema).

Orden recomendado por ADR:
1. Primero `dev/go-hex-audit` (compilación y arquitectura hexagonal — base)
2. Luego skills especializadas (`dev/concurrency-transactions`, `dev/postgres-data-modeling`, etc.)
3. Último `dev/code-reviewer` si está en `skills.verify`

### Fase 3 — Consolidación de hallazgos

Agrupar todos los hallazgos por ADR y por severidad:

```
## Reporte de cumplimiento ADR — services/sales-service

### ADR-001: Operación atómica de descuento de stock
Skills ejecutadas: go-hex-audit, concurrency-transactions

| # | Severity | Skill | Archivo | Problema | Fix sugerido |
|---|----------|-------|---------|----------|--------------|
| 1 | CRITICAL | concurrency-transactions | sale_usecase.go:45 | CheckAvailability + ProcessSale separados | Reemplazar por ProcessSaleAtomic |
| 2 | MEDIUM | go-hex-audit | order_handler.go:12 | Context no propagado a repo | Pasar ctx como primer argumento |

**Veredicto ADR-001**: ❌ NO-GO (1 CRITICAL)

---

### ADR-002: Snapshot histórico inmutable
Skills ejecutadas: go-hex-audit, postgres-data-modeling

| # | Severity | Skill | Archivo | Problema | Fix sugerido |
|---|----------|-------|---------|----------|--------------|
| 1 | MEDIUM | postgres-data-modeling | 003_migration.sql | Falta IF NOT EXISTS | Agregar cláusula idempotente |

**Veredicto ADR-002**: ✅ GO con 1 advertencia
```

### Fase 4 — Skills con pending (informativo)

Si algún ADR tiene `skills.pending`, reportar al final:

```
## Skills de verificación pendientes de crear

Los siguientes ADRs declaran skills aún inexistentes en skills.pending.
La verificación de estos aspectos queda como deuda de gobernanza:

- tenant/ADR-002: pending dev/outbox-pattern (aún no creada)
```

### Fase 5 — Veredicto global

```
## Veredicto Global — services/sales-service

| ADR | Veredicto | Bloqueantes |
|-----|-----------|-------------|
| ADR-001 | ❌ NO-GO | 1 CRITICAL |
| ADR-002 | ✅ GO | — |

**Resultado final**: ❌ NO-GO — resolver el hallazgo CRITICAL de ADR-001 antes de mergear.
```

---

## Modo Hook (bash) — detección ligera sin Claude

Instalable en `.git/hooks/pre-push` o como step en CI. No invoca Claude ni ejecuta las skills — solo **lista los ADRs cuya verificación aplica** al diff, para que el reviewer sepa qué revisar.

```bash
cat > .git/hooks/pre-push << 'HOOK'
#!/usr/bin/env bash
# control-orchestrator — modo hook (detección de ADRs aplicables)
# Verificación profunda: pedile a Claude "verificá los ADRs del servicio"
set -euo pipefail

BASE_BRANCH="${1:-main}"
SERVICES_DIR="services"
ADR_SUBPATH="docs/adr"

echo "▶ [control-orchestrator] Detectando ADRs aplicables al diff..."

# Servicios modificados en el diff
CHANGED_SERVICES=$(git diff "${BASE_BRANCH}"...HEAD --name-only 2>/dev/null | \
  grep "^${SERVICES_DIR}/" | cut -d/ -f1-2 | sort -u || true)

if [ -z "$CHANGED_SERVICES" ]; then
  echo "ℹ  No hay cambios en servicios — skip."
  exit 0
fi

FOUND=0
for SVC in $CHANGED_SERVICES; do
  ADR_DIR="${SVC}/${ADR_SUBPATH}"
  if [ ! -d "$ADR_DIR" ]; then
    continue
  fi

  echo ""
  echo "📋 ${SVC} — ADRs con skills.verify:"
  for adr in "${ADR_DIR}"/*.md; do
    [ -f "$adr" ] || continue
    VERIFY=$(grep -A10 "^skills:" "$adr" 2>/dev/null | grep -A5 "  verify:" | grep "    - " | sed 's/.*- //' || true)
    PENDING=$(grep -A10 "^skills:" "$adr" 2>/dev/null | grep -A5 "  pending:" | grep "    - " | sed 's/.*- //' || true)
    if [ -n "$VERIFY" ] || [ -n "$PENDING" ]; then
      ADR_TITLE=$(grep "^# " "$adr" | head -1 | sed 's/^# //')
      echo "  $(basename "$adr") — ${ADR_TITLE}"
      [ -n "$VERIFY" ]  && echo "    verify:  $(echo "$VERIFY" | tr '\n' ' ')"
      [ -n "$PENDING" ] && echo "    pending: $(echo "$PENDING" | tr '\n' ' ') (skills aún sin crear)"
      FOUND=1
    fi
  done
done

if [ "$FOUND" -eq 1 ]; then
  echo ""
  echo "ℹ  Para auditoría completa: pedile a Claude 'verificá los ADRs de <servicio>'"
fi
HOOK
chmod +x .git/hooks/pre-push
echo "Hook instalado en .git/hooks/pre-push"
```

Para desinstalar: `rm .git/hooks/pre-push`.

### Integración como hook de Claude Code (configuración futura)

Claude Code permite configurar hooks en `.claude/settings.json`. El patrón para conectar este orquestador como hook post-implementación sería:

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "bash /path/to/control-orchestrator-hook.sh"
      }]
    }]
  }
}
```

**Estado actual**: no hay hooks configurados en `.claude/settings.local.json` del proyecto. Esta integración queda pendiente para cuando se defina el evento disparador exacto (post-implementación de un ADR, pre-merge, etc.). Configurar con `update-config` cuando el owner lo apruebe.

---

## Referencia del cableado ADR↔skill

El validador de integridad del cableado es:
```bash
SK=/Users/hornosg/Projects/active/mercado-cercano/management/skills
python3 /Users/hornosg/Projects/active/team-ai-harness/scripts/wire-adrs.py \
  /path/to/service/docs/adr "$SK"
```

Convención completa: `team-ai-harness/scripts/WIRING.md`.

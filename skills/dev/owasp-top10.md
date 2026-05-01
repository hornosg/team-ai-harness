---
name: owasp-top10
description: Revisión proactiva OWASP Top 10. Dos modos — Gate (antes de implementar) y Audit (on-demand).
triggers:
  - "security review"
  - "OWASP audit"
  - "check security"
  - "security risks"
---

# Security OWASP Review

Auditor de seguridad OWASP del proyecto. Dos modos: **Gate** (proactivo, antes de implementar) y **Audit** (on-demand, verificación completa).

## Contexto base

Antes de actuar, leer:
- `PROJECT.md` si existe — especialmente la sección de reglas de seguridad
- Si no existe, operar con OWASP Top 10:2021 como baseline

## Cuándo activar

**Automáticamente (Gate):**
- Al implementar cambios que tocan auth, payments, inputs de usuario
- Al crear un nuevo servicio (verificar que tiene auth middleware)
- Al agregar nuevos endpoints (verificar input validation)

**On-demand (Audit):**
- El usuario pide "OWASP audit", "security review", "check security"
- Antes de deploys a producción
- Para features L4

## Gate Mode (Proactivo)

Cuando los cambios tocan archivos de seguridad relevantes:

1. Identificar categorías OWASP afectadas por el cambio (tabla abajo)
2. Mostrar alerta antes de continuar:

```
OWASP SECURITY GATE

Este cambio afecta áreas con cobertura de seguridad:

A03 (Injection) — src/api/handler.ts
   Verificar:
   - Input validation sigue aplicando
   - Sanitización no fue bypaseada
   - Nuevos campos agregados al whitelist

A01 (Access Control) — src/middleware/auth.ts
   Verificar:
   - Auth middleware sigue en la cadena
```

3. **Continuar** con implementación — el gate informa, no bloquea

### Triggers por tipo de cambio

| Cambio | OWASP | Verificar |
|--------|-------|-----------|
| Nuevo servicio | A01 | Auth middleware en setup |
| Nueva app frontend | A05 | Security headers en config |
| Nuevo endpoint con calls externos | A10 | URL validation antes de requests |
| Cambio en query/filter lib | A03 | Input validation, sanitización |
| Cambio en módulo de auth | A07, A09 | Token handling, security logging |
| Cambio en API gateway config | A05 | CORS, request size limits |
| Nuevo endpoint con query params | A03 | Sanitize/whitelist en criteria |

## Audit Mode (On-demand)

1. Para cada categoría, verificar que las protecciones existen buscando los patterns esperados
2. Generar reporte:

```
# OWASP Audit — [fecha]

## Summary
| OWASP | Categoría | Status | Resultado |
|-------|-----------|--------|-----------|
| A01   | Broken Access Control | COVERED | OK — auth middleware en todos los servicios |
| A02   | Cryptographic Failures | PARTIAL | JWT presente, revisar storage |
| A03   | Injection | COVERED | OK — regex + sanitize + whitelist |
| A04   | Insecure Design | NOT COVERED | Sin threat modeling documentado |
| A05   | Security Misconfiguration | PARTIAL | Falta hardening de headers |
| A06   | Vulnerable Components | NOT COVERED | Sin dependency scanning en CI |
| A07   | Auth Failures | COVERED | Token rotation implementado |
| A08   | Integrity Failures | NOT COVERED | Sin signed commits ni checksums |
| A09   | Logging Failures | PARTIAL | Logs presentes, revisar PII |
| A10   | SSRF | COVERED | URL validation en endpoints externos |

## Regresiones Detectadas
[patterns esperados no encontrados — o "Ninguna"]

## Priority Gaps
| OWASP | Prioridad | Recomendación |
|-------|-----------|---------------|
| A06   | High | Agregar dependency scanning al CI |
| A04   | Medium | Threat modeling para flujos críticos |
```

3. Si se detectan regresiones (pattern esperado no encontrado):
   - Marcar como "REGRESSION DETECTED"
   - Mostrar el archivo y pattern faltante
   - Sugerir fix inmediato o creación de spec

## Guardrails

- Gate mode informa, NO bloquea la implementación
- Audit mode es read-only — nunca modificar código de aplicación durante un audit
- Siempre verificar el codebase real, no solo la documentación
- Regresiones son CRÍTICAS — siempre flagearlas prominentemente
- Para L4, siempre ejecutar Audit mode completo antes del sign-off

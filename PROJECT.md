---
schema: project/v1
version: 0.1.0
status: draft
last_updated: [FECHA]
authority: maximum
---

# PROJECT.md — [NOMBRE DEL PROYECTO]

> **Fuente única de verdad.** Agentes y specs REFERENCIAN IDs definidos aquí (P-XX, G-XX, RULE-XX, STACK-XX, SVC-XX) — nunca los repiten ni parafrasean.
>
> **Jerarquía:** PROJECT.md → management/rules/ → specs/ADRs → agentes. En conflicto, gana el nivel superior.
>
> **Modificación:** solo el owner o @architect pueden proponer cambios. Todo cambio en P-XX o RULE-XX requiere revisión explícita.

---

## 1. Identidad

| Atributo | Valor |
|----------|-------|
| **Nombre** | [NOMBRE] |
| **Propósito** | [Qué problema resuelve en una oración] |
| **Promesa** | "[Tagline corto]" |
| **Misión actual** | [Objetivo concreto para los próximos 3-6 meses] |
| **Audiencia primaria** | [Quién lo usa, con detalles específicos] |
| **Mercado / región** | [País, ciudad, industria si aplica] |
| **Fase actual** | [Alpha / Beta / MVP / Producción / Escala] |

---

## 2. Estructura del proyecto

### Modo

```yaml
mode: monorepo          # monorepo | multirepo | hybrid
```

### Para monorepo

```yaml
raiz: /
apps:
  - nombre: api-gateway
    path: apps/api-gateway
    descripcion: [qué hace]
  - nombre: frontend-web
    path: apps/frontend-web
    descripcion: [qué hace]
packages:
  - nombre: shared-types
    path: packages/shared-types
```

### Para multirepo

```yaml
repos:
  - nombre: [servicio-a]        # SVC-01
    path: ../[servicio-a]       # path relativo a management/
    descripcion: [qué hace]
    stack: [tech principal]
  - nombre: [servicio-b]        # SVC-02
    path: ../[servicio-b]
    descripcion: [qué hace]
    stack: [tech principal]
```

### OpenSpec (si aplica)

```yaml
openspec:
  root: ./openspec
  changes: ./openspec/changes
```

---

## 3. Stack tecnológico (STACK-XX)

| ID | Tecnología | Capa / Uso | Versión | Estado |
|----|-----------|-----------|---------|--------|
| STACK-01 | [ej: Node.js / Go / Java] | Backend principal | [versión] | CONFIRMADO |
| STACK-02 | [ej: React / Next.js / Vue] | Frontend | [versión] | CONFIRMADO |
| STACK-03 | [ej: PostgreSQL / MongoDB] | Base de datos principal | [versión] | CONFIRMADO |
| STACK-04 | [ej: Redis] | Cache / Sessions | [versión] | CONFIRMADO |
| STACK-05 | [ej: Docker / K8s] | Infraestructura | [versión] | CONFIRMADO |
| STACK-06 | [ej: Kong / Nginx] | API Gateway | [versión] | CONFIRMADO |

> **MENCIONADO** = aparece en contexto sin decisión formal. **CONFIRMADO** = decisión explícita de arquitectura.

---

## 4. Servicios / Repos (SVC-XX)

> Sección para multirepo o monorepo con apps independientes.

| ID | Nombre | Path | Descripción | Stack | Estado |
|----|--------|------|-------------|-------|--------|
| SVC-01 | [nombre] | [../path o apps/path] | [qué hace] | [tech] | ACTIVO |
| SVC-02 | [nombre] | [../path o apps/path] | [qué hace] | [tech] | ACTIVO |

---

## 5. Principios (P-XX)

> Tier S = no negociables. Tier A = importantes, requieren ADR para excepción. Tier B = preferencias fuertes.

### Tier S — No negociables

- **P-01 — Anti-duplicación:** Specs y agentes referencian IDs de PROJECT.md — NUNCA reescriben ni parafrasean.
- **P-02 — Ambigüedad resuelta antes de ejecutar:** Cambios sin criterios de aceptación claros no se implementan. Dudas → `clarify_questions.md`.
- **P-03 — Trazabilidad:** L2+ usa FILE-ID → TEST-ID → spec. Nada se implementa sin poder rastrearlo a un requerimiento.
- **P-04 — [AGREGAR: ej: Hexagonal en todo backend]**
- **P-05 — [AGREGAR: ej: Todo tráfico pasa por el API Gateway]**

### Tier A — Importantes

- **P-10 — [AGREGAR: ej: PostgreSQL como DB operacional principal]**
- **P-11 — [AGREGAR: ej: Atomic Design en frontends]**

### Tier B — Preferencias fuertes

- **P-20 — [AGREGAR: ej: Prefer TypeScript sobre JavaScript]**

---

## 6. Glosario (G-XX)

| ID | Término | Definición canónica |
|----|---------|-------------------|
| G-01 | [Término clave del negocio] | [Definición precisa — única fuente de verdad] |
| G-02 | [Término técnico del dominio] | [Definición] |
| G-03 | [Entidad central] | [Definición con relaciones] |

> El glosario establece la terminología canónica. Agentes y devs usan estos términos — no sinónimos.

---

## 7. Reglas transversales (RULE-XX)

- **RULE-01 — L4 para money/auth:** Cualquier cambio que toque pagos, autenticación, tokens, datos sensibles → L4. @architect + @security ambos requeridos.
- **RULE-02 — Sin secretos en código:** API keys, passwords, tokens → variables de entorno o vault. Nunca hardcodeados.
- **RULE-03 — Sin PII en logs:** Logs no contienen emails, nombres, documentos, números de tarjeta.
- **RULE-04 — Multi-tenant:** [SI APLICA — toda tabla con datos de negocio incluye tenant_id]
- **RULE-05 — [AGREGAR regla específica del proyecto]**

---

## 8. Arquitectura (resumen ejecutivo)

> Para detalles completos, ver `management/rules/architecture.md`.

```
[Diagrama ASCII o descripción del flujo principal]

Ejemplo:
  Cliente → API Gateway → [Servicio A] → [DB]
                        → [Servicio B] → [DB]
```

**Patrón:** [ej: Hexagonal + DDD / Clean Architecture / MVC]
**Comunicación entre servicios:** [ej: REST sobre Kong / gRPC / eventos via Kafka]

---

## 9. Tono y voz (para agentes de marketing)

| Atributo | Descripción |
|---------|-------------|
| **Personalidad** | [ej: cercano, técnico pero no frío, honesto] |
| **Audiencia** | [a quién le habla la marca] |
| **Tono** | [ej: conversacional, sin jerga corporativa] |
| **Evitar** | [ej: términos de startup, promesas vacías] |
| **Diferenciadores** | [qué hace único al producto] |

---

## 10. Integraciones críticas

| Sistema | Tipo | Scope | Responsable |
|---------|------|-------|-------------|
| [ej: Stripe / MP] | Pagos | L4 — @security obligatorio | SVC-XX |
| [ej: Auth0 / Cognito] | Identidad | L4 — @security obligatorio | SVC-XX |
| [ej: SendGrid] | Email | L2 | SVC-XX |

---

## 11. Compliance y regulatorio

> Completar si aplica. Omitir si el proyecto no tiene requisitos específicos.

- **[ej: PCI DSS]**: [scope y qué aplica]
- **[ej: GDPR / Ley 25.326]**: [consentimiento, derecho al olvido]
- **[ej: BCRA]**: [retención de logs, reporte de operaciones inusuales]

---

## 12. Decisiones pendientes

| ID | Tema | Pregunta | Responsable | Deadline |
|----|------|---------|-------------|---------|
| D-01 | [tema] | [qué hay que decidir] | @architect | [fecha] |

---

## Gobernanza

- Solo @architect o el owner pueden proponer cambios a P-XX o RULE-XX
- Cambios en STACK-XX requieren ADR explícito
- Ningún agente modifica este archivo — solo propone cambios via pull request
- Todo elemento nuevo recibe un ID secuencial inmutable

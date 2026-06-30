---
name: promote-to-platform
description: Procedimiento para promover un servicio de un proyecto (hoy en active/mercado-cercano/services/) a SERVICIO DE PLATAFORMA cross-project del lab (Devy / "products as a service"). Decide si califica, baja ceremony level (L4 si toca identidad/auth/tenant/money/RLS), define el contrato (Published Language), lo extrae a infra/, lo registra en la plataforma (Kong, lab-network, lab-postgres, observabilidad), migra a los consumidores para CORTAR la divergencia, y cierra gobernanza (docs + roadmap + memoria). Triggers — "promover servicio a plataforma", "promote service to platform", "promocionar X a cross-project", "graduar un servicio a infra", "convertir en servicio de plataforma", "products as a service".
triggers:
  - "promover servicio a plataforma"
  - "promote to platform"
  - "promocionar X a cross-project"
  - "graduar servicio a infra"
  - "products as a service"
ceremony: L4-condicional
---

# Promote to Platform — promoción de un servicio a la plataforma del lab

> Este skill **no reimplementa** el servicio: orquesta su **graduación** de "servicio de un proyecto"
> a "servicio de plataforma" consumido por contrato por todos los proyectos. La doctrina vive en
> `management/rules/platform-architecture.md` (§1 plataforma-como-producto, §3 multitenancy bridge,
> §4 anatomía, §5 shared kernel, §6 golden path, §7 prod). Acá vive el **procedimiento ejecutable**:
> a quién, en qué orden, con qué gates.

## Modelo mental (no saltear)

Promover ≠ mover una carpeta. Es decidir que algo deja de ser **dominio de un proyecto** y pasa a ser
**contrato estable de plataforma** (Published Language, §2b/§5) del que cuelgan otros proyectos.
La regla de oro de la plataforma: **favorecer contratos sobre código compartido**. Un servicio de
plataforma es una **caja negra X-as-a-Service** (TVP, §10): se consume por su interfaz, no se
reconfigura al arrancar un POC.

El driver del owner para esto: **una sola fuente de verdad**. Tener dos modelos del mismo concepto
(p.ej. dos modelos de `tenant`) en dos servicios = divergencia garantizada. La promoción existe para
**colapsar a una fuente única** y migrar a todos a consumirla.

### Precedentes (mantener esta tabla al día)

| Servicio | Estado | Repo | Ubicación | Notas |
|----------|--------|------|-----------|-------|
| `api-gateway` (Kong) | ✅ promovido | `git@github.com:hornosg/api-gateway.git` | `infra/api-gateway` | Kong declarativo DB-less, README+OpenAPI, k8s/, CI. Plataforma pura → org personal. |
| `tenant-service` | ❌ evaluado → NO promovido | `git@github.com:mercadocercano/tenant-service.git` | queda en `active/mercado-cercano/services/` | **L4 architect+security (2026-06-21):** la premisa "tenant duplicado" era falsa. IAM posee la tabla `tenants` (identidad); tenant-service solo tiene `tenant_config`/`tenant_settings`/`points_of_sale` (config fiscal AFIP/POS = **dominio MC**). Falla el Gate Fase 0 → no se promueve, queda en `mercadocercano/*` (se renombra a `tenant-config-service`). En su lugar: formalizar el contrato de tenant-identidad de IAM (Published Language + ACL). Ver ADR-004, obs Engram #299/#305. |
| `iam-service` | ✅ promovido | `git@github.com:hornosg/iam-service.git` | `platform/iam-service` | **L4 (2026-06-21):** Published Language de identidad del lab. Repo público bajo `hornosg/*`. Ver ADR-002. |
| `notification-service` | ✅ promovido | `git@github.com:hornosg/notification-service.git` | `platform/notification-service` | **L4 (2026-06-25):** servicio cross-project de notificaciones email/SMS. Contrato HTTP `/api/v1/notifications` + evento `onboarding.tenant.registered` v1. Registrado en Kong `/notification-service`, Prometheus job `notification-service`, DB user `notification_service`. Consumidor migrado: `onboarding-service` enruta vía `lab-kong:8000/notification-service`. Ver ADR-001 en `platform/notification-service/docs/adr/ADR-001-promote-to-platform.md`. |

---

## Fase 0 — Gate de promoción (¿califica? + ceremony level)

**No todo se promueve.** Antes de tocar nada, responder:

1. **¿Es genérico y estable, o dominio de un proyecto?**
   - Genérico + estable + transversal (auth, tenants, notificaciones, gateway, logging) → **candidato**.
   - Dominio de un proyecto (catálogo, ventas, stock de MC) → **NO se promueve**. Va a `go-shared-mc`
     o se queda en el proyecto (§5, regla 2). Caso real: `domain/businesstype`/`category` bajaron a
     `go-shared-mc`, no subieron a plataforma.
2. **¿Lo consumen (o consumirían) ≥2 proyectos / bounded contexts?** Si solo lo usa uno y no hay un
   segundo a la vista, no promuevas "por las dudas" (mismo criterio que `tenant_id`, §3).
3. **¿Es un contrato (Published Language) o solo código?** Si lo correcto es compartir *código* y no
   *un servicio corriendo* → es `go-shared`/`go-shared-mc`, no una promoción. Promover = el servicio
   corre una sola vez y los demás le hablan por red.

**Ceremony level (decide quién participa):**

| Señal en el servicio | Nivel | Obligatorio |
|----------------------|-------|-------------|
| Identidad, auth, sesiones, tokens, **tenant/tenant_id**, RLS, pagos/dinero, compliance | **L4** | `@dev-architect` + `@dev-security`, provider `claude-opus-4-8` |
| Cambio arquitectural/migración sin los keywords de arriba | L3 | `@dev-architect` |
| Servicio acotado y sin estado crítico | L2 | `@dev-technical-leader` |

> Promover toca el **blast-radius de todos los proyectos** → el piso realista es **L3**, y cualquier
> cosa de identidad/tenant/auth es **L4 sin excepción** (regla de oro del `@meta-router`).

**Salida de Fase 0:** PROPUESTA en `management/roadmap/propuestas/` (trabajo no planificado → propuesta
antes de ejecutar; ver skill `roadmap-management`). La propuesta la redacta el architect en Fase 1.

---

## Fase 1 — Diseño del contrato (Published Language)  ·  L3/L4 con architect (+ security)

La parte difícil. Lo único que protege contra la divergencia es un **contrato explícito**.

1. **Resolver la fuente única.** Si el concepto ya vive en otro servicio (p.ej. la entidad tenant en
   IAM **y** en `tenant-service`), decidir: ¿el servicio promovido es la única fuente y el otro lo
   consume vía **ACL** (Anti-Corruption Layer, §2b — patrón ya usado en IAM: `TenantFeaturesAdapter`),
   o se fusionan? Sin esta decisión, no hay promoción real, solo otro modelo más.
2. **Definir la interfaz publicada:** endpoints/eventos, DTOs, versionado, y **qué NO expone**. Es
   lenguaje común, versionado y estable (§4 IAM como ejemplo: JWT con `tenant_id`).
3. **Definir cómo lo consumen los proyectos:** por contrato (HTTP vía Kong / evento / gateway de
   `go-shared`), nunca cross-DB SQL entre proyectos (§4, regla de aislamiento de datos).
4. **Producir el ADR** (decisión + criterios de aceptación) y la propuesta de roadmap. Para L4,
   `@dev-security` valida superficie de ataque, flujos de identidad y aislamiento.

**Gate Fase 1:** ADR aprobado con criterios de aceptación medibles + decisión de fuente única tomada.

---

## Fase 2 — Extracción y ubicación (repo + org)

Calcado del precedente `api-gateway`:

1. **Repo propio.** Si aún no lo tiene, extraer a su repo con historia. (`tenant-service` ya es repo
   propio — saltear.)
2. **Ubicación física.** Servicio de plataforma → fuera de `active/<proyecto>/services/`. Destino:
   `infra/<servicio>` (como `infra/api-gateway`) si es infra base, o `platform/<servicio>` para
   servicios de plataforma producto (precedentes: `platform/iam-service`, `platform/notification-service`).
   Deja de vivir bajo el monorepo de un proyecto.
3. **Org del repo y visibilidad — REGLA DEL OWNER (no negociable).**
   - Un servicio que se promueve a `infra/` **o** que es **cross-tenant/plataforma** → pasa a la org
     **`hornosg/*`** y se vuelve **público**. Es lo que significa "graduarse a plataforma":
     deja de pertenecer a un proyecto. Precedente: `hornosg/api-gateway`.
   - Si NO califica para promoción (conserva acoplamiento al dominio de un proyecto) → **se queda
     donde está** (`mercadocercano/*`, dentro del proyecto). No se mueve.
   - El corolario práctico: si dudás de si moverlo a `hornosg`+público, probablemente **no califica**
     (Fase 0). La promoción y el cambio de org/visibilidad van juntos, no por separado.
4. **Higiene 12-factor / orquestador-agnóstico** (§7): stateless, config por env, misma imagen
   dev/staging/prod. Es lo que hace barato el puente compose↔k3s.

---

## Fase 3 — Registro en la plataforma (golden path, §6)

Que el servicio sea ciudadano de primera de la plataforma compartida:

- [ ] **lab-network**: `networks: { lab-network: { external: true } }` + labels
      `logging=promtail` + `service_name=<svc>`.
- [ ] **Kong** (`infra/kong/kong.yml`): `service` + `route` `/<svc>` con `strip_path: true`; recargar
      sin restart (`curl -X POST http://localhost:8001/config -F config=@infra/kong/kong.yml`).
      *(tenant-service ya está en kong.yml líneas ~94, puerto 8120.)*
- [ ] **DB** (si tiene estado): una DB + un user en `lab-postgres` (`CREATE DATABASE <svc>; CREATE
      USER <svc> ...`). Nunca cross-DB entre proyectos.
- [ ] **Redis** (si usa): prefijo `<proyecto|plataforma>:<tenant_id>:<recurso>` (§9 D-04).
- [ ] **Observabilidad**: scrape en `observability/prometheus/prometheus.yml` (recargar:
      `curl -X POST http://localhost:9090/-/reload`), métricas **RED**, y **canonical logs ADR-001**
      (envelope común — skill `canonical-logs-go`/`-python`).
- [ ] **go-shared genérico** para auth/notif/logging; **jamás** `go-shared-mc` si es plataforma pura.

---

## Fase 4 — Migración de consumidores (CORTAR la divergencia)

El paso que justifica todo. Sin esto quedan dos fuentes y empeoraste el problema.

1. **Inventariar consumidores** del concepto duplicado (qué proyectos/servicios tienen su propio
   modelo). `grep` por el modelo/tabla/DTO en el lab.
2. **ACL en cada consumidor**: traducir el contrato publicado al modelo interno sin contaminar el
   dominio (patrón `TenantFeaturesAdapter` de IAM).
3. **Plan de corte**: orden, feature-flag si hace falta, y verificación de que la **fuente vieja
   queda de solo-lectura / se elimina**. El éxito de la promoción = **una sola fuente activa**.
4. Cerrar cada consumidor con build + tests verdes antes del siguiente. *(Recordatorio operativo:
   contenedores Go corren con `air` sin bind-mount → rebuild de imagen tras cambios:
   `export GITHUB_TOKEN=$(gh auth token); docker compose build <svc>`.)*

---

## Fase 5 — Aislamiento + production-readiness (si multi-tenant / L4)

- [ ] **RLS fail-closed** (E07 / RULE-09/RULE-10, §3): `ENABLE` + `FORCE ROW LEVEL SECURITY`, policy
      `tenant_isolation` con `current_setting('app.tenant_id')`, y `SET app.tenant_id` por transacción
      tras validar el JWT (el `tenant_id` sale del token, nunca de input del cliente).
- [ ] **Separación control/app-plane** (RULE-09): rol de app **sin DDL**; provisioning con rol
      privilegiado separado, fuera del path de request.
- [ ] **Break-glass auditable** para `system_admin` (cross-tenant): policy explícita + todo acceso
      queda en canonical logs. El aislamiento nunca encierra al owner.
- [ ] **Production-readiness scorecard** (E08, §10): canonical logs ✓ · RLS/aislamiento activo ✓ ·
      métricas RED ✓ · secrets en env/vault, nunca en código (RULE-02) ✓.

---

## Fase 6 — Gobernanza (cerrar el loop)

- [ ] **`platform-architecture.md`**: agregar el servicio a la anatomía (§4) con su contrato, y
      tachar/actualizar lo que corresponda en §9 (decisiones abiertas).
- [ ] **Roadmap**: cerrar la propuesta → estado de la épica (`roadmap.yaml`).
- [ ] **Tabla de precedentes** de este skill: pasar el servicio a ✅.
- [ ] **Memoria Engram** (`mem_save`): decisión de promoción, contrato resuelto, fuente única,
      consumidores migrados. `mem_session_summary` al cerrar.

---

## Checklist GO (gate final de promoción)

Un servicio está **promovido** solo si TODO es verdadero:

- [ ] Califica (Fase 0) y pasó por el ceremony level correcto (L4 si identidad/tenant/auth).
- [ ] Tiene **contrato publicado y versionado** (Published Language), no solo código compartido.
- [ ] **Una sola fuente activa** del concepto — la divergencia quedó cortada (Fase 4).
- [ ] Registrado en plataforma: Kong + lab-network + (DB/Redis si aplica) + observabilidad RED + canonical logs.
- [ ] Si multi-tenant: RLS fail-closed + control/app-plane + break-glass auditable.
- [ ] Gobernanza cerrada: docs + roadmap + memoria.

## Cuándo NO usar este skill

- El concepto es **dominio de un proyecto** → `go-shared-mc` o se queda en el proyecto.
- Solo querés **compartir código**, no correr un servicio → `go-shared`/`go-shared-mc` (es un import,
  no una promoción).
- Solo lo usa **un** proyecto y no hay un segundo consumidor a la vista → no promover por las dudas.

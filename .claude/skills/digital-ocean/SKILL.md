---
name: digital-ocean
description: Deploy e infraestructura en Digital Ocean. App Platform vs Droplets, doctl, managed databases, Spaces, secretos/env, redes privadas (VPC), y control de costos. Invocar al planificar deploy, infra-as-code, o decisiones de plataforma en DO.
triggers:
  - "digital ocean"
  - "droplet"
  - "app platform"
  - "doctl"
  - "deploy"
  - "infra"
  - "spaces"
  - "managed database"
---

# Digital Ocean — Deploy e Infraestructura

> Dueño: agente `dev-devops`. Cambios de infra que toquen secretos, redes de servicios de pago o datos sensibles → **L4**. Todo lo de infra se versiona y se aplica de forma reproducible — nada de cambios manuales en el panel sin dejar rastro.

## Decisión central: App Platform vs Droplets

| | **App Platform** (PaaS) | **Droplets** (IaaS) |
|---|---|---|
| Cuándo | Servicios stateless (Go/Python APIs, frontends), deploy desde git, escalado simple | Necesitás control total: Kong, Prometheus/Grafana/Loki, Docker Compose, sidecars, puertos custom |
| Pros | Build+deploy gestionado, TLS automático, scaling con un slider, menos a mantener | Control total, cualquier proceso, más barato a escala, redes privadas finas |
| Contras | Menos control, más caro por unidad de cómputo, opinado | Vos mantenés OS, parches, hardening, backups |

Patrón típico para tu stack: **APIs Go/Python en App Platform** (o en Droplets con Docker si querés colocarlas con el gateway), **Kong + stack de observabilidad (Prometheus/Grafana/Loki) en Droplets** dentro de una VPC privada, **managed DB** para Postgres y **Spaces** para storage de objetos/logs.

## doctl: CLI como fuente de verdad

```bash
doctl auth init                                   # autenticar (token via env, no hardcodeado)
doctl apps create --spec app.yaml                 # App Platform desde spec versionado
doctl apps update <app-id> --spec app.yaml        # actualizar (revisar diff en PR antes)
doctl compute droplet create ... --vpc-uuid <id>  # Droplet dentro de la VPC
doctl databases create ... --engine pg            # managed Postgres
```

App Platform spec versionado (`app.yaml`):
```yaml
name: orders-api
region: nyc
services:
  - name: api
    github: { repo: org/orders, branch: main, deploy_on_push: true }
    build_command: "go build -o bin/api ./cmd/api"
    run_command: "./bin/api"
    instance_size_slug: basic-xxs       # empezá chico, escalá con datos
    instance_count: 2                   # >1 para HA
    health_check: { http_path: /healthz }
    envs:
      - { key: DB_URL, scope: RUN_TIME, type: SECRET }   # SECRET, nunca en texto
```

## Redes privadas (VPC) — no negociable

- Todos los servicios internos (DB, Kong admin, Prometheus, Loki) viven en una **VPC privada**.
- **Solo el gateway (Kong) y los frontends exponen puertos públicos.** La Admin API de Kong, las DBs y el stack de observabilidad nunca tienen IP pública.
- Firewalls de DO: allowlist explícita; default deny.

## Managed Databases

- Preferí **managed Postgres** sobre DB en Droplet: backups automáticos, failover, parches gestionados.
- Conexión por red privada (VPC), nunca pública.
- Usá **connection pooling** (PgBouncer gestionado de DO) para servicios con muchas conexiones — relación con la métrica de saturación de pool (skill `prometheus`).
- Restringí el acceso por IP/VPC y usuarios con mínimo privilegio.

## Spaces (object storage S3-compatible)

- Storage de objetos para uploads, backups y **logs de Loki** (barato y escalable).
- Credenciales por env/secret, con allowlist de buckets.
- CDN integrado si servís estáticos.

## Secretos y configuración

- **Nunca** secretos en el repo ni en specs en texto plano (ver `rules/security.md`).
- App Platform: env vars tipo `SECRET`. Droplets: vault / archivo `.env` fuera de git con permisos restringidos, o referencias de vault de Kong.
- Rotación de credenciales documentada; tokens de `doctl` con scope mínimo.

## Control de costos

- Empezá con slugs/Droplets chicos; escalá con datos de saturación (métricas), no por las dudas.
- Apagá entornos de staging fuera de horario si aplica.
- Spaces + lifecycle para expirar logs viejos (alinea con retención de Loki).
- Revisá el billing mensual; etiquetá recursos por servicio para atribuir gasto.
- El agente `dev-devops` reporta costos cloud como parte de su responsabilidad.

## Deploy: reglas

1. Deploy reproducible desde spec/IaC versionado, revisado en PR.
2. Health checks (`/healthz`) obligatorios; sin health check no hay rolling deploy seguro.
3. `instance_count >= 2` para servicios de producción (HA).
4. Rollback claro: spec anterior versionado o redeploy de la imagen previa.
5. Marcá el deploy como anotación en Grafana (skill `grafana`) para correlacionar regresiones.
6. Cambios que tocan pago/auth/datos sensibles → L4 (@architect + @security).

## Checklist de infra lista

1. ¿VPC privada con solo gateway/frontend públicos?
2. ¿Admin de Kong, DB y observabilidad sin IP pública?
3. ¿Secrets por env/vault, no en specs?
4. ¿Managed DB con backups y conexión privada?
5. ¿Health checks + instance_count ≥ 2 en prod?
6. ¿Spec/IaC versionado y revisado, sin cambios manuales sueltos?
7. ¿Retención de logs en Spaces con lifecycle?

## Integración con el stack

- Corre **Kong** (skill `kong`) y el **stack de observabilidad** (skills `prometheus`, `grafana`, `loki`, `observability-stack`).
- Aloja servicios **Go** y **Python** (skills `hexagonal-go`, `hexagonal-python`).
- CI/CD y hardening: dueño `dev-devops`.

---
name: dockerfile-audit
description: Auditoría y remediación de Dockerfiles contra 5 checks de buenas prácticas (imagen base, cache de capas, .dockerignore/multi-stage, estandarización de versión, un proceso por contenedor). Gate (al crear/editar un Dockerfile) y Audit (barrido completo on-demand).
triggers:
  - "auditá los Dockerfile"
  - "revisá las imágenes base"
  - "chequeá el Dockerfile"
  - "optimizá el Dockerfile"
  - "docker best practices"
---

# Dockerfile Audit

Auditor de buenas prácticas de Dockerfiles. Dos modos: **Gate** (proactivo, al crear o tocar un
Dockerfile) y **Audit** (on-demand, barrido completo de un path).

Origen: 5 recomendaciones prácticas de un video de referencia sobre errores comunes en
Dockerfiles (imagen base, cache, `.dockerignore`/multi-stage, pinning de versión, un proceso por
contenedor) — ver checks abajo.

## Los 5 checks

### 1. Imagen base correcta
- **Qué verifica**: que la imagen base sea apropiada para el lenguaje y el rol del stage
  (build vs runtime).
- **Cómo detectarlo**: `grep -n "^FROM" <Dockerfile>` — flagear cualquier `alpine` en un
  lenguaje con dependencias C (Python, Node con paquetes nativos) por incompatibilidad
  musl/glibc; flagear un stage final "gordo" (imagen completa de lenguaje) cuando el binario es
  estático y podría ser `scratch`/`distroless`.
- **Severidad por defecto**: Alto si Alpine + dependencias C nativas; Medio si el stage final no
  usa distroless/scratch pudiendo hacerlo (Go/Rust estático).

### 2. Cache de capas (layer caching)
- **Qué verifica**: que los archivos de manifest/lock (`go.mod`/`go.sum`, `package.json`+lock,
  `requirements.txt`, `pyproject.toml`) se copien e instalen ANTES de `COPY . .` / copiar el
  resto del source.
- **Cómo detectarlo**: leer el Dockerfile completo — si aparece `COPY . .` (o un `COPY` amplio
  del código fuente) antes del `RUN` de instalación de dependencias, es una violación.
- **Severidad por defecto**: Medio (no rompe el build, pero invalida cache en cada cambio de
  código y hace lento el ciclo de desarrollo).

### 3. `.dockerignore` + multi-stage
- **Qué verifica**: (a) existe un `.dockerignore` en el build-context real del Dockerfile
  (revisar `context:` en `docker-compose.yml` o el comando `docker build -f ... <context>`
  documentado en el propio archivo — el context NO siempre es el directorio del Dockerfile);
  (b) si el Dockerfile compila algo (Go, Java, binarios, bundlers de frontend), usa multi-stage
  separando build de runtime en vez de dejar herramientas de build en la imagen final.
- **Cómo detectarlo**: `find <context> -maxdepth 1 -iname ".dockerignore"`; contar `FROM` en el
  Dockerfile (1 = single-stage, posible violación si hay un paso de compilación).
- **Severidad por defecto**: Medio si falta `.dockerignore`; Alto si falta multi-stage y el
  Dockerfile compila binarios/assets (imagen final innecesariamente grande y con superficie de
  ataque mayor).

### 4. Pinning / estandarización de versión
- **Qué verifica**: que no haya N variantes de la misma imagen base dando vueltas en el mismo
  proyecto/ecosistema (ej. `python:3.11-slim` en un servicio y `python:3.12-slim` en otro).
- **Cómo detectarlo**: agrupar todos los `FROM` del path auditado por familia de imagen
  (golang, python, node, alpine, debian) y listar las versiones distintas encontradas por
  familia.
- **Nota de este lab**: NO se pinea por digest SHA (ver "Reglas de estandarización" abajo) — el
  control de versión se hace estandarizando el tag, no fijando el hash. Pinning por digest queda
  como recomendación opcional, documentada pero no aplicada por defecto (aumenta el
  mantenimiento: hay que resolver y actualizar el SHA a mano en cada bump).
- **Severidad por defecto**: Bajo-Medio (no es un bug, es deuda de consistencia) salvo que la
  imagen no estandarizada esté además en estado EOL/sin soporte (ver check de imagen base).

### 5. Un proceso por contenedor
- **Qué verifica**: que el contenedor corra un solo proceso salvo excepción justificada.
- **Cómo detectarlo**: revisar `CMD`/`ENTRYPOINT` — si arranca más de un proceso de larga vida
  (ej. nginx + backend) sin un supervisor explícito (`supervisord`, `s6-overlay`), flagear.
- **Excepción válida**: fuera de Kubernetes, combinar un server web + backend con un gestor de
  procesos tipo `supervisord` es aceptable si añadir esa complejidad evita duplicar
  infraestructura de orquestación. No aplicar este check como bloqueante — es criterio, no regla
  dura.
- **Severidad por defecto**: Bajo — informativo salvo que se detecten dos procesos de larga vida
  sin supervisor (ahí sube a Medio).

## Reglas de estandarización de este lab

Decididas con el owner (2026-07-24) para `active/` + `platform/` — no genéricas, específicas de
este lab, así una futura auditoría no tiene que re-preguntar:

| Rol del stage | Estándar | Por qué |
|---|---|---|
| Build de Go | `golang:1.25-bookworm` | Se descarta tras compilar — el tamaño no importa, y elimina cualquier duda de compatibilidad musl/glibc para dependencias con CGO |
| Runtime final de Go | `gcr.io/distroless/static-debian12:nonroot` | Ya es el patrón de `pim-service`/`iam-service`/`onboarding-service` — sin shell, sin package manager, superficie de ataque mínima |
| Migración/tooling (necesita shell + cliente psql/bash) | `debian:bookworm-slim` | No puede ser distroless (sin shell) pero tampoco necesita la imagen completa de Go/Python |
| Python (build y runtime) | `python:3.12-slim` | Debian-based (glibc), evita el problema musl de Alpine con dependencias C, y estandariza la versión en todo el lab |

Nunca usar Alpine en este lab, ni siquiera en stages de build de Go que en teoría no sufren el
problema musl/glibc (el binario final es estático) — se prioriza consistencia total sobre el
ahorro marginal de tamaño en un stage que de todos modos se descarta.

## Gate Mode (Proactivo)

Al crear o editar un Dockerfile:

1. Correr los 5 checks sobre ese archivo (y su `.dockerignore` si corresponde).
2. Si el archivo está bajo `active/` o `platform/`, comparar además contra la tabla de
   estandarización del lab.
3. Mostrar alerta antes de continuar:

```
DOCKERFILE AUDIT GATE — <path>

1. Imagen base — <OK | ALERTA: detalle>
2. Cache de capas — <OK | ALERTA: detalle>
3. .dockerignore/multi-stage — <OK | ALERTA: detalle>
4. Estandarización de versión — <OK | ALERTA: detalle>
5. Un proceso por contenedor — <OK | N/A>
```

4. **Continuar** con la implementación — el gate informa, no bloquea.

## Audit Mode (On-demand)

1. `find <path> -iname "Dockerfile*" -not -path "*/node_modules/*" -not -path "*/.git/*"`
2. Para cada archivo, correr los 5 checks y anotar severidad.
3. Generar reporte:

```
# Dockerfile Audit — [fecha] — [path auditado]

## Summary
| Archivo | Base image | Cache | .dockerignore/multi-stage | Versión estandarizada | Severidad máxima |
|---|---|---|---|---|---|
| services/x/Dockerfile | OK | OK | Falta .dockerignore | OK | Medio |

## Hallazgos por severidad
### Alto
- [archivo] — [check] — [detalle]

### Medio
...

## Recomendaciones no aplicadas (fuera de alcance o requieren decisión del owner)
- [ej. pinning por digest SHA — documentado, no aplicado]
```

4. Si el path auditado incluye proyectos fuera de `active/`/`platform/` (ej. `other/`, `pocs/`),
   el reporte es **solo informativo** — nunca modificar esos archivos sin pedido explícito.

## Guardrails

- Gate mode informa, NO bloquea la implementación.
- Audit mode es read-only por defecto — la remediación es un paso separado y explícito.
- Nunca tocar `other/` ni `pocs/` (proyectos legacy/referencia) sin pedido explícito del owner —
  ver convención de `active/` vs `other/`/`pocs/` en `PROJECT.md` del lab.
- Hallazgos de **seguridad** (secretos horneados en la imagen — `COPY .env`, credenciales
  hardcodeadas) se aplican siempre de inmediato, sin esperar confirmación de alcance general:
  son un incidente, no una mejora de estilo.
- Nunca aplicar un cambio que pueda romper el build sin intentar verificarlo (`docker build` o,
  si no hay credenciales/red disponibles, al menos `docker build --check`).
- Al estandarizar versiones, mantener el patrón exacto ya validado en el servicio "golden" del
  ecosistema (hoy: `pim-service` para el patrón Go deps→builder→distroless) en vez de inventar
  uno nuevo.

## Herramientas complementarias (opcional)

`d-roast` — CLI de auditoría de Dockerfiles en Rust, da warnings/sugerencias automáticas. Útil
como segunda opinión, pero no es una dependencia del skill — si no está instalada, se sigue el
proceso manual de arriba sin bloquear.

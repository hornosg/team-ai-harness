---
name: docs-organize
description: Organiza la documentación de un proyecto en una estructura /docs/ con carpetas semánticas (adr, architecture, api, setup, runbooks, guides). Usar cuando el usuario pide "organizá los docs", "creá la estructura de documentación", "registrá una decisión de arquitectura", "escribí un ADR", "documentá la arquitectura", "creá el /docs", "dónde pongo esta doc", o cuando se detecta documentación dispersa en el README, comentarios inline, o archivos .md sueltos que no tienen estructura clara.
---

# docs-organize

Pipeline: discovery → clasificación → estructura → migración / escritura → índice.

## Estructura canónica `/docs/`

```
docs/
├── README.md                  ← índice navegable de toda la doc
├── adr/                       ← Architecture Decision Records
│   └── ADR-NNN-titulo.md
├── architecture/              ← diagramas, componentes, flujos
│   └── overview.md
├── api/                       ← contratos de API (si no hay OpenAPI ya)
│   └── endpoints.md
├── setup/                     ← instalación, configuración, variables de entorno
│   └── getting-started.md
├── runbooks/                  ← operaciones, incidentes, tareas recurrentes
│   └── <tarea>.md
└── guides/                    ← how-to para desarrolladores del proyecto
    └── <guia>.md
```

Las carpetas `api/`, `runbooks/` y `guides/` son **opcionales** — crearlas solo si hay contenido real para poner ahí o el usuario las pide explícitamente. No crear carpetas vacías de placeholder.

## Execution scope

- Pedido completo ("organizá los docs", "creá /docs") → todas las fases.
- Pedido parcial ("escribí un ADR", "documentá el setup") → siempre Fase 0 + la fase correspondiente.
- Fase 3 (migración) solo si hay docs existentes que mover.
- Nunca crear archivos de placeholder vacíos. Si no hay contenido, dejar la carpeta sin crear.

## Convenciones

- Markdown GitHub-flavored. Encabezados con `#`, listas con `-`.
- Los ADRs siguen el formato MADR-lite (ver abajo). Numeración correlativa con padding de 3 dígitos: `ADR-001`, `ADR-002`.
- No duplicar lo que ya está bien en el `README.md` raíz — referencias cruzadas con links relativos (`../README.md`).
- No eliminar el `README.md` raíz ni moverlo. Solo agregar un link a `docs/` si no existe.
- Si el proyecto tiene OpenAPI (`openapi.yaml`, `swagger.json`) no crear `docs/api/` — el spec ya es la doc de API.
- Registrar cada archivo creado o modificado. Si una decisión requiere input del usuario (¿este doc va en `guides/` o `runbooks/`?), pausar y preguntar.
- Nunca commitear. El usuario decide cuándo.

---

## Fase 0 — Discovery (siempre corre)

1. Listar archivos `.md` en el proyecto (excluyendo `node_modules`, `vendor`, `.git`):
   ```bash
   find . -name "*.md" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*"
   ```

2. Verificar si ya existe una carpeta `docs/` con estructura parcial. Si existe, mapear qué hay.

3. Leer el `README.md` raíz (si existe). Identificar secciones que podrían separarse a archivos propios (setup largo, arquitectura, decisiones, etc.).

4. Buscar comentarios de diseño en el código fuente:
   ```bash
   grep -r "TODO\|FIXME\|DECISION\|ARCHITECTURE\|RATIONALE\|NOTE:" --include="*.go" --include="*.py" --include="*.ts" --include="*.java" -l .
   ```

5. Detectar si el proyecto ya tiene ADRs en cualquier forma (`adr`, `decisions`, `decision-records`, archivos `ADR-*`, `decision-*.md`).

6. Identificar el tipo de proyecto: API service, CLI, librería, frontend, fullstack, monorepo. Esto determina qué carpetas de `/docs/` tienen sentido.

Salida: tabla de hallazgos mostrada al usuario antes de continuar:

| Hallazgo | Archivo / ubicación | Acción sugerida |
|----------|---------------------|----------------|
| README sección "Arquitectura" larga | `README.md` líneas X–Y | Extraer a `docs/architecture/overview.md` |
| Decisión enterrada en comentario | `src/db/pool.go:42` | Crear ADR sobre la decisión de pool |
| Archivos .md sueltos | `CONTRIBUTING.md`, `DEPLOY.md` | Mover a `docs/guides/` / `docs/runbooks/` |
| ... | | |

---

## Fase 1 — Estructura

Crear las carpetas que tengan contenido concreto (determinado en Fase 0):

```bash
mkdir -p docs/adr
mkdir -p docs/architecture
# solo si hay contenido:
# mkdir -p docs/setup
# mkdir -p docs/runbooks
# mkdir -p docs/guides
# mkdir -p docs/api
```

Si `docs/` ya existe parcialmente, respetar lo que hay — solo agregar lo que falta.

---

## Fase 2 — ADRs

### Cuándo crear un ADR

Crear un ADR cuando la Fase 0 detecta alguno de estos indicadores:
- Una decisión técnica no trivial sin registro escrito (elección de base de datos, patrón arquitectónico, framework, protocolo de comunicación, estrategia de autenticación, etc.).
- El usuario pide explícitamente documentar una decisión.
- Una sección del README describe el "por qué" de algo importante.

No crear ADRs para decisiones triviales o reversibles sin consecuencias amplias (ej. "usamos `fmt.Errorf` en lugar de `errors.New`").

### Plantilla MADR-lite

```markdown
# ADR-NNN: <Título conciso en forma de sustantivo — qué se decidió>

**Estado**: Aceptado | Propuesto | Obsoleto | Reemplazado por ADR-XXX  
**Fecha**: YYYY-MM-DD  
**Contexto**: <1–3 oraciones: el problema o situación que requirió una decisión>

## Decisión

<Lo que se decidió. Presente indicativo. "Usamos X", "Adoptamos Y", no "Se propone usar X".>

## Alternativas consideradas

| Opción | Por qué no |
|--------|-----------|
| Opción A | <razón concreta> |
| Opción B | <razón concreta> |

## Consecuencias

**Positivas**: <qué mejora o se habilita>  
**Negativas / trade-offs**: <qué se pierde, complica o restringe>  
**Neutral**: <efectos sin carga de valor>
```

### Numeración

- Leer los ADRs existentes para determinar el próximo número.
- Si no hay ADRs, empezar en `ADR-001`.
- Nunca reutilizar ni saltar números.

---

## Fase 3 — Migración de docs existentes

Para cada doc identificada en Fase 0 con acción "mover" o "extraer":

### 3a. Extraer secciones del README

Si el README tiene secciones que superan ~30 líneas y son autocontenidas (setup, arquitectura, contribución):

1. Crear el archivo destino con el contenido extraído.
2. En el README, reemplazar la sección por un link: `Para más detalles, ver [Arquitectura](docs/architecture/overview.md).`
3. No borrar toda la sección — dejar un párrafo introductorio + el link.

### 3b. Mover archivos .md sueltos

Archivos como `CONTRIBUTING.md`, `DEPLOY.md`, `RUNBOOK.md`, `ARCHITECTURE.md` que están en la raíz:

- Mover a la carpeta semántica correcta bajo `docs/`.
- Actualizar el link en el README raíz si existía.
- No romper links relativos internos del archivo — corregirlos al mover.

### 3c. Rescatar decisiones de comentarios inline

Si Fase 0 encontró decisiones en comentarios (`// DECISION: usamos pgvector porque...`):

- Crear el ADR correspondiente con la información del comentario.
- Reemplazar el comentario largo por una referencia: `// Ver docs/adr/ADR-003-vector-db.md`

---

## Fase 4 — Escritura de docs nuevas

Si el usuario pide crear documentación nueva (arquitectura, setup, guía):

### 4a. `docs/architecture/overview.md`

Estructura sugerida:
```markdown
# Arquitectura — <Nombre del proyecto>

## Visión general

<1 párrafo: qué hace el sistema, quiénes lo usan>

## Componentes principales

| Componente | Responsabilidad | Tecnología |
|-----------|----------------|-----------|
| ... | ... | ... |

## Flujo principal

<Descripción del happy path o diagrama Mermaid>

```mermaid
graph TD
    ...
```

## Decisiones de arquitectura relevantes

- [ADR-001: ...](../adr/ADR-001-...)
```

### 4b. `docs/setup/getting-started.md`

Estructura sugerida:
```markdown
# Getting Started

## Requisitos previos

- ...

## Variables de entorno

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| ... | ... | ... |

## Levantar en local

```bash
# pasos mínimos para correr el proyecto
```

## Verificar que funciona

<health check o smoke test>
```

### 4c. `docs/runbooks/<tarea>.md`

Estructura sugerida:
```markdown
# Runbook: <Tarea>

**Frecuencia**: <cuándo ejecutar>  
**Duración estimada**: <X minutos>

## Pasos

1. ...
2. ...

## Rollback

<cómo deshacer si algo falla>

## Indicadores de éxito

<cómo saber que funcionó>
```

---

## Fase 5 — Índice (`docs/README.md`)

Crear o actualizar `docs/README.md` como índice navegable:

```markdown
# Documentación — <Nombre del proyecto>

## Architecture Decision Records

| ADR | Título | Estado | Fecha |
|-----|--------|--------|-------|
| [ADR-001](adr/ADR-001-titulo.md) | Título | Aceptado | YYYY-MM-DD |

## Arquitectura

- [Visión general](architecture/overview.md)

## Setup

- [Getting started](setup/getting-started.md)

## Runbooks

- [<Tarea>](runbooks/<tarea>.md)

## Guías

- [<Guía>](guides/<guia>.md)
```

Solo listar secciones que tienen contenido real. No incluir secciones vacías.

Agregar al `README.md` raíz del proyecto (si no existe ya):
```markdown
## Documentación

Ver [`docs/`](docs/README.md) para arquitectura, ADRs, setup y guías operativas.
```

---

## Reporte final

Emitir al usuario:

1. **Archivos creados** — lista con ruta y descripción de cada uno
2. **Archivos modificados** — qué cambió y en qué archivo
3. **ADRs registrados** — tabla con número, título y decisión en una línea
4. **Pendiente** — docs que se identificaron pero no se escribieron (con la razón: "requiere input del equipo", "contenido no disponible", etc.)

Factual y sin relleno.

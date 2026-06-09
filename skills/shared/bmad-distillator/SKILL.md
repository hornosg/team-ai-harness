---
name: bmad-distillator
description: Compresión lossless de documentos optimizada para LLM. Preserva toda la información relevante eliminando overhead humano.
triggers:
  - "distilá documentos"
  - "crear distillate"
  - "comprimir documentos para LLM"
---

# BMAD Distillator

Compresión lossless de documentos fuente. **No es un resumen** — es compresión: preserva cada hecho, decisión, constraint y relación, eliminando solo el overhead que humanos necesitan y los LLMs no.

## Activación

El usuario provee:
- **source_documents** (requerido) — Paths, carpetas o globs a destilar
- **downstream_consumer** (opcional) — Qué workflow/agente consume el distillate (ej: "PRD creation"). Cuando se provee, se usa para discriminar señal vs ruido
- **output_path** (opcional) — Dónde guardar. Default: mismo directorio que la fuente con sufijo `-distillate.md`

## Principios de compresión

### Qué eliminar
- Frases de introducción y cierre ("En este documento veremos...", "Para concluir...")
- Redundancias: información idéntica repetida sin propósito
- Ejemplos obvios que no agregan información nueva
- Prose explicativa cuando un bullet alcanza
- Contenido que pertenece a otro documento

### Qué preservar
- Cada decisión y su razón
- Cada constraint o restriction
- Cada relación entre conceptos
- Números, nombres, y detalles específicos
- Referencias cruzadas entre secciones

### Formato de salida
- Solo bullets — sin párrafos de prose
- Sin formatting decorativo
- Sin información repetida
- Cada bullet self-contained
- Temas delimitados con `##`

## Proceso

### 1. Analizar fuentes
Leer todos los documentos fuente. Identificar:
- Temas principales y sub-temas
- Relaciones entre documentos
- Tamaño estimado del distillate

### 2. Comprimir
Para cada sección:
- Extraer hechos, decisiones, constraints en formato bullet
- Eliminar prose overhead
- Deduplicar información repetida entre secciones
- Preservar relaciones con referencias cruzadas (`→ ver [sección]`)

### 3. Verificar
- ¿Cada heading del original está representado?
- ¿Cada entidad nombrada (persona, sistema, decisión) aparece?
- ¿Hay bullets de prose que deberían ser sub-bullets?

### 4. Guardar

**Distillate único** (documentos cortos):
```yaml
---
type: bmad-distillate
sources:
  - "ruta/relativa/al/fuente.md"
downstream_consumer: "general"
created: "YYYY-MM-DD"
---
```

**Split distillate** (documentos largos — >5000 tokens estimados):
```
{base-name}-distillate/
├── _index.md           # Orientación + manifesto de secciones
├── 01-{topic}.md       # Sección self-contained
└── 02-{topic}.md
```

## Ejemplo de compresión

**Original:**
> "En nuestra plataforma, hemos tomado la decisión de utilizar JWT tokens para la autenticación de usuarios. Esta decisión fue tomada en reunión del equipo el 15 de marzo. Los JWT expiran a las 24 horas..."

**Distillate:**
> - Auth: JWT tokens, expiración 24h. Decisión: 2024-03-15

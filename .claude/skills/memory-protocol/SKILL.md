---
name: memory-protocol
description: Protocolo Engram — cuándo y cómo guardar/recuperar memoria persistente. Complementa el MCP de Engram definiendo triggers y estructura.
triggers:
  - "guardar memoria"
  - "memoria persistente"
  - "engram protocol"
---

# Memory Protocol (Engram)

Define cuándo y cómo usar las herramientas MCP de Engram. No reemplaza Engram — le dice al agente *cuándo* llamarlo.

## Herramientas disponibles

- `mem_save` — guardar memoria con topic_key
- `mem_search` — buscar por keywords
- `mem_context` — cargar contexto por topic
- `mem_session_summary` — cerrar sesión con resumen

## Cuándo guardar (mem_save)

Llamar inmediatamente después de:
- Decisión arquitectural o técnica
- Bug resuelto con causa raíz no obvia
- Patrón o gotcha descubierto
- Cambio de configuración o preferencia de usuario
- Feature completada

### Estructura del contenido

```
What: [qué se decidió/descubrió]
Why: [por qué — la razón, no la descripción]
Where: [archivos, módulos, o contexto relevante]
Learned: [qué se aprendió o qué hay que recordar]
```

### topic_key

Usar topic_key estable para temas que evolucionan (ej: `auth-decisions`, `db-config`, `frontend-patterns`). No usar timestamps como key.

## Cuándo buscar (mem_search / mem_context)

- Primer mensaje que referencia proyecto, feature, o problema → `mem_search` con keywords antes de responder
- Antes de trabajo similar a algo ya hecho → `mem_search` proactivo
- En recall explícito → `mem_context` primero, luego `mem_search`

## Cierre de sesión (mem_session_summary)

Antes de decir "listo" o cerrar trabajo:

1. Llamar `mem_session_summary` con:
   - **goal**: qué se intentaba lograr
   - **discoveries**: hallazgos no obvios
   - **accomplished**: qué quedó hecho
   - **next_steps**: qué queda pendiente
   - **relevant_files**: paths clave

## Post-compactación

Si el contexto fue compactado:
1. Guardar resumen primero con `mem_save`
2. Recuperar contexto con `mem_context` + `mem_search`
3. Continuar trabajo

## Memoria episódica local (por proyecto)

Complementa Engram con dos archivos JSONL dentro del proyecto. Útil para registrar el *rastro* de decisiones y fallos sin depender del MCP.

### Archivos

```
memory/
  decisions.jsonl   ← decisiones de arquitectura y diseño
  failures.jsonl    ← bugs e incidentes con raíz causa y fix
```

Agregar `memory/` al `.gitignore` si el contenido es sensible, o incluirlo si quiere versionarse junto al proyecto.

### Estructura de entrada en decisions.jsonl

```json
{"date": "YYYY-MM-DD", "context": "qué estaba haciendo", "decision": "qué se decidió", "alternatives": ["opción A", "opción B"], "rationale": "por qué esta sobre las otras"}
```

### Estructura de entrada en failures.jsonl

```json
{"date": "YYYY-MM-DD", "symptom": "qué se observó", "root_cause": "por qué pasó", "fix": "cómo se resolvió", "prevent": "qué evita que vuelva a pasar"}
```

### Cuándo escribir

- Al cerrar una decisión de diseño que no sea obvia → `decisions.jsonl`
- Al resolver un bug que tomó más de 30 minutos → `failures.jsonl`

### Cuándo leer

- Al iniciar trabajo en un área → `grep <keyword> memory/decisions.jsonl`
- Al enfrentar un error similar a uno anterior → `grep <symptom> memory/failures.jsonl`

---

## Guardrails

- NUNCA guardar PII (emails, tokens, passwords) en memoria
- topic_key debe ser reutilizable entre sesiones — evitar genérico como "session-1"
- Si no hay Engram MCP activo, documentar la decisión como comentario en el código o ADR
- Los archivos JSONL de memoria episódica no reemplazan a Engram — son el registro local; Engram es la capa cross-proyecto

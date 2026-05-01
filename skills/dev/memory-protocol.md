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

## Guardrails

- NUNCA guardar PII (emails, tokens, passwords) en memoria
- topic_key debe ser reutilizable entre sesiones — evitar genérico como "session-1"
- Si no hay Engram MCP activo, documentar la decisión como comentario en el código o ADR

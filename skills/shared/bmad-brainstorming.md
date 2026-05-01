---
name: bmad-brainstorming
description: Facilita sesiones de brainstorming usando técnicas creativas diversas. Objetivo 100+ ideas antes de organizar.
triggers:
  - "help me brainstorm"
  - "ayudame a brainstormear"
  - "sesión de brainstorming"
  - "ideación"
---

# BMAD Brainstorming

Facilitador de sesiones de brainstorming creativo. Meta: mantener al usuario en modo generativo el mayor tiempo posible.

## Mindset crítico

- **Anti-sesgo**: los LLMs derivan hacia clustering semántico. Cada 10 ideas, cambiar dominio: técnico → UX → negocio → edge cases → "black swans"
- **Cantidad antes que calidad**: las primeras 20 ideas son obvias. La magia está en las ideas 50-100
- **No organizar prematuramente**: resistir el impulso de concluir. Cuando dudes, haz otra pregunta
- **Objetivo**: 100+ ideas antes de cualquier organización

## Técnicas disponibles

### Selección por el usuario
Preguntar qué técnica prefiere o recomendar según el tema.

### AI-Recommended (default)
Seleccionar la técnica más adecuada según el problema:
- **SCAMPER**: Sustituir, Combinar, Adaptar, Modificar, Poner en otros usos, Eliminar, Reordenar
- **What If...**: Cuestionar suposiciones clave ("¿Y si no hubiera precio?", "¿Y si fuera para niños?")
- **6 Sombreros**: Perspectivas paralelas (datos, emociones, crítico, optimista, creativo, proceso)
- **Analogías**: Resolver el problema como si fuera otro dominio completamente distinto
- **Inversión**: ¿Cómo empeoraría el problema? Invertir las respuestas
- **Random Input**: Palabra aleatoria como disparador creativo

### Progressive Flow
Encadenar técnicas: empezar amplio → ir a específico → explorar edge cases.

## Proceso de sesión

### Inicio
1. Confirmar el tema/problema con el usuario
2. Preguntar o recomendar técnica
3. Si el proyecto tiene `PROJECT.md`, leerlo para contexto de negocio

### Durante
- Generar ideas en bloques de 10-20
- Hacer preguntas para profundizar en threads prometedores
- Rotar dominio cada 10 ideas (técnico → usuario → negocio → extremo)
- Nunca juzgar ideas — todo va al pool

### Cierre
Cuando el usuario quiera organizar:
1. Agrupar por tema/categoría
2. Marcar las 5-10 más prometedoras con criterio acordado (impacto, factibilidad, novedad)
3. Documentar en `BRAINSTORMING-[fecha].md`

## Output del documento

```markdown
# Brainstorming: [Tema] — [Fecha]

## Ideas generadas

### [Categoría A]
- [idea 1]
- [idea 2]

### [Categoría B]
- ...

## Top candidatas
1. [idea] — [por qué es prometedora]
2. ...

## Próximos pasos
- [qué explorar primero]
```

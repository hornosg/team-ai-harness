---
name: market-copy
description: Análisis y mejora de copy con alineación a brand voice. Genera pares antes/después con justificación.
triggers:
  - "mejorá el copy"
  - "optimizá los headlines"
  - "mejorá los CTAs"
---

# Skill: Mejora de Copy

Analiza copy existente y genera sugerencias antes/después alineadas con la voz de marca del proyecto.

## Cuándo activar

- Usuario pide "mejorá el copy", "optimizá los headlines", "mejorá los CTAs"
- Usuario menciona copy, landing, headlines, CTAs, textos de conversión

## Contexto obligatorio

Antes de analizar, buscar en el proyecto:
- `PROJECT.md` — buscar sección de tono y voz, principios de comunicación
- `marketing/TONO_Y_VOZ.md` — si existe, es la referencia de brand voice
- `marketing/COPYWRITING_BANCO.md` — si existe, usar como inspiración y verificar consistencia

Si no existen documentos de brand voice, preguntar al usuario: "¿Hay algún documento de tono y voz o principios de comunicación que debería respetar?"

## Criterios de evaluación

- **Claridad**: ¿Se entiende en 5 segundos qué ofrece y para quién?
- **Persuasión**: ¿Habla del beneficio, no de la feature?
- **Especificidad**: ¿Tiene números o detalles concretos?
- **Alineación**: ¿Respeta el tono definido en el proyecto?

## CTAs

Evitar genéricos: "Enviar", "Click aquí", "Más información", "Submit"

Preferir value-driven: "Empezá a vender en 10 minutos", "Probalo gratis — sin tarjeta"

## Proceso

1. **Obtener copy** — Si el usuario da URL, usar WebFetch para extraer headlines, copy, CTAs. Si da texto, usarlo directamente
2. **Evaluar** — Aplicar criterios de la sección anterior
3. **Generar sugerencias** — Mínimo 3 pares antes/después

## Output

Mínimo **3 pares antes/después**:

```
**Antes:** [copy actual — citar exactamente]
**Después:** [versión mejorada]
**Por qué:** [explicación breve del cambio]
```

Guardar en `COPY-SUGGESTIONS.md` si hay más de 5 sugerencias. Si es breve, responder en el chat.

## Guardrails

- NUNCA cambiar el significado — solo la expresión
- Si el tono del proyecto no está documentado, preguntar antes de asumir
- Los pares antes/después deben citar el original exactamente

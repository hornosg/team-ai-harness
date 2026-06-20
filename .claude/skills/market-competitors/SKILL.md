---
name: market-competitors
description: Análisis competitivo con matriz comparativa. Escanea competidores y genera recomendaciones de diferenciación.
triggers:
  - "análisis competitivo"
  - "matriz competitiva"
  - "compará con competidores"
---

# Skill: Inteligencia Competitiva

Análisis comparativo de competidores con matriz multi-dimensional y recomendaciones de diferenciación.

## Cuándo activar

- Usuario pide "compará con [competidor]", "análisis competitivo", "qué hace la competencia"
- Usuario pide "matriz competitiva" o "inteligencia competitiva"

## Contexto

Buscar en el proyecto documentos de posicionamiento, propuesta de valor, o pricing del producto propio (ej: `PROJECT.md`, `marketing/FICHAS_PRODUCTO.md`). Usar como referencia para comparar contra competidores.

## Proceso

1. **Identificar URLs** — Extraer URLs de competidores del mensaje del usuario
2. **Obtener datos** — Para cada competidor, usar WebFetch para analizar:
   - Headline principal y tagline
   - Propuesta de valor
   - Pricing (si visible)
   - CTAs principales
   - Social proof (testimonios, logos, números)
   - Plataforma técnica (si detectable)
3. **Comparar con el producto propio** — Si el usuario quiere "nosotros vs ellos", incluir columna propia
4. **Identificar gaps** — Dónde el producto propio puede destacar

## Output

Generar `COMPETITOR-MATRIX.md` con:

### Tabla comparativa
| Dimensión | Producto propio | Competidor A | Competidor B |
|-----------|----------------|--------------|--------------|
| Headline | ... | ... | ... |
| Pricing | ... | ... | ... |
| CTAs | ... | ... | ... |
| Trust signals | ... | ... | ... |

### Por competidor
- URL, headline, propuesta de valor, fortalezas, debilidades

### Recomendaciones de diferenciación
- Gaps donde el producto puede destacar vs competidores
- Oportunidades no explotadas en el mercado

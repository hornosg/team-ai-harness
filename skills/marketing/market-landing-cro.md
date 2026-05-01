---
name: market-landing-cro
description: Optimización de conversión de landing pages. Evalúa CTAs, formularios, social proof y above-the-fold.
triggers:
  - "optimizá la conversión"
  - "mejorá la landing"
  - "CRO"
---

# Skill: Optimización de Conversión (CRO)

Evaluación de elementos de conversión en landing pages. Genera recomendaciones priorizadas por impacto y esfuerzo.

## Cuándo activar

- Usuario pide "optimizá la conversión", "mejorá la landing", "CRO de la landing"
- Usuario menciona conversión, tasa de conversión, CTAs, formularios, above-the-fold

## Proceso

1. **Obtener URL** — Si no se especifica, pedir al usuario
2. **Analizar página** — Usar WebFetch para ver el contenido. Si el proyecto tiene un script de análisis, usarlo como complemento
3. **Evaluar elementos** — Ver secciones abajo
4. **Clasificar y priorizar** — Quick wins vs estratégicos

## Elementos a evaluar

### CTAs
- Claridad y especificidad del texto
- Ubicación: ¿visible above-the-fold? ¿múltiples puntos?
- Texto value-driven vs genérico
- Contraste visual (evaluable solo si hay info visual)

### Formularios
- Cantidad de campos (menos = mejor, >7 es alto friction)
- Labels claros, placeholders útiles
- Botón de submit con copy persuasivo
- Indicadores de campos requeridos

### Social proof
- Testimonios con nombre, foto, empresa
- Logos de clientes o medios
- Números concretos ("500+ comercios")
- Reviews de terceros o certificaciones

### Above-the-fold
- Headline clara: ¿se entiende la propuesta en <5 segundos?
- CTA visible sin scroll
- Propuesta de valor evidente
- Visual relevante (foto de producto, persona, resultado)

## Clasificación de recomendaciones

- **Quick win**: bajo esfuerzo, alto impacto — implementar esta semana
- **Estratégico**: alto esfuerzo, alto impacto — planificar 1-3 meses

## Output

Generar `LANDING-CRO.md` con:
- Resumen de hallazgos principales
- Quick wins (con copy específico sugerido cuando aplica)
- Mejoras estratégicas (con descripción detallada)
- Estimación de impacto por recomendación (Alto / Medio / Bajo)

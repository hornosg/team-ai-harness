---
name: market-audit
description: Auditoría completa de marketing de una URL con scoring multi-dimensional y recomendaciones priorizadas.
triggers:
  - "auditame la landing"
  - "auditoría de marketing"
  - "auditá la web"
---

# Skill: Auditoría de Marketing

Auditoría completa de marketing para cualquier URL. Genera reporte accionable con scoring y recomendaciones priorizadas.

## Cuándo activar

- Usuario pide "auditame la landing", "auditá la web", "hacé una auditoría de marketing de [URL]"
- Usuario menciona una URL o dominio específico

## Contexto (leer si existen)

Antes de analizar, buscar en el proyecto:
- `marketing/BUYER_PERSONAS.md` o sección equivalente en `PROJECT.md` — para evaluar alineación con audiencia
- `marketing/TONO_Y_VOZ.md` o `PROJECT.md` — para evaluar brand voice
- Cualquier documento de propuesta de valor o fichas de producto

Si no existen, aplicar mejores prácticas generales.

## Proceso

1. **Obtener URL** — Si no se especifica, pedir al usuario
2. **Obtener contenido** — Usar WebFetch para analizar la página. Si el proyecto tiene un script de análisis (`marketing/scripts/analyze_page.py`), usarlo en lugar de WebFetch
3. **Evaluar dimensiones** — Ver sección Scoring
4. **Generar reporte** — Ver Output

## Scoring

| Dimensión | Peso | Qué evaluar |
|-----------|------|-------------|
| SEO & Discoverabilidad | 30% | title (30-60 chars), meta desc (120-160 chars), H1 único, jerarquía headings, alt texts, robots, sitemap |
| Contenido & Messaging | 25% | headlines, propuesta de valor, copy, CTAs, claridad en <5 segundos |
| Optimización de conversión | 25% | CTAs value-driven, formularios (menos campos), social proof, above-the-fold |
| Señales de confianza | 20% | testimonios con nombre/foto, logos, números concretos, schema markup |

Score compuesto = promedio ponderado (0-100).

## Output

Generar `MARKETING-AUDIT.md` con:
- Resumen ejecutivo (3-5 párrafos)
- Tabla de scores por categoría
- Top 5 quick wins (implementar esta semana — bajo esfuerzo, alto impacto)
- Recomendaciones estratégicas (este mes)
- Análisis detallado por categoría
- Próximos pasos priorizados

## Error handling

- Si la URL no responde: reportar error, sugerir verificar URL
- Si WebFetch falla: intentar con distintos endpoints o pedir al usuario el contenido manualmente

---
name: market-seo
description: Auditoría SEO técnica y de contenido con checklist priorizado por severidad.
triggers:
  - "auditoría SEO"
  - "auditá el SEO"
  - "revisá el SEO"
---

# Skill: Auditoría SEO

Análisis SEO técnico y de contenido. Genera checklist priorizado de mejoras.

## Cuándo activar

- Usuario pide "auditoría SEO", "auditá el SEO", "revisá el SEO de [URL]"
- Usuario menciona SEO, meta tags, headings, sitemap, posicionamiento orgánico

## Proceso

1. **Obtener URL** — Si no se especifica, pedir al usuario
2. **Analizar página** — Usar WebFetch para extraer:
   - `<title>` y `<meta description>`
   - Headings (H1, H2, H3...)
   - Imágenes y atributos alt
   - Canonical, robots meta
   - Sitemap y robots.txt
   - Schema/JSON-LD
   - Internal/external links
3. **Evaluar on-page** — title (30-60 chars), meta (120-160 chars), H1 único, jerarquía correcta
4. **Evaluar técnico** — robots.txt, sitemap.xml, schema markup, canonicales

## Checklist por severidad

| Severidad | Hallazgo |
|-----------|---------|
| **Crítico** | Falta title, falta H1, meta vacía, robots bloqueando indexación |
| **Alto** | Title/meta fuera de rango óptimo, múltiples H1, imágenes sin alt |
| **Medio** | Headings mal jerarquizados, canonical faltante, sitemap ausente |
| **Bajo** | Schema incompleto, optimizaciones menores |

## SEO local

Si la URL es de Argentina (.com.ar) o el sitio es local, agregar evaluación de:
- Google Business Profile (mencionado o vinculado)
- Schema LocalBusiness
- Keywords locales (ciudad, barrio, "cerca de")
- NAP consistency (Nombre, Dirección, Teléfono consistentes en el sitio)

## Output

Generar `SEO-AUDIT.md` con:
- Resumen ejecutivo
- Checklist priorizado (tabla: Severidad | Hallazgo | Acción recomendada)
- Recomendaciones de SEO local (si aplica)
- Próximos pasos ordenados por impacto

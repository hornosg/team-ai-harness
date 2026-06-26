# PROP-NNN: [Título descriptivo corto]

**Estado:** borrador
**Autor:** [nombre o @agente]
**Fecha:** [YYYY-MM-DD]
**Hito propuesto:** H[N]
**Épica:** E[NN] (o "nueva" si propone crear una)
**Prioridad:** critica | alta | media | baja
**Ceremony level:** L[1-4]
**Detalle de ejecución:** estándar | reforzado  ← reforzado si se ejecutará con backing model abierto (Hermes/Kimi/Ollama)
**Spec:** — (se completa al aprobar → `openspec/changes/[nombre-kebab]`)

## Qué

Descripción concisa de lo que se propone hacer. 2-3 oraciones máximo.

## Por qué

Motivación y contexto. ¿Qué problema resuelve? ¿Qué pasa si no se hace?
¿Se alinea con el hito actual (`fase_actual` en roadmap.yaml)?

## Servicios / repos afectados

- [servicio-a]
- [servicio-b]

## Tareas estimadas

> Nivel propuesta: una línea por tarea, **acción + resultado observable** (no hace falta path/firma todavía).
> Al aprobar, la épica las expande a tareas atómicas verificables (ver `epicas/_TEMPLATE.md → Tareas`).

- [ ] [Verbo + objeto → resultado observable] (ej: "Agregar endpoint POST /x → devuelve 201 con la entidad")
- [ ] [Tarea]
- [ ] [Tarea]

## Criterios de validación

### Automáticos
- [ ] [Tests pasan / endpoint responde / build OK]

### Manuales
- [ ] [Validación del owner o usuario]

## Riesgos

- [Riesgo] → [Mitigación]

## Decisiones de diseño requeridas

> Completar si la propuesta requiere decisiones antes de ejecutar (L3+).

- [ ] [Decisión arquitectural — @architect]
- [ ] [Decisión de seguridad — @security]

## Notas

(Links, contexto, alternativas descartadas)

---

<!-- LIFECYCLE:
  borrador      → Idea inicial, puede estar incompleta
  en-revisión   → Lista para que el owner la revise y apruebe/rechace
  aprobada      → Validada, lista para ejecutar
  en-ejecución  → Trabajo en curso (spec creada o implementando)
  completada    → Todas las tareas listas y criterios validados
  descartada    → No se implementará (documentar por qué en Notas)
-->

<!-- NAMING:
  Archivo: PROP-NNN-descripcion-corta.md
  NNN = secuencial desde 001
-->

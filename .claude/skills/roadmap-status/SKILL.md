---
name: roadmap-status
description: Reporte de estado del roadmap cruzando épicas, propuestas y specs. Muestra qué está en ejecución, qué está para tomar, qué está bloqueado.
triggers:
  - "status"
  - "dame un status"
  - "qué tenemos en ejecución"
  - "roadmap status"
  - "qué hay para tomar"
---

# Roadmap Status

Reporte unificado del estado del proyecto. Cruza `roadmap.yaml`, `propuestas/`, y `workspace/` (specs activas).

## Proceso

### 1. Leer fuentes (OBLIGATORIO — no asumir, leer)

**Leer primero:**
```
management/roadmap/roadmap.yaml          ← hitos + épicas + estados
management/roadmap/propuestas/           ← escanear todos los *.md (no _TEMPLATE)
```

**Specs activas:**
```
management/workspace/                    ← specs activas (formato SNNN-slug/ o nombre-feature/)
```

Reportar solo lo que existe en disco. Si `workspace/` no existe o está vacío → reportar "Sin specs activas".

**NUNCA usar memoria (Engram, contexto de sesión anterior) como fuente de estado del roadmap.** Los archivos son la única fuente de verdad.

### 2. Clasificar épicas por estado

- **EN PROGRESO** → `estado: en-progreso`
- **PARA TOMAR** → `estado: pendiente` + prioridad `critica` o `alta` del hito activo
- **BLOQUEADAS** → `estado: bloqueado`
- **COMPLETAS** → `estado: completo`

### 3. Clasificar propuestas

- `en-revisión` → necesita decisión del owner
- `aprobada` → lista para ejecutar (¿tiene spec ya?)
- `borrador` → ideas sin madurar
- `en-ejecución` → ya tiene epic o spec activa

### 4. Cruzar con specs

Detectar specs activas:
- Si existe `management/workspace/` → listar subdirectorios con `tasks.md` (ignorar `_template`, `_archive`)
- Si no existe o vacío → omitir sección, no inventar

Linkear spec ↔ épica ↔ propuesta solo si el vínculo está explícito en los archivos.

### 5. Generar reporte

```
═══════════════════════════════════════════
  ROADMAP STATUS — [NOMBRE PROYECTO]
═══════════════════════════════════════════
  Fase actual : H[N] — [nombre hito]
  Norte       : [objetivo medible]
  Actualizado : [fecha de roadmap.yaml]

🔄 EN PROGRESO ([N])
  E03 — [nombre] · H1 · Crítica
       Spec: workspace/[nombre] ← si existe
  E07 — [nombre] · H2 · Alta

📋 PARA TOMAR ([N]) — Hito actual: H[N]
  E04 — [nombre] · H1 · Crítica · [servicios]
  E05 — [nombre] · H1 · Alta

🚫 BLOQUEADAS ([N])
  E06 — [nombre] · bloqueado
        → Ver epicas/E06-[nombre].md para detalle

✅ COMPLETAS ([N])
  E01 — [nombre]
  E02 — [nombre]

──────────────────────────────────────────
📝 PROPUESTAS

  ⚠️  Para aprobar ([N])
    PROP-002 — [nombre] · en-revisión
    PROP-003 — [nombre] · en-revisión

  ✔  Aprobadas sin spec ([N])
    PROP-004 — [nombre] · aprobada → pendiente convertir a spec/épica

  📐 En ejecución ([N])
    PROP-001 — [nombre] · en-ejecución → E03 · workspace/[nombre]

──────────────────────────────────────────
📐 SPECS ACTIVAS
  [nombre-cambio] → E03 · PROP-001

──────────────────────────────────────────
🎯 HITO ACTUAL: H[N] — [nombre]
  Progreso: [N completas] / [N total épicas del hito]
  Gate: "[criterio de finalización]"
  [██████████░░░░░] 60%

  Siguiente hito: H[N+1] — [nombre] ([fecha objetivo])
═══════════════════════════════════════════
```

## Acciones sugeridas al final del reporte

Si hay propuestas `aprobada` sin spec → sugerir: "PROP-00N está aprobada. ¿Creo la épica y spec?"

Si hay épicas `en-progreso` sin spec → sugerir: "E0N no tiene spec en workspace/. ¿Creo una?"

Si el hito actual está > 80% completo → sugerir: "H[N] casi listo. ¿Revisamos gate y planificamos H[N+1]?"

## Guardrails

- **Solo leer** — este skill no modifica nada
- **Si `roadmap.yaml` no existe**: reportar "Roadmap no inicializado. Completar management/roadmap/roadmap.yaml"
- **Si no hay specs en ninguna ruta**: omitir sección specs — no inventar ciclos ni cambios
- **NUNCA completar datos desde memoria o inferencia** — si el campo está vacío en el YAML, mostrar "[sin datos]"
- Mostrar siempre primero lo que requiere acción del owner
- Si el agente detecta que usó memoria en vez de archivos: parar, releer archivos, regenerar reporte

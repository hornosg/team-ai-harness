---
name: roadmap-management
description: Crear y actualizar épicas, propuestas y roadmap.yaml. Agentes leen el roadmap para contexto y escriben para mantenerlo actualizado.
triggers:
  - "crear epica"
  - "nueva propuesta"
  - "agregar al roadmap"
  - "actualizar estado"
  - "crear propuesta"
---

# Roadmap Management

Skill para que los agentes lean, creen y actualicen el roadmap del proyecto.

## Estructura del roadmap

```
management/roadmap/
  roadmap.yaml          ← índice maestro (hitos + épicas + estado)
  epicas/               ← una por épica con tareas y criterios
  propuestas/           ← pendientes de aprobación del owner
```

## Cuándo leer el roadmap (siempre antes de proponer)

Antes de sugerir cualquier trabajo nuevo:
1. Leer `management/roadmap/roadmap.yaml` — ¿ya existe una épica para esto? ¿Qué hito está activo (`fase_actual`)?
2. Si existe épica → referenciar su ID en la respuesta
3. Si no existe → crear propuesta en lugar de ejecutar directamente

## Cómo crear una propuesta

Trigger: pedido de trabajo nuevo no reflejado en el roadmap.

```
@meta-router crear epica [descripción]
@product-orchestrator nueva propuesta [descripción]
```

### Proceso

1. Leer `roadmap.yaml` → determinar hito activo y próximo ID de propuesta (PROP-NNN)
2. Copiar `management/roadmap/propuestas/_TEMPLATE.md`
3. Completar todos los campos del template:
   - `Estado: borrador`
   - Hito propuesto (alineado con `fase_actual`)
   - Tareas concretas (verbos en infinitivo, resultados observables)
   - Criterios de validación auto + manual
   - Ceremony level estimado (L1-L4)
4. Guardar como `management/roadmap/propuestas/PROP-NNN-descripcion-corta.md`
5. Presentar al owner para aprobación — NO ejecutar sin aprobación explícita para L2+

## Cómo crear una épica (propuesta aprobada)

Trigger: propuesta aprobada por el owner.

1. Determinar próximo ID de épica (E01, E02... secuencial)
2. Copiar `management/roadmap/epicas/_TEMPLATE.md`
3. Completar template con las tareas y criterios de la propuesta aprobada
4. Guardar como `management/roadmap/epicas/ENN-descripcion-corta.md`
5. Agregar entrada en `roadmap.yaml`:
   ```yaml
   - id: ENN
     nombre: "[nombre]"
     hito: H[N]
     estado: pendiente
     prioridad: [nivel]
     archivo: epicas/ENN-[nombre].md
     servicios: [lista]
     descripcion: "[una oración]"
   ```

## Cómo actualizar estado

Al completar tareas o épicas:

```yaml
# En roadmap.yaml — cambiar estado de la épica
- id: E03
  estado: completo   # pendiente | en-progreso | bloqueado | completo | deprecado

# En el archivo de la épica — marcar tareas
- [x] Tarea completada
```

Si se completa una épica → verificar si el hito completo cumple su `gate`. Si sí → marcar hito como `completo`.

## Cómo deprecar

```yaml
estado: deprecado
# Agregar en el archivo de la épica:
## Motivo de deprecación
[explicación — qué cambió, qué la reemplaza]
```

## Guardrails

- NUNCA ejecutar trabajo L2+ sin propuesta aprobada por el owner
- NUNCA crear épica sin ID secuencial único
- Roadmap.yaml es single source of truth — toda épica tiene entrada ahí
- Al mover una épica entre hitos, actualizar AMBOS lugares (yaml + archivo)
- Propuestas en `borrador` son solo ideas — el owner decide si avanzan

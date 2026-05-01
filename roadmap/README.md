# Roadmap

Fuente de verdad del roadmap del proyecto. Los agentes leen este directorio para contextualizar su trabajo antes de proponer o ejecutar.

## Estructura

```
roadmap/
  roadmap.yaml          ← Índice: hitos, épicas, estado (lo que leen los agentes)
  epicas/               ← Detalle de cada épica con tareas y criterios
    _TEMPLATE.md        ← Template para nuevas épicas
    E01-nombre.md
    E02-nombre.md
    ...
  propuestas/           ← Propuestas pendientes de aprobación del owner
    _TEMPLATE.md        ← Template para nuevas propuestas
    README.md
    PROP-001-nombre.md
    ...
```

## Flujo de trabajo

```
1. Owner o agente identifica necesidad
2. Se genera una propuesta en propuestas/PROP-NNN-nombre.md
3. Owner revisa, aprueba o ajusta
4. Propuesta aprobada → épica creada en epicas/ + entrada en roadmap.yaml
5. Agente ejecuta tareas de la épica
6. Al completar, agente actualiza estado en roadmap.yaml
```

## Convenciones

| Campo | Valores válidos |
|-------|----------------|
| estado | `pendiente` \| `en-progreso` \| `bloqueado` \| `completo` \| `deprecado` |
| prioridad | `critica` \| `alta` \| `media` \| `baja` |
| IDs | Hitos: `H0`, `H1`... · Épicas: `E01`, `E02`... · Propuestas: `PROP-001`... |

**Naming de archivos:**
- Épicas: `E01-descripcion-corta.md` (kebab-case)
- Propuestas: `PROP-001-descripcion-corta.md` (kebab-case)

## Cómo usan este directorio los agentes

- **@dev-orchestrator** / **@product-orchestrator**: leen `roadmap.yaml` para clasificar el trabajo en el hito correcto y detectar conflictos con épicas en curso
- **@project-leader** / **@product-leader**: proponen nuevas épicas y actualizan estados
- **@meta-router**: lee `fase_actual` para priorizar ruteo cross-domain

Ante cualquier pedido que no esté reflejado en el roadmap, los agentes generan una propuesta en lugar de ejecutar directamente.

# Propuestas

Propuestas de trabajo pendientes de revisión y aprobación del owner.

## Flujo

```
borrador → en-revisión → aprobada → en-ejecución → completada
                      ↘ descartada
```

| Estado | Significado |
|--------|-------------|
| `borrador` | Idea inicial, puede estar incompleta |
| `en-revisión` | Lista para que el owner la revise |
| `aprobada` | Validada por el owner, lista para ejecutar |
| `en-ejecución` | Trabajo activo (spec creada o implementando) |
| `completada` | Todas las tareas listas y criterios validados |
| `descartada` | No se implementará — documentar por qué |

## Convención de nombres

```
PROP-NNN-descripcion-corta.md
```

NNN es secuencial desde 001. Ejemplo: `PROP-001-setup-autenticacion.md`

## Quién crea propuestas

- **Owner**: pedidos de negocio o features nuevas
- **@product-orchestrator** / **@dev-orchestrator**: cuando detectan trabajo no planificado que impacta el roadmap
- **@architect**: cambios arquitecturales que requieren aprobación antes de ejecutar

Los agentes NO ejecutan trabajo no reflejado en el roadmap sin una propuesta aprobada.

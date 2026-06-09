---
name: bmad-party-mode
description: Orquesta discusiones grupales entre agentes del equipo, habilitando conversaciones multi-agente naturales.
triggers:
  - "party mode"
  - "discusión de equipo"
  - "que opinen todos"
---

# BMAD Party Mode

Modo de discusión multi-agente. Orquesta conversaciones naturales entre agentes del equipo con perspectivas distintas.

## Activación

Cuando el usuario activa party mode o pide que varios agentes opinen sobre un tema.

## Setup

Al activar:
1. Identificar qué agentes del equipo son relevantes para el tema
2. Cargar sus perfiles de `agents/` (nombre, rol, estilo de comunicación)
3. Presentar los agentes que participarán

**Ejemplo de bienvenida:**
```
PARTY MODE ACTIVADO

Los siguientes agentes están en la sala para discutir [tema]:
- @technical-leader — foco en viabilidad técnica y tradeoffs
- @architect — foco en diseño y constraints arquitecturales
- @qa — foco en riesgos y casos borde

¿Qué querés discutir?
```

## Selección de agentes por mensaje

Para cada mensaje del usuario:
1. Analizar dominio y expertise requerido
2. Seleccionar 2-3 agentes más relevantes
3. Considerar participación anterior (rotar para diversidad)
4. Si el usuario nombra un agente específico, priorizarlo + 1-2 complementarios

## Orquestación de conversación

### Formato de respuesta
Cada agente habla desde su perspectiva:
```
**@technical-leader:** [respuesta desde perspectiva técnica]

**@architect:** [respuesta desde perspectiva arquitectural, puede concordar o disentir]

**@qa:** [respuesta desde perspectiva de calidad y riesgos]
```

### Interacción entre agentes
- Agentes pueden referenciar a otros: "@architect tiene razón en que..."
- Desacuerdos son bienvenidos — representan perspectivas reales del equipo
- Mantener personalidad consistente de cada agente (ver su perfil en `agents/`)

### Preguntas directas al usuario
Si un agente necesita información del usuario:
- Terminar esa ronda inmediatamente después de la pregunta
- Esperar respuesta antes de continuar

## Salida del modo

Triggers de salida: `*exit`, `goodbye`, `end party`, `quit`, `salir`

Al salir:
- Resumir puntos de consenso alcanzados
- Listar decisiones pendientes o puntos sin resolver
- Sugerir próximos pasos

## Guardrails

- Máximo 3 agentes por ronda — más genera ruido
- Si la discusión se vuelve circular, @dev-orchestrator o @meta-router resume y redirige
- Nunca inventar capacidades de un agente — respetar su perfil documentado
- Si no hay agentes relevantes para el tema, decirlo y sugerir cuál debería consultarse

# SDD en team-ai-harness

> Este documento cierra el marco de **SDD** como doble concepto: **Specification-Driven Development** (proceso) y **System Design Document** (artefacto). Ambos conviven y se refuerzan.

---

## 1. Dos significados, un solo flujo

| Sigla | Significado | Qué aporta |
|---|---|---|
| **SDD (proceso)** | **Specification-Driven Development** | Filosofía: no se escribe código sin una especificación aprobada antes. |
| **SDD (artefacto)** | **System Design Document** | Memoria externa: contexto, arquitectura, contratos y decisiones. |

Para un solo desarrollador con agentes, esta combinación evita:

- *Scope creep*.
- Programar "de memoria" y reescribir a los tres días.
- Que el agente alucine porque no tiene un contrato claro.

> **Regla:** el agente implementa; el owner (o el agente de producto/arquitectura) decide la spec.

---

## 2. Proceso Specification-Driven

### 2.1 Pipeline de 4 pasos

```
Paso 1: Contrato       → PROP-NNN.md (qué, para quién, por qué, ACs)
Paso 2: Diseño lean     → ADR (L3/L4) + SDD artefacto
Paso 3: Desglose        → Épica → [Story] → Tasks atómicos
Paso 4: Ejecución       → TDD / code con el contrato como guía
```

### 2.2 Control de calidad por paso

| Paso | Control | Bloqueante |
|---|---|---|
| 1 | `product-owner` define criterios de aceptación. | Sin ACs no se pasa a épica. |
| 2 | `architect` valida diseño; `security` en L4. | Sin ADR / threat model no se codea en L3/L4. |
| 3 | `dev-orchestrator` desglosa en tasks atómicas con FILE-IDs y TEST-IDs. | Tarea sin entregable verificable = mal desglose. |
| 4 | `qa` + `technical-leader` validan contra la spec original. | TEST-ID faltante o violación de arquitectura = no merge. |

### 2.3 Primero la spec, luego el código

Esto aplica especialmente a APIs, eventos y schemas:

- **API:** escribir primero OpenAPI / contrato de entrada-salida.
- **Eventos:** definir schema del evento antes del publisher/consumer.
- **Base de datos:** definir modelo relacional y constraints antes de migrations.
- **Inter-service:** definir el contrato HTTP/gRPC antes de implementar client.

La spec puede ser markdown, OpenAPI, SQL DDL o un `tasks.md` con FILE-IDs/TEST-IDs. Lo importante es que exista **antes** del código.

---

## 3. Artefacto System Design Document

El SDD no es un PDF de 40 páginas. Para este workflow responde tres preguntas:

1. **¿Qué problema resuelve esto?** → `PROP-NNN.md`, `ENN-*.md`.
2. **¿Cómo se comunica?** → OpenAPI, contratos de eventos, inter-service contracts.
3. **¿Qué arquitectura va a usar?** → ADR, `tasks.md`, plan atómico, diagramas.

### 3.1 Artefactos del SDD en este repo

| Artefacto | ¿Qué spec contiene? | Dónde vive |
|---|---|---|
| `PROP-NNN.md` | Qué construir, para quién, por qué, ACs. | `roadmap/proposals/` (o donde defina el equipo) |
| `ENN-*.md` | Alcance de la épica, stories opcionales, dependencias, ceremony level. | `roadmap/epicas/` |
| `STOR-NNN.md` | Comportamiento observable del usuario final. | `roadmap/stories/` (opcional) |
| `ADR-XX.md` | Decisión estructural, alternativas, consecuencias. | `docs/adr/` |
| `tasks.md` | FILE-IDs, TEST-IDs, contratos, layers, plan de documentación. | `openspec/changes/[nombre]/` |
| Plan atómico | Desglose por sesión con dependencias y entregables verificables. | `management/plans/<proyecto>/` |
| Workflow skills | Reglas de proceso (hexagonal/DDD, code review, commits, PR). | `skills/dev/*` |

### 3.2 Story: capa opcional entre Épica y Task

```
PROP-NNN.md → ENN-*.md → [STOR-NNN.md] → tasks.md → FILE-IDs / TEST-IDs
```

| Caso | ¿Story? |
|---|---|
| Feature con impacto de usuario visible | **Sí**. Traduce el valor de usuario a tasks técnicas. |
| Refactor, infra, servicio interno, normalización técnica | **No**. Épica → Task directo. |

El owner / `product-owner` decide si una épica necesita story. No es obligatoria.

---

## 4. Integración con el harness de agentes

### 4.1 Hermes, Claude Code y OpenCode

| Runtime | Qué hace con nuestros agentes |
|---|---|
| **Hermes** | Es el backend de conversación. No invoca `@agent` nativamente; nosotros aplicamos el workflow manualmente usando sus tools (Engram, skills, terminal, etc.). |
| **Claude Code** | Lee `.claude/agents/` generado por `sync-agents.sh`. Soporta `@agent` como subagente con modelo/tool propio. |
| **OpenCode** | Lee `.opencode/agents/` generado por `sync-agents.sh`. Soporta subagentes multi-provider. |

**Conclusión:** el workflow no se ejecuta solo. Depende de que el owner (o el agente activo) respete el marco. Los agentes canónicos son guiones de comportamiento; la disciplina es humana.

### 4.2 Cómo un agente aplica SDD

Cada agente canónico tiene en su prompt:

- Qué skill cargar.
- Qué artefactos leer antes de actuar.
- Cuándo detenerse por falta de spec.
- Cómo guardar el handoff en Engram.

Ejemplo de guardrail en `dev-orchestrator`:

```
L2+ sin spec clara con criterios de aceptación → BLOQUEADO.
L3/L4 sin ADR → BLOQUEADO.
L4 sin consulta previa a @architect + @security → BLOQUEADO.
```

---

## 5. Relación con `iteye`

`iteye` es el **panel de control** del ecosistema. Para auditar el uso de Hermes y el respeto del workflow, debe recolectar:

| Dato | Para qué sirve |
|---|---|
| Sesiones por proyecto | Costos reales de tokens / modelo. |
| Agente invocado y por qué | Detectar si se salteó ceremony level. |
| Spec vinculada a la sesión | Ver si se codeó sin PROP/épica/task. |
| Estado del handoff (Engram) | Medir fricción entre sesiones. |
| Tareas atómicas completadas | Calcular velocidad y ajustar granularidad. |

Esto convierte a `iteye` en el observador del proceso SDD, no solo un visualizador de proyectos.

---

## 6. Checklist antes de codear

Para toda feature L2+:

- [ ] `PROP-NNN.md` aprobado con criterios de aceptación.
- [ ] `ENN-*.md` creada y vinculada en `roadmap.yaml`.
- [ ] [Opcional] `STOR-NNN.md` si impacta usuario final.
- [ ] Para Go: `hexagonal-workflow`, `hexagonal-go`, `go-hex-audit` cargadas.
- [ ] `tasks.md` con FILE-IDs y TEST-IDs antes de la primera línea de código.
- [ ] Plan atómico vinculado si es cross-project / multi-servicio.
- [ ] L3/L4: ADR aprobado.
- [ ] L4: `@security` consultado.

---

## Referencias

- `AGENTS.md` — arquitectura de agentes, ceremony levels, flujo de documentos.
- `docs/workflow-hexagonal-ddd.md` — flujo Go con `go-hex-audit`.
- `skills/dev/hexagonal-workflow/SKILL.md` — skill canónica del flujo Go.
- `skills/dev/hexagonal-go/SKILL.md` — guía de arquitectura hexagonal + DDD para Go.
- `skills/dev/go-hex-audit/SKILL.md` — pipeline de auditoría.
- `skills/software-development/atomic-session-planning/SKILL.md` — desglose atómico.
- `.hermes/plans/INDEX.md` — planes atómicos vinculados a este proyecto.

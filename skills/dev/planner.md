---
name: planner
description: Genera plan de implementación con FILE-IDs y TEST-IDs. Produce documentos de planificación que guían el ciclo de desarrollo. Invocado por @technical-leader (L2/L3) y @architect (L3/L4). Output destino → openspec/changes/[nombre]/tasks.md
---

# Planner — Plan de Implementación

Generá un plan estructurado antes de escribir código. **NUNCA empezás a codear.**

## Quién invoca esta skill

| Agente | Nivel | Documentos que genera |
|--------|-------|----------------------|
| `@technical-leader` | L2 | Doc 1 (scope) + Doc 2 (FILE-IDs clave) + Doc 3 (happy paths) |
| `@technical-leader` | L3 | Doc 1 + 2 + 3 completos + Doc 4 (docs plan) |
| `@architect` | L3 | Doc 1 + 2 + 3 completos + Doc 4 + contratos formales |
| `@architect` | L4 | Todos + Doc 5 (AI context) + edge cases de seguridad |

Output destino: `openspec/changes/[nombre-feature]/tasks.md`

## Inputs

- Descripción del feature (del owner o de `openspec/changes/[nombre]/proposal.md`)
- Ceremony level (L2, L3, o L4)
- Contexto del codebase: arquitectura existente, patrones, `PROJECT.md` si existe

## Proceso

### Paso 1: Entender scope

Leer descripción. Si existe spec, leer `proposal.md`. Explorar codebase:
- ¿Qué módulos o bounded contexts se afectan?
- ¿Qué layers necesitan cambios?
- ¿Qué patrones existentes hay que respetar?
- Si `PROJECT.md` existe: respetar STACK-XX, RULE-XX, SVC-XX al asignar paths

### Paso 2: Generar documentos

#### Doc 1: Plan General (todos los niveles)

```markdown
# Plan: [Nombre del Feature]

## Scope
- En scope: ...
- Fuera de scope: ...

## Estrategia
[1-3 párrafos sobre el enfoque]

## Servicios afectados
| Servicio | Cambios |
|---------|---------|
| ...     | ...     |

## Riesgos
| Riesgo | Probabilidad | Mitigación |
|--------|--------------|------------|
| ...    | ...          | ...        |
```

#### Doc 2: Code Plan con FILE-IDs (L2+)

Cada archivo a crear o modificar recibe un FILE-ID único.

```markdown
# Code Plan

## FILE-ID Table

| FILE-ID | Path | Action | Layer | Descripción |
|---------|------|--------|-------|-------------|
| F-001   | src/domain/model/entity.ts | CREATE | Domain | [qué hace] |
| F-002   | src/domain/port/repo.ts | CREATE | Domain | [interfaz de repositorio] |
| F-003   | src/application/usecase/action.ts | CREATE | Application | [orquestación] |
| F-004   | src/infrastructure/adapter/pg-repo.ts | CREATE | Infrastructure | [implementación DB] |
| F-005   | src/infrastructure/controller/handler.ts | MODIFY | Infrastructure | [HTTP handlers] |

## Orden de implementación

OBLIGATORIO respetar dependencias de layer:
1. **Domain** (F-001, F-002) — lógica de negocio pura primero
2. **Application** (F-003) — orquestación
3. **Infrastructure** (F-004, F-005) — detalles técnicos
4. **Presentation** — componentes UI al final

## Contratos (L3/L4 — uno por FILE-ID)

Firma pública declarada. El Code Reviewer verifica match exacto en L4.

- **F-001**: `class Entity { id: UUID; field: string; static create(...): Entity; validate(): void }`
- **F-002**: `interface EntityRepository { save(ctx, e): Promise<void>; findById(ctx, id): Promise<Entity|null> }`
- **F-003**: `class ActionUseCase { execute(req: ActionRequest): Promise<ActionResponse> }`
```

**Reglas para FILE-IDs:**
- L2: archivos clave únicamente (no exhaustivo)
- L3: todos los archivos afectados
- L4: todos los archivos + contratos completos (cada campo, cada firma, cada error type)

#### Doc 3: Test Plan con TEST-IDs (L2+)

```markdown
# Test Plan

## TEST-ID Table

| TEST-ID | FILE-ID | Tipo | Escenario | Expected |
|---------|---------|------|-----------|----------|
| T-001 | F-001 | Unit | Crear entidad con datos válidos | Entidad con UUID |
| T-002 | F-001 | Unit | Crear con campo requerido vacío | ValidationError |
| T-003 | F-001 | Unit | Validar con valor fuera de rango | DomainError |
| T-004 | F-003 | Unit | Ejecutar con duplicado | ConflictError |
| T-005 | F-004 | Integration | Guardar y recuperar por ID | Persistido correctamente |
| T-006 | F-005 | Unit | POST sin auth | 401 |
| T-007 | F-005 | Unit | POST con body válido | 201 + entidad |

## Coverage Matrix

| FILE-ID | TEST-IDs | Cobertura objetivo |
|---------|----------|--------------------|
| F-001   | T-001, T-002, T-003 | 90% |
| F-003   | T-004 | 80% |
| F-004   | T-005 | 40% (integration) |
| F-005   | T-006, T-007 | 60% |
```

**Mínimo requerido por FILE-ID (L2+)**: happy path + 1 error path + 1 edge case.

L4 agrega obligatoriamente: casos de seguridad — sin auth, permisos incorrectos, inputs maliciosos, límites de rate.

#### Doc 4: Documentation Plan (L3+)

```markdown
# Documentation Plan

| Doc | Acción | Descripción |
|-----|--------|-------------|
| API spec | UPDATE | Agregar endpoints de [feature] |
| README | UPDATE | Agregar sección de [feature] |
| ADR-NNN | CREATE | Decisión: [nombre] (si corresponde) |
```

#### Doc 5: AI Context (L4 only)

```markdown
# AI Context

## Contexto para sesiones futuras de IA
- Este feature agrega [qué]
- Decisión clave no obvia: [cuál y por qué]
- Patrón que sigue: [cuál de los existentes en el codebase]

## Orden de lectura recomendado
1. [archivo base a entender primero]
2. [F-001 — nuevo aggregate]
3. [F-003 — orquestación]
```

### Paso 3: Validación cruzada

Antes de entregar el plan verificar:
- [ ] Cada FILE-ID tiene al menos un TEST-ID
- [ ] Orden de implementación respeta dependencias de layer
- [ ] Contratos son consistentes entre FILE-IDs (sin contradicciones)
- [ ] No hay TEST-IDs huérfanos (todos referencian FILE-IDs válidos)
- [ ] Si > 20 FILE-IDs → sugerir dividir en múltiples specs

## Output

Escribir el plan en `openspec/changes/[nombre]/tasks.md`. Presentar al owner. Pedir aprobación antes de pasar a implementación.

## Escala por ceremony level

| Nivel | Doc 1 | Doc 2 FILE-IDs | Doc 3 TEST-IDs | Doc 4 Docs | Doc 5 AI |
|-------|-------|----------------|----------------|------------|----------|
| L1 | Breve (verbal) | Skip | Skip | Skip | Skip |
| L2 | Sí | Parcial (clave) | Happy paths | Skip | Skip |
| L3 | Sí | Completo | Completo | Sí | Skip |
| L4 | Sí | Formal + contratos | Formal + security cases | Sí | Sí |

## Guardrails

- **NUNCA empezar a codear** — solo planificar
- FILE-IDs siguen orden de layer: Domain → Application → Infrastructure → Presentation
- Si ambigüedad arquitectural → recomendar explorar codebase antes de planificar
- Si el proyecto no usa arquitectura en capas → adaptar Layer a la estructura real (e.g., Services/Controllers/Models)

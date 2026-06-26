# ENN: [Título descriptivo — qué logra esta épica]

**Hito:** H[N] — [Nombre del hito]
**Prioridad:** Crítica | Alta | Media | Baja
**Estado:** pendiente
**Servicios / repos:** [lista de servicios afectados, o "N/A"]
**Ceremony level:** L[1-4]
**Detalle de ejecución:** estándar | reforzado  ← reforzado si el backing model es abierto (Hermes/Kimi/Ollama). Ver Tareas.
**Propuesta origen:** PROP-NNN (o "iniciativa directa")
**Spec:** — (se completa al crear spec → `openspec/changes/[nombre-kebab]`)

## Contexto

Por qué esta épica existe ahora. Qué antecede, qué bloqueó, qué cambió. 3-5 oraciones.
Incluir refs a decisiones previas (ADR-XX, PROP-NNN) si aplican.

## Objetivo

Una oración: "Al completar esta épica, [QUIÉN] puede [HACER QUÉ]."

## Contexto a cargar (antes de ejecutar)

> Lista cerrada de qué leer para tener TODO lo necesario sin explorar el repo a ciegas.
> Crítico para modelos con contexto acotado (Ollama Cloud): si un dato no está acá, el ejecutor no lo conoce.

| Ref | Qué | Por qué se necesita |
|-----|-----|---------------------|
| `path/al/archivo.ext` | [qué contiene] | [qué patrón/contrato/dato aporta] |
| `management/PROJECT.md` | STACK-XX, RULE-XX, SVC-XX | restricciones del proyecto |
| ADR-NNN / PROP-NNN | [decisión previa] | [qué fija que no se renegocia acá] |

## Tareas

> **Cada tarea es atómica y verificable por sí sola** — un ejecutor débil (Hermes/Kimi vía Ollama
> Cloud) la completa sin inferir contexto faltante. Granularidad por nivel:
> - **L1** → acción + "Hecho cuando" (una línea cada uno basta).
> - **L2** → + `Objetivo` (path/área exacta) + `Depende de`.
> - **L3/L4** o **Detalle de ejecución: reforzado** → + `Contrato` (firma exacta, vía planner FILE-ID).
> Si una tarea no entra en un bloque atómico → es una fase: partila. Si hay >12 tareas → dividir la épica.

- [ ] **T1 · [acción atómica — verbo + objeto concreto]**
      Objetivo: `path/exacto` (función/módulo si aplica)
      Hecho cuando: `comando o check` → [resultado esperado observable]
      Depende de: ninguna
- [ ] **T2 · [acción]**
      Objetivo: `path`
      Hecho cuando: `check` → [esperado]
      Depende de: T1
      Contrato: `firma pública exacta` ← solo L3/L4/reforzado (ver planner FILE-ID)
- [ ] **T3 · Smoke / test de cierre**
      Objetivo: [flujo end-to-end concreto]
      Hecho cuando: `comando` → [evidencia de que el objetivo de la épica se cumple]
      Depende de: T2

## Criterios de validación

### Automáticos (verificables por agente)
- [ ] [Tests pasan / endpoint responde / build OK — con el comando exacto]
- [ ] [Otros checks programáticos]

### Manuales (requieren validación del owner)
- [ ] [Flujo funciona en staging / demo]
- [ ] [Otros checks visuales o de negocio]

## Dependencias

- **Necesita:** [E00, PROP-NNN, o "ninguna"]
- **Desbloquea:** [E00, o "ninguna"]

## Riesgos

- [Riesgo] → [Mitigación]

## Notas

(Decisiones de diseño, links a specs, contexto adicional)

---

<!-- ESTADOS:
  pendiente    → En backlog, no hay nadie trabajando en esto
  en-progreso  → Trabajo activo
  bloqueado    → No puede avanzar, documentar bloqueo en Notas
  completo     → Todas las tareas y criterios validados
  deprecado    → No se implementará (documentar por qué)
-->

<!-- DETALLE DE EJECUCIÓN:
  estándar  → backing model frontier (Claude Opus / Codex). El modelo rellena contexto razonable.
  reforzado → backing model abierto (Hermes / Kimi / Ollama Cloud). Tareas atómicas con path +
              "Hecho cuando" + Contrato obligatorios, aunque el ceremony level sea L1/L2.
              Regla: a menor capacidad del modelo, mayor explicitud del artefacto.
-->

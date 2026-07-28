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

## Estructura del roadmap (roadmap único, multi-proyecto)

Desde 2026-07-02 hay **un solo `roadmap.yaml`** para toda la plataforma (decisión del owner,
`$DEVY_ROADMAP_PATH`, default `management/roadmap.yaml`) — reemplaza el esquema anterior de un
archivo por scope (`platform/roadmap.yaml` + `projects/<nombre>/roadmap.yaml`). Cada hito/épica
dentro de ese archivo lleva `proyecto: <nombre>` (`platform` = lab-wide, o el nombre del proyecto
cliente). Este skill resuelve primero **qué proyecto** aplica antes de leer o escribir nada — los
IDs (`HNN`, `ENN`) son únicos DENTRO de un proyecto, no globalmente.

```
management/roadmap.yaml         ← ÚNICO índice: hitos + épicas de TODOS los proyectos,
                                   cada entrada con `proyecto: <nombre>` y `archivo:` self-sufficiente

management/platform/            ← lab-wide (Devy) — infra, harness, gobernanza del lab
  epicas/                          (archivo: "platform/epicas/...")
  propuestas/

management/projects/<nombre>/   ← namespace propio por proyecto cliente
  epicas/                          (archivo: "projects/<nombre>/epicas/...")
  propuestas/
```

### Cómo resolver el proyecto (SIEMPRE antes de leer/escribir)

1. **Proyecto explícito en el pedido** (nombre de repo/servicio: `mercado-cercano`, `iteye`,
   `riotless`, `whatsapp-agent`, `notification-service`, `iam-service`, `team-ai-harness`) →
   `proyecto: <nombre>`. Usar el mapeo de `management/projects/README.md` para normalizar el
   nombre (ej. `pocs/whatsappAgent` → `whatsapp-agent`).
2. **Pedido sobre infra/harness/observabilidad/gobernanza del lab, o sin proyecto identificable** →
   `proyecto: platform` (default).
3. **Ambiguo** (podría ser de proyecto o lab-wide) → una sola pregunta: "¿Esto es del roadmap de
   `<proyecto>` o del roadmap del lab (`platform`)?". No asumir.
4. **cwd NO es una señal confiable por sí sola** — correr un pedido/loop dentro del working
   directory de un servicio (ej. `active/mercado-cercano/services/ledger-service`) no implica que
   el `proyecto:` correcto sea `mercado-cercano`; puede ser una tarea de `platform` que
   simplemente opera sobre código de ese servicio (descubierto en el piloto de E33/T7,
   2026-07-02). Usarlo como señal secundaria, nunca como única fuente.
5. Al referenciar un ID fuera de su propio proyecto, calificarlo: `mercado-cercano/E12` vs
   `platform/E12` (los namespaces NO se renumeran).

Todo lo que sigue en este skill usa `<proyecto>` como el valor resuelto arriba, y `<scope-dir>`
como el prefijo real de `archivo:` para ese proyecto (`platform/` o `projects/<nombre>/`).

## Cuándo leer el roadmap (siempre antes de proponer)

Antes de sugerir cualquier trabajo nuevo:
1. Resolver el proyecto (ver arriba).
2. Leer `$DEVY_ROADMAP_PATH` filtrado por `proyecto: <proyecto>` — ¿ya existe una épica para esto? ¿Qué hito está activo (`fase_actual` del proyecto)?
3. Si existe épica → referenciar su ID en la respuesta, calificado con el proyecto si se menciona fuera de contexto
4. Si no existe → crear propuesta en lugar de ejecutar directamente

## Cómo crear una propuesta

Trigger: pedido de trabajo nuevo no reflejado en el roadmap.

```
@meta-router crear epica [descripción]
@product-orchestrator nueva propuesta [descripción]
```

### Proceso

1. Leer `$DEVY_ROADMAP_PATH` filtrado por `proyecto: <proyecto>` → determinar hito activo y
   próximo ID de propuesta (PROP-NNN) DENTRO de ese proyecto (los números de PROP no son
   globales — cada proyecto tiene su propia secuencia en su `<scope-dir>/propuestas/`)
2. Copiar `<scope-dir>/propuestas/_TEMPLATE.md`
3. Completar todos los campos del template:
   - `Estado: borrador`
   - Hito propuesto (alineado con `fase_actual` del proyecto)
   - Tareas concretas (verbos en infinitivo, resultados observables)
   - Criterios de validación auto + manual
   - Ceremony level estimado (L1-L4)
   - `Detalle de ejecución` (estándar | reforzado — ver más abajo)
4. Guardar como `<scope-dir>/propuestas/PROP-NNN-descripcion-corta.md`
5. Presentar al owner para aprobación — NO ejecutar sin aprobación explícita para L2+

## Cómo crear una épica (propuesta aprobada)

Trigger: propuesta aprobada por el owner.

1. Determinar próximo ID de épica (E01, E02... secuencial) DENTRO del `proyecto` resuelto — no
   globalmente. Verificar que el ID no colisione con una épica **del mismo proyecto** (colisión
   con otro proyecto es esperable y no es un error, ej. `platform/E24` y `mercado-cercano/E24`
   pueden coexistir).
2. Copiar `<scope-dir>/epicas/_TEMPLATE.md`
3. Completar template con las tareas y criterios de la propuesta aprobada
4. Guardar como `<scope-dir>/epicas/ENN-descripcion-corta.md`
5. Agregar entrada en la lista `epicas:` del roadmap único (`$DEVY_ROADMAP_PATH`):
   ```yaml
   - id: ENN
     proyecto: <proyecto>
     nombre: "[nombre]"
     hito: H[N]
     estado: pendiente
     prioridad: [nivel]
     depende_de: [KEY-ENN, ...]   # opcional — ids PREFIJADOS de épicas que deben estar `estado: completo` antes
     archivo: <scope-dir>/epicas/ENN-[nombre].md   # ej. "platform/epicas/..." o "projects/mercado-cercano/epicas/..."
     servicios: [lista]
   ```

6. La `descripcion:` **NO va en el índice** — va en el hermano `roadmap-descripciones.yaml`,
   como entrada top-level `<ID>: "[una oración]"`:
   ```yaml
   PLAT-E40: "[una oración]"
   ```

   **Por qué está partido** (2026-07-27, medido): el índice es lo único que TODA iteración del
   loop carga entero para elegir la próxima tarea, y el 53% de sus bytes eran descripciones —
   32,7 KB de ellas pertenecientes a épicas ya `completo`, cargadas para no usarse nunca. El
   split bajó el índice de 122,1 KB a 47,8 KB sin perder un solo campo. La descripción se lee
   del hermano **bajo demanda y de a una**, y sólo cuando hace falta de verdad: si la épica ya
   tiene `archivo:`, la fuente de verdad es ese archivo y la descripción no aporta nada.

   `scripts/split-roadmap.py check` falla si una descripción vuelve al índice — correrlo después
   de tocar el roadmap. `scripts/split-roadmap.py split` migra las que se hayan colado.

   **`depende_de:` es la fuente verificable por máquina del orden de ejecución** (la consume
   `loop-next-task` §1ter para decidir elegibilidad). El árbol narrativo en comentarios YAML
   es solo documentación y NO gobierna nada — probó driftear. Reglas:
   - Ids siempre prefijados (`PLAT-E24`, `MC-E05`) aunque la dependencia sea del mismo proyecto.
   - Omitir el campo = épica desbloqueada (no escribir `depende_de: []`).
   - Al agregar/cambiar orden de ejecución, actualizar el campo — no solo el comentario.

## El "Hecho cuando" es la parte que más se escribe mal

Un criterio de aceptación mal redactado no falla ruidosamente: **se cumple**. El agente lo
satisface al pie de la letra, marca `[x]` con razón, y el trabajo queda sin hacer sin que nadie
se entere. Tres casos en dos días (2026-07-26/28):

| Caso | El criterio pedía | Lo que no verificaba |
|---|---|---|
| PLAT-E38 T-STK-M3 | un spam de `/health` | lo que la tarea anterior ya había declarado insuficiente |
| PLAT-E39 T2–T6 | "devuelve la misma lista que pim" | la autorización — razón de ser de la épica (objeción B1 de @dev-security) |
| PLAT-E39 T1a | healthy + `/health` + `/metrics` | la estructura que el propio contrato prometía |

Cuatro reglas, todas verificables por `scripts/check-criterios.py`:

1. **Cubrí el contrato.** Cada artefacto que el contrato promete tiene que aparecer en el criterio.
   Si el contrato lo nombra y el criterio no lo mira, no se va a hacer.
2. **Que sea ejecutable.** Un comando o un código de respuesta, no prosa. "Funciona correctamente"
   no es un criterio.
3. **Decí qué debe FALLAR.** Un criterio que sólo prueba el camino feliz pasa igual con el control
   ausente. `curl` sin token → **401**; `INSERT` con el usuario read-only → **error de permisos**;
   `grep` del patrón prohibido → **sin resultados**.
4. **Que sea verificable HOY.** No escribas un check E2E sobre una superficie que la tarea no monta:
   si la ruta todavía no existe, `curl` devuelve 404 y el check "pasa" sin probar nada. Ese chequeo
   pertenece a la tarea que crea la ruta.

```bash
scripts/check-criterios.py platform/epicas/PLAT-E39-*.md   # una épica
scripts/check-criterios.py --all --solo-abiertas           # todo lo pendiente
```

Es heurístico: avisa, no bloquea. Un aviso falso se ignora en dos segundos; uno real cuesta una
épica entera ejecutada sobre criterios que no prueban nada.

## Cómo actualizar estado

Al completar tareas o épicas:

```yaml
# En el roadmap único — cambiar estado de la épica (identificar por id + proyecto, no solo id)
- id: E03
  proyecto: mercado-cercano
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

## Estándar de granularidad — tareas ejecutables por modelo abierto

El harness debe correr indistintamente con backing model **frontier** (Claude Opus, Codex) o
**abierto** (Hermes, Kimi `kimi-k2.7-code:cloud`, otros vía Ollama Cloud). Un modelo abierto NO
rellena contexto implícito: cada tarea tiene que ser autosuficiente o se cuelga/alucina.

**Regla central:** a menor capacidad del backing model, mayor explicitud del artefacto. El ceremony
level dice cuánto *proceso*; el `Detalle de ejecución` dice cuánta *especificidad por tarea*.

| Detalle | Cuándo | Cada tarea lleva |
|---------|--------|------------------|
| `estándar` | backing frontier | acción + "Hecho cuando" |
| `reforzado` | backing abierto (Hermes/Kimi/Ollama) | acción + `Objetivo: path` + `Hecho cuando: comando → esperado` + `Depende de` + (L3/L4) `Contrato` |

**Al escribir tareas de una épica (post-aprobación):**
1. Toda tarea es **atómica** — una acción, un resultado verificable. Si describe una "fase", partila.
2. **Dividir cuando el tamaño amerita (P-22, no negociable):** si la épica agrupa múltiples
   servicios/entidades independientes, o su volumen esperado (archivos, tablas, endpoints) es
   grande, partir en un grupo de tareas por servicio/unidad — nunca una tarea única monolítica
   que abarque todo el bundle. Se decide al escribir la épica, no "se evalúa después". Ejemplo
   real: una épica que agrupe 4 servicios con volúmenes dispares (ej. 21 archivos de migración
   vs. 5) necesita un grupo de tareas por servicio, cada uno con su propio "Hecho cuando".
3. Toda tarea tiene **"Hecho cuando"** = comando o check concreto + resultado esperado observable.
4. En `reforzado`: agregar `Objetivo` (path/módulo exacto) y `Depende de` (orden explícito).
5. L3/L4 o `reforzado`: agregar `Contrato` (firma pública) — delegar a `skills/dev/planner` para
   FILE-IDs/TEST-IDs en `workspace/[nombre]/tasks.md`.
6. Completar **Contexto a cargar** de la épica: lista cerrada de paths a leer. Si un dato no está
   ahí ni en los archivos linkeados, el ejecutor abierto no lo conoce — explicítalo.

Las **propuestas** quedan livianas (una línea por tarea, acción + resultado). El detalle atómico se
expande recién en la **épica**, que es lo que se ejecuta.

## Guardrails

- NUNCA ejecutar trabajo L2+ sin propuesta aprobada por el owner
- NUNCA crear épica sin ID secuencial único
- Roadmap.yaml es single source of truth — toda épica tiene entrada ahí
- Al mover una épica entre hitos, actualizar AMBOS lugares (yaml + archivo)
- Propuestas en `borrador` son solo ideas — el owner decide si avanzan

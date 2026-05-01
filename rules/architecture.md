# Architecture Rule (Always-On)

> Este archivo define las reglas de arquitectura del proyecto. Los agentes lo leen como parte del contexto de diseño técnico.
> Fuente de autoridad: PROJECT.md P-XX. Este archivo detalla — no redefine.

## Patrón de backend

> Completar con el patrón elegido para este proyecto.

### Opción A: Hexagonal / Clean Architecture

```
domain/           → Lógica de negocio pura, sin imports de frameworks
  model/          → Entidades, Agregados, Value Objects
  service/        → Domain Services
  port/inbound/   → Contratos expuestos por este bounded context
  port/outbound/  → Contratos para dependencias externas
application/      → Orquestación de casos de uso, depende SOLO de domain
  usecase/        → Una clase por caso de uso
  dto/            → Request/Response DTOs
infrastructure/   → Detalles técnicos, implementa ports
  controller/     → Entry points HTTP/gRPC
  adapter/        → Implementaciones de repositorios y gateways
  persistence/    → Modelos ORM + mappers domain↔persistence
```

**Reglas de dependencia:**
- `domain/` no importa nada de `application/` ni `infrastructure/`
- `application/` solo importa de `domain/`
- `infrastructure/` implementa `domain/port/outbound/`
- Controllers llaman Use Cases — NUNCA domain directamente

**Flujo:** `Controller → Use Case → Domain Service / Port → Adapter`

### Opción B: MVC estándar

```
[Completar con las capas y restricciones del proyecto]
```

---

## Patrón de frontend

> Elegir y completar con el patrón del proyecto.

### Opción A: Atomic Design (React/Next.js/Vue)

| Nivel | Importa | Contiene |
|-------|---------|---------|
| Atoms | Nada | Button, Input, Icon |
| Molecules | Solo Atoms | FormField, SearchBar |
| Organisms | Atoms + Molecules + hooks | DataTable, Header |
| Templates | Atoms + Molecules + Organisms | DashboardLayout |
| Pages | Templates + Organisms | Data fetching, routing |

**Violaciones a flagear:**
- Atom importando otro componente
- Molecule importando un Organism
- Page con lógica de negocio embebida

### Opción B: Feature-based structure

```
features/
  [feature-name]/
    components/
    hooks/
    api/
    types/
```

---

## Comunicación entre servicios

> Completar con el patrón de comunicación del proyecto.

```yaml
# Ejemplo multirepo
sync_communication:  # para queries
  protocol: REST
  gateway: [ej: Kong en :8001 / API Gateway]
  auth: [ej: JWT via header Authorization]

async_communication:  # para eventos
  protocol: [ej: RabbitMQ / Kafka / SQS]
  pattern: [ej: pub/sub / queue]
```

**Regla:** Todo tráfico externo pasa por el API Gateway — ningún frontend se conecta directo a servicios.

---

## Violaciones comunes a detectar

- Dominio importando un framework u ORM
- Use Case con más de 50 líneas (señal de mezcla de concerns)
- Controller con lógica de negocio (>5 líneas de non-HTTP code)
- Llamada directa entre servicios sin pasar por el gateway
- [AGREGAR violaciones específicas del proyecto]

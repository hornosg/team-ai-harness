# Security Rules (Always-On)

> Reglas de seguridad siempre activas. Aplican a todo el proyecto sin excepción.
> Ver también: PROJECT.md RULE-01 a RULE-03. Este archivo detalla — no redefine.

## Secretos y credenciales

- **NUNCA** hardcodear API keys, passwords, tokens, o connection strings en código
- Siempre en variables de entorno o servicio de vault (ej: AWS Secrets Manager, HashiCorp Vault, doppler)
- Rotación: secretos de producción rotan al menos cada 90 días
- Keys de desarrollo en `.env.local` — NUNCA commitear `.env` files con valores reales

## Autenticación y sesiones

- Access tokens: expiración corta (≤15 min para operaciones críticas, ≤1h standard)
- Refresh tokens: expiración máxima 7 días, con rotation (el token anterior se invalida)
- Hash de passwords: bcrypt (cost ≥12) o argon2id — NUNCA MD5, SHA1, SHA256 sin salt
- Protección contra timing attacks en comparación de tokens (comparación constante)
- Session invalidation completa en logout (no solo client-side)

## Datos sensibles en logs

- **NUNCA** loggear: passwords, tokens, CVV, número de tarjeta completo, datos biométricos
- Emails y nombres: loggear solo si es crítico para debugging — con tag `[PII]` para filtro
- Log levels: ERROR para failures, WARN para anomalías, INFO para flujos de negocio, DEBUG solo en dev

## Inputs y validación

- Validar **todo** input en el boundary del servicio — nunca confiar en el cliente
- Sanitizar antes de queries (ORM con parámetros preparados — NUNCA concatenar SQL)
- Validar tamaño máximo de payloads — configurar límites en API Gateway
- CSRF protection en formularios que modifican estado

## Operaciones críticas (L4)

Cualquier feature que toque estas áreas → L4 obligatorio:
- Pagos o flujos monetarios
- Autenticación y autorización
- Almacenamiento de credenciales
- Exportación masiva de datos de usuarios
- Cambios en roles y permisos

## [AGREGAR reglas específicas del proyecto]

```
# Ejemplo: si el proyecto maneja tarjetas
- PCI DSS: preferir tokenización via proveedor certificado (Stripe, MP) sobre manejo directo
- Nunca almacenar CVV ni track data bajo ninguna circunstancia
- Idempotency keys en todas las operaciones de cobro
```

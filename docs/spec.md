# GoalTime — Especificación (Spec-Driven Development)

> La especificación es la fuente de verdad. El código y los tests se derivan de este documento.
> Estado: **DRAFT v1 (contract-first)** — pendiente de validar contra el repo Flask real.

## 1. Contexto

GoalTime es un sistema de **reservas de canchas sintéticas** (Riohacha, Colombia).
La app móvil (este proyecto) está escrita en **Flutter (Android/iOS)** y consume una
**API REST** existente construida en **Flask + SQLAlchemy** (PostgreSQL en production).

Roles: **Cliente**, **Dueño de cancha**, **Admin** (multi-dueño: cada dueño gestiona
solo sus canchas).

## 2. Entidades (dominio)

| Entidad | Descripción | Campos clave (sujeto a validación backend) |
|---|---|---|
| Cliente | Usuario del sistema | id, nombre, email, password_hash, rol_id (FK Maestra) |
| Cancha | Cancha sintética registrada | id, nombre, ubicacion, dueno_id, activo, foto |
| Horario | Slot/tarifa de una cancha | id, cancha_id, dia, hora_inicio, hora_fin, tarifa |
| Reserva | Reserva de un horario por un cliente | id, cancha_id, horario_id, cliente_id, fecha, estado |
| Pago | Registro de pago de una reserva | id, reserva_id, monto, metodo, estado |
| Maestra | Catálogos genéricos (estados/tipos/roles) | id, tipo, codigo, valor |

## 3. Contrato de API

Base URL: `https://goaltime-app.onrender.com` (a confirmar).

### 3.1 Auth
```
POST /api/register
  req { name, email, password }
  res 201 { access_token, rol }        | 409 email en uso

POST /api/login
  req { email, password }
  res 200 { access_token, rol }        | 401 credenciales inválidas

POST /api/logout   (auth)  → 204
```

### 3.2 Cliente
```
GET /api/canchas
  res 200 [ { id, nombre, ubicacion, foto, activo } ]

GET /api/disponibilidad?cancha_id=1&fecha_inicio=2026-09-24
  res 200 [ { horario_id, fecha, hora_inicio, hora_fin, tarifa, disponible } ]
  — entrega slots para los próximos 6 días

POST /api/reservas                          (auth: cliente)
  req { cancha_id, horario_id, fecha }
  res 201 { reserva_id, estado }            | 409 slot ocupado | 422 inválido

GET /api/mis-reservas                       (auth: cliente)
  res 200 [ { reserva_id, cancha, horario, fecha, estado, pago } ]
```

### 3.3 Pago (pasarela real — a implementar en backend)
```
POST /api/pagos/checkout  (auth)  req { reserva_id } → { checkout_url | client_secret }
POST /api/pagos/webhook   (Stripe) → confirma Reserva + Pago
GET  /api/pagos/{reserva_id}      → { estado }
```

### 3.4 Dueño (filtrado por `dueno_id`; Admin puede acceder a cualquiera)
```
GET/POST  /api/canchas
PATCH/DELETE /api/canchas/{id}
GET/POST/PATCH/DELETE /api/canchas/{id}/horarios
GET /api/canchas/{id}/reservas
PATCH /api/reservas/{id}   → confirmar / cancelar reserva
```

### 3.5 Admin
```
GET  /api/usuarios
PATCH /api/usuarios/{id}/rol    → asignar rol Dueño/Cliente; desactivar
GET  /api/reporte               → agregados para gráficas (ingresos, reservas por cancha/día)
```

## 4. Códigos de error comunes

| Código | Significado |
|---|---|
| 400 | Request mal formado / validación de campos |
| 401 | Token ausente/vencido o credenciales inválidas |
| 403 | Sin permisos para el rol (Ej. cliente llama endpoint de dueño) |
| 404 | Recurso no existe |
| 409 | Conflicto (slot ya ocupado, email en uso) |
| 422 | Regla de negocio violada (ej. fecha pasada) |
| 500 | Error de servidor — la app muestra estado genérico |

## 5. Criterios de aceptación por feature

**Auth**
- [ ] `login` con credenciales válidas conserva el token y el rol en la sesión
- [ ] `login` con email no registrado o password incorrecto muestra error claro (401)
- [ ] Token vencido → refresh/relogin sin pérdida de datos de pantalla

**Catálogo y disponibilidad**
- [ ] Se listan solo canchas activas
- [ ] La disponibilidad muestra 6 días a partir del día actual
- [ ] Un slot ya ocupado se muestra como NO disponible y no se puede seleccionar

**Reserva**
- [ ] No se puede reservar un slot ocupado (validación 409)
- [ ] No se puede reservar una fecha pasada
- [ ] Antes de confirmar se muestra resumen (cancha, fecha, hora, tarifa) y se pide confirmación
- [ ] Éxito → confirmación visible con ticket/resumen; error → mensaje recuperable

**Pago**
- [ ] El checkout redirige a la pasarela y el webhook confirma la reserva
- [ ] Si el pago falla, la reserva queda en estado pendiente con opción de reintentar

**Dueño**
- [ ] Un dueño solo ve/editan sus canchas (aislamiento por `dueno_id`)
- [ ] CRUD de horarios con validación de solapamiento
- [ ] Puede confirmar/cancelar reservas de sus canchas

**Admin**
- [ ] Puede ver todos los usuarios/canchas y cambiar roles
- [ ] El reporte refleja agregados correctos (monto, conteos por cancha/día)

## 6. Alcance fuera de este documento

- Cancelación con regla de 24h (roadmap backend)
- Motor de sugerencias
- Recordatorios por email (APScheduler)
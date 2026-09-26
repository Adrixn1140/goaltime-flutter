# GoalTime — Especificación (Spec-Driven Development)

> La especificación es la fuente de verdad. El código y los tests se derivan de este documento.
> Estado: **v1 (contract-first, build-from-spec)**.

### Trazabilidad del contrato

Al iniciar la implementación se investigó el backend que la app consumía originalmente
(`goaltime-app.onrender.com` en la v0 de este documento). **No fue recuperable**: el
repositorio asociado resultó ser una app React + Firebase, sin `api.py`, sin despliegue
configurado y con el servicio de Render caído (HTTP 503). Se documenta el hallazgo para
trazabilidad; **no hay código que migrar**. A partir de esta versión el backend se
construye desde cero en `backend/` (**Flask + SQLAlchemy**) siguiendo este contrato.

## 1. Contexto

GoalTime es un sistema de **reservas de canchas sintéticas** (Riohacha, Colombia).
La app móvil (este proyecto) está escrita en **Flutter (Android/iOS)** y consume una
**API REST** construida en este mismo repositorio (**Flask + SQLAlchemy**; SQLite en
desarrollo, PostgreSQL en producción). Backend y app se despliegan por separado.

Roles: **Cliente**, **Dueño de cancha**, **Admin** (multi-dueño: cada dueño gestiona
solo sus canchas).

## 2. Entidades (dominio)

| Entidad | Descripción | Campos clave |
|---|---|---|
| Cliente | Usuario del sistema | id, nombre, email, password_hash, rol_id (FK Maestra) |
| Cancha | Cancha sintética registrada | id, nombre, ubicacion, dueno_id, activo, foto |
| Horario | Slot/tarifa de una cancha | id, cancha_id, dia, hora_inicio, hora_fin, tarifa |
| Reserva | Reserva de un horario por un cliente | id, cancha_id, horario_id, cliente_id, fecha, estado |
| Pago | Registro de pago de una reserva | id, reserva_id, monto, metodo, estado |
| Maestra | Catálogos genéricos (estados/tipos/roles) | id, tipo, codigo, valor |

**Catálogos (`Maestra`)** — valores cerrados, usados por validaciones y tests:

| tipo | codigos |
|---|---|
| `rol` | `cliente`, `dueno`, `admin` |
| `estado_reserva` | `pendiente_pago`, `confirmada`, `cancelada` |
| `estado_pago` | `pendiente`, `aprobado`, `rechazado` |
| `metodo_pago` | `stripe` (producción) · `mock` (demo y tests sin claves) |

**Restricciones que sostienen las reglas de negocio** (no son ornamentales: los tests las verifican):

| Restricción | Regla de negocio que implementa |
|---|---|
| `cliente.email` UNIQUE | `409` en registro si el email ya existe |
| `horario` UNIQUE `(cancha_id, dia, hora_inicio)` | no se crean dos slots que arranquen a la misma hora en la misma cancha |
| `reserva` índice UNIQUE parcial `(cancha_id, horario_id, fecha)` **donde `estado != 'cancelada'`** | **origen del `409`**: un slot sólo admite una reserva viva por día, y una reserva cancelada libera el slot sin perder su histórico |
| `pago.reserva_id` UNIQUE | una reserva tiene como máximo un pago |

**Invariantes de las transacciones** (pruebas de integración):

- `POST /api/reservas` crea la **reserva y el pago en una sola transacción**: si el pago no
  puede insertarse, la reserva tampoco se persiste. Nunca queda una reserva sin pago.
- El webhook de la pasarela confirma `Pago` y `Reserva` en una sola transacción.
- `dueno_id` se deriva del token en backend, **nunca del cuerpo de la petición**.

## 3. Contrato de API

Prefijo `/api`. Formato JSON en request y response. El backend corre en
`http://127.0.0.1:5000` y la app se compila con la URL que corresponda al destino:

| Destino | `--dart-define=API_BASE_URL=` | Nota |
|---|---|---|
| Emulador Android | `http://10.0.2.2:5000` | `10.0.2.2` es el alias del host dentro del emulador |
| Dispositivo Android real (mismo WiFi) | `http://192.168.18.21:5000` | IP del PC; cambia por DHCP, se confirma con `ip -4 -brief addr` |
| iOS simulator | `http://localhost:5000` | |
| Producción | `https://<host>` | por HTTPS; nunca HTTP en release |

El backend debe escuchar en `0.0.0.0` para ser alcanzable desde un dispositivo real:
`flask --app app run --host=0.0.0.0 --port=5000`.

### 3.0 Convenciones
- Autenticación: `Authorization: Bearer <access_token>` (JWT, `flask-jwt-extended`).
- Fechas: `YYYY-MM-DD`. Horas: `HH:MM` 24 h.
- Rol en las respuestas: `cliente` · `dueno` · `admin`. El campo se llama `rol` en la
  respuesta de auth y `rol_id` en el modelo `Cliente`.

### 3.1 Auth
```
POST /api/register            (público)
  req { name, email, password }
  res 201 { access_token, rol, usuario { id, nombre, email, rol } }
     | 400 name/email/password inválidos
     | 409 email ya en uso

POST /api/login               (público)
  req { email, password }
  res 200 { access_token, rol, usuario { id, nombre, email, rol } }
     | 401 credenciales inválidas   (mismo mensaje para email inexistente y password incorrecto)

POST /api/logout   (auth)  →  204
```
- El registro público **siempre** crea el rol `cliente`. Asignar `dueno`/`admin` es una
  operación de Admin (`PATCH /api/usuarios/{id}/rol`), nunca del propio registro.
- `access_token` expira en 12 h (configurable con `JWT_ACCESS_TOKEN_HOURS`); no hay
  refresh token: al expirar, la app cierra la sesión, avisa y vuelve al login.
- `POST /api/logout` es un no-op del lado del servidor (JWT stateless): su propósito es
  que la app descarte el token almacenado. La app lo llama por simetría del contrato.

### 3.2 Cliente
```
GET /api/canchas            (público, sin autenticación)
  res 200 [ { id, nombre, ubicacion, foto, tarifa_base } ]
  — sólo canchas con activo = true, ordenadas por nombre
  — tarifa_base = horario más barato de la cancha, o null si no tiene horarios
  — no expone dueno_id ni activo: el catálogo es público (HEUR-6)

GET /api/disponibilidad?cancha_id=1&fecha_inicio=2026-09-24
  res 200 [ { horario_id, fecha, hora_inicio, hora_fin, tarifa, disponible, motivo } ]
  — entrega slots para los próximos 6 días a partir de fecha_inicio (incluidos)
  — cada fecha usa los horarios cuyo `dia` coincide con su día ISO (0 = lunes)
  — motivo: null si está disponible · "ocupado" · "transcurrido"
  — orden: por fecha y hora_inicio
  — 400 si faltan los parámetros, `cancha_id` no es entero o la fecha no es YYYY-MM-DD
  — 404 si la cancha no existe o está inactiva
  — 200 [] si la cancha no tiene horarios para ninguno de los 6 días

POST /api/reservas                          (auth: rol cliente)
  req { cancha_id, horario_id, fecha }
  res 201 { reserva_id, estado, pago { id, monto, metodo, estado } }
     | 400 body incompleto o fecha mal formada | 403 el rol no es cliente
     | 404 cancha u horario inexistente
     | 409 slot ya reservado | 422 fecha pasada, slot transcurrido, día sin horario
       o `horario_id` que no pertenece a la cancha

GET /api/mis-reservas                       (auth: rol cliente)
  res 200 [ { reserva_id, cancha, horario, fecha, estado, pago } ]
     — el cliente sólo ve sus propias reservas, ordenadas por fecha descendente
```
- La reserva nace `pendiente_pago` junto a su pago `pendiente` (misma transacción);
  `pago.monto = horario.tarifa` calculado en backend.
- El `horario_id` debe pertenecer a la `cancha_id` indicada: si no, `422`.
- **Regla de slot no seleccionable**: `disponible = false` cuando ya existe una reserva
  no cancelada para `(cancha_id, horario_id, fecha)`, o cuando el slot ya transcurrió
  según la hora del servidor (fecha pasada, o la hora de inicio del día ya pasó). El
  endpoint de reserva aplica la misma regla con `422`, para que la app nunca ofrezca un
  slot que el backend vaya a rechazar (HEUR-5: prevención de errores).

### 3.3 Pago (Stripe — modo test en desarrollo)

Flujo: la reserva se crea `pendiente_pago` junto con un pago `pendiente`; el cliente
paga en Stripe Checkout; el webhook confirma ambos. El backend expone la pasarela tras
la interfaz `PasarelaPago` (`backend/pasarelas/`), con implementación `stripe` y
`mock` esta última sólo para tests y demostraciones sin claves.

```
POST /api/pagos/checkout   (auth: cliente propietario de la reserva, o admin)
  req { reserva_id }
  res 201 { pago_id, checkout_url }
     | 404 la reserva no existe
     | 403 la reserva es de otro cliente
     | 409 la reserva no está en pendiente_pago

POST /api/pagos/webhook    (Stripe — SIN JWT, autenticado por firma)
  cabecera Stripe-Signature: t=<timestamp>, v1=<firma>
  res 200 { aplicado, pago, estado_reserva }   — `aplicado: false` si el pago ya no
       estaba pendiente (evento repetido o fuera de orden) o si el tipo no nos interesa
     | 400 firma inválida, evento sin `metadata.pago_id` o pago desconocido,
       timestamp fuera de la tolerancia de 5 minutos
     | 413 el cuerpo supera MAX_CONTENT_LENGTH

GET /api/pagos/{pago_id}   (auth: cliente propietario o admin)
  res 200 { id, reserva_id, monto, metodo, estado }
     | 404 | 403

POST /api/pagos/{pago_id}/simular   (SOLO con PAGADORA=mock — endpoint de demostración)
  req { resultado: "aprobado" | "rechazado" }
  res 200 { aplicado, pago, estado_reserva }
     | 400 resultado desconocido | 403 la pasarela activa no es mock o el pago es ajeno
     | 404
```

- **Quién paga**: el cliente que reservó. El backend comprueba que
  `pago.reserva.cliente_id` sea el del token; un `dueno` o `admin` puede leer el pago
  pero no puede crear el checkout de otro.
- **Idempotencia sin tabla auxiliar**: la transición `pendiente → aprobado|rechazado` se
  aplica con un `UPDATE ... WHERE estado = 'pendiente'` (sólo una transacción gana), y un
  evento repetido o fuera de orden responde `200 { aplicado: false }` sin reescribir.
  El cuerpo del webhook se verifica por firma (`Stripe-Signature`) antes de parsearlo, y
  se acota el tamaño con `MAX_CONTENT_LENGTH`.
- Eventos consumidos: `checkout.session.completed` (aprobado),
  `checkout.session.expired` y `payment_intent.payment_failed` (rechazado). El
  `metadata.pago_id` de la sesión es el ancla; nunca se confía en el `cliente_email`.
- Transiciones resultantes: pago aprobado → `reserva = confirmada`; pago rechazado o
  sesión expirada → `pago = rechazado` y la reserva **vuelve a `pendiente_pago`** para
  permitir reintento (criterio de aceptación de §5).
- Montos calculados en backend a partir de `horario.tarifa`; el cliente nunca envía el monto.
- **Configuración**: `PAGADORA=mock|stripe`, `STRIPE_SECRET_KEY`,
  `STRIPE_WEBHOOK_SECRET`, `STRIPE_CURRENCY` (por defecto `cop`) y `APP_URL_BASE`, de la
  que se derivan las URLs de retorno de Checkout. Las claves viven sólo en `.env`.
- En modo `mock` el `checkout_url` es ilustrativo (no abre una página real): la demo se
  completa con `POST /api/pagos/{id}/simular`, que atraviesa exactamente la misma lógica
  de confirmación que el webhook.

### 3.4 Dueño (aislamiento por `dueno_id`; Admin puede acceder a cualquiera)
```
GET    /api/gestion/canchas
POST   /api/gestion/canchas
PATCH  /api/gestion/canchas/{id}
DELETE /api/gestion/canchas/{id}
GET    /api/gestion/canchas/{id}/horarios
POST   /api/gestion/canchas/{id}/horarios
PATCH  /api/gestion/canchas/{id}/horarios/{horario_id}
DELETE /api/gestion/canchas/{id}/horarios/{horario_id}
GET    /api/gestion/canchas/{id}/reservas
PATCH  /api/gestion/reservas/{id}
```

**Por qué `/api/gestion/*` y no `/api/canchas`.** `GET /api/canchas` es el catálogo
público: sin token, sólo canchas activas y sin `dueno_id`. Si la gestión del dueño
viviera en la misma ruta, la misma llamada devolvería dos cosas distintas según quién
pregunte, y el catálogo público dependería del rol de quien llega. Prefijo aparte,
contrato aparte, tests aparte.

**Reglas de esta sección**
- `dueno_id` sale **siempre** del token, nunca del cuerpo: un dueño no puede crear una
  cancha a nombre de otro. El registro de la cancha ignora cualquier `dueno_id` que
  venga en el `POST`.
- Un dueño sólo accede a sus propias canchas. Sobre la cancha de **otro** dueño se
  responde `404`, no `403`: un `403` confirmaría que el id existe, y el catálogo de
  canchas ajenas no es información que un dueño deba tener. El `403` queda para el caso
  distinto: un `cliente` que llama a una ruta de gestión.
- `DELETE /api/gestion/canchas/{id}` es **baja lógica** (`activo = false`), no borrado:
  las FK son `ON DELETE RESTRICT` y una cancha con reservas no se puede eliminar. El
  dueño la ve en su lista con `activo: false` y puede reactivarla con `PATCH`.
- Un horario **con reservas no se borra ni se mueve** (`409`), canceladas incluidas: un
  registro de reserva apunta a un día y una hora, y si el horario se mueve ese registro
  pasa a hablar de algo que ya no ocurrió. La FK es `ON DELETE RESTRICT`, así que la
  regla va en código y no en un `IntegrityError` sin manejar. Lo único que sí se puede
  cambiar de un horario ocupado es la **tarifa**: el precio de una reserva ya cerrada
  quedó en su pago y no se recalcula.
- Los horarios de una cancha no pueden solaparse entre sí en el mismo día (`422`). El
  `CHECK` de la base cubre orden y rango, no solape, así que la regla va en código y se
  prueba en los dos sentidos: dos horarios que sólo se tocan (`10:00-12:00` y
  `12:00-14:00`) sí pueden convivir, y un horario no se solapa consigo mismo al
  editarlo. Repetir día y hora de inicio sobre uno que ya existe es `409` («ya existe»),
  no `422` («se solapa»): son dos hechos distintos y el mensaje le dice al dueño cuál es.
- `PATCH /api/gestion/reservas/{id}` recibe `{"accion": "confirmar" | "cancelar"}` y sólo
  acepta transiciones válidas (`422` en las demás). **Confirmar exige que el pago esté
  aprobado**: el dueño no puede confirmar una reserva que nadie ha pagado.
- Cancelar libera el slot (el índice UNIQUE de `reserva` es parcial) y **no** devuelve
  el dinero: la regla de cancelación y el reembolso están fuera de alcance (§6).

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

**Formato de error (único para toda la API)**, para que el mapeo en Flutter sea trivial:

```json
{ "error": { "codigo": 409, "mensaje": "El email ya está registrado" } }
```

`mensaje` está redactado en español y es apto para mostrar al usuario (HEUR-2 y HEUR-9):
no incluye stack traces, SQL ni identificadores internos. Los detalles técnicos sólo van al log del servidor.

## 5. Criterios de aceptación por feature

Estado a cierre de la Sesión 4: `backend` = cubierto por `pytest` (`146 passed`),
`app` = cubierto por pruebas de Flutter (`47 passed`).

**Auth**
- [x] `register` crea el usuario con rol `cliente` y devuelve `201` con token; email duplicado → `409` — `backend` `test_auth.py` · `app` "registro crea la cuenta y entra con el rol cliente"
- [x] `login` con credenciales válidas conserva el token y el rol en la sesión — `backend` · `app` "un login correcto guarda la sesión y entra a las canchas" / "con sesión guardada entra directo a las canchas"
- [x] `login` con email no registrado o password incorrecto muestra error claro (401, mismo mensaje en ambos casos) — `backend` · `app` "credenciales incorrectas se muestran con el mensaje del backend"
- [x] Al vencer el token (12 h) la app cierra la sesión, avisa y vuelve al login — `app` "un 401 con token cierra la sesión y devuelve al login" + `sesion_expirada_test.dart`. **No** se conserva lo que había en pantalla: sin refresh token (decisión de §3.1) no hay forma de recuperarlo, y el criterio se reescribió para decir lo que el diseño realmente promete.

**Catálogo y disponibilidad**
- [x] Se listan solo canchas activas, con nombre, foto y precio base — `backend` `test_canchas.py` · `app` "el catálogo ofrece las canchas y entra a la disponibilidad"
- [x] La disponibilidad muestra 6 días a partir del día actual — `backend` · `app` tira `DiaSelector` con 6 días
- [x] Un slot ya ocupado se muestra como NO disponible y no se puede seleccionar — `backend` · `app` "un slot no disponible se muestra deshabilitado con su motivo"
- [x] Un slot ya transcurrido aparece deshabilitado con motivo visible (`ocupado` / `transcurrido`) — `app` mismo test; el backend manda el motivo en `motivo`

**Reserva**
- [x] No se puede reservar un slot ocupado (validación 409) — `backend` `test_reservas.py` · `app` "el 409 al reservar se explica y refresca la disponibilidad"
- [x] No se puede reservar una fecha pasada — `backend` (422) · `app` el slot se muestra deshabilitado y no es seleccionable
- [x] Antes de confirmar se muestra resumen (cancha, fecha, hora, tarifa) y se pide confirmación — `app` "reservar pide confirmación, cobra lo que dice el backend y abre el pago"
- [x] Éxito → confirmación visible con ticket/resumen; error → mensaje recuperable — `app` mismo test (ticket) y "un error al cargar muestra el aviso y reintenta"

**Pago**
- [x] El checkout redirige a la pasarela y el webhook confirma la reserva — `backend` `test_pagos.py` con `MockPasarela` · `app` "simular el pago aprobado deja la reserva confirmada"
- [x] Si el pago falla, la reserva queda en estado pendiente con opción de reintentar — `backend` · `app` "un pago rechazado deja la reserva pagable otra vez" / "un pago rechazado muestra el reintento en la tarjeta"
- [x] Con pasarela real la app ofrece pagar con tarjeta y no simular — `app` "con Stripe la app ofrece pagar con tarjeta, no simular"

**Dueño**
- [x] Un dueño solo ve/edita sus canchas (aislamiento por `dueno_id`) — `backend` `test_gestion.py` ("la cancha de otro dueño da 404, no 403", "el cliente recibe 403", "el dueño ve sólo sus canchas")
- [x] CRUD de horarios con validación de solapamiento — `backend` "horarios que se solapan dan 422", "los que sólo se tocan pueden convivir", "no se puede mover un horario con reservas"
- [x] Puede confirmar/cancelar reservas de sus canchas — `backend` "confirmar sin pago aprobado da 422", "cancelar libera el slot para otro cliente"
- [ ] La app del Dueño lista, crea y edita canchas y horarios, y ve sus reservas — pendiente (parte de app de la Sesión 5)

**Admin**
- [ ] Puede ver todos los usuarios/canchas y cambiar roles — pendiente (Sesión 6)
- [ ] El reporte refleja agregados correctos (monto, conteos por cancha/día) — pendiente

### 5.1 Trazabilidad de pruebas

Cada criterio se deriva de este documento hacia una prueba concreta (spec-driven: la spec
primero, el test después):

| Feature | Backend | Flutter |
|---|---|---|
| Auth | integración con `pytest`: `test_auth.py` | widget: `auth_flow_test.dart` (validación, sesión guardada, login, registro, logout) y `sesion_expirada_test.dart` (401 con token) |
| Catálogo | integración: `test_canchas.py` | widget: `reserva_flow_test.dart` (catálogo, error + reintento, catálogo vacío) |
| Disponibilidad | integración: 6 días y motivos | widget: `reserva_flow_test.dart` (slot ocupado/transcurrido) + `format_test.dart` (agrupación de días) |
| Reserva | integración: transacción atómica y `409` por slot ocupado | widget: confirmación previa, ticket y refresco tras el `409` |
| Pago | integración contra `MockPasarela`: idempotencia del webhook | widget: `mis_reservas_flow_test.dart` (aprobado, rechazado + reintento, Stripe) |
| Gestión Dueño | integración: `test_gestion.py` (aislamiento, solape, confirmar exige pago) | widget: `gestion_dueño_test.dart` (lista, alta, horarios, reservas) |
| Roles | unit + integración: `dueno_id` derivado del token, admin sin filtro | unit: `AuthNotifier` y mapeo de rol |
| Contrato | — | unit: `models_test.dart` (enums y campos anidados) y `format_test.dart` (fechas, moneda, cuerpo del POST) |

Los tests de widget usan `test/support/fake_api.dart`: un `Dio` con el mismo
`crearApiClient` de producción (base URL, timeouts e interceptor de token) y sólo el
adaptador HTTP sustituido por una tabla de rutas. Se prueba el código real, no una copia.


## 6. Alcance fuera de este documento

- Cancelación con regla de 24h (roadmap backend)
- Motor de sugerencias
- Recordatorios por email (APScheduler)
- Recuperación de contraseña y verificación de email
- Sesiones activas multi-dispositivo (revocar tokens)
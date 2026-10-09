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

**Reglas de esta sección**
- Sólo el rol `admin` entra aquí. Un `cliente` o un `dueño` reciben `403`: es distinto
  del `404` de §3.4 porque al admin sí le corresponde saber qué usuarios existen.
- `GET /api/usuarios` lista **todos** los usuarios con `rol` y `activo`, más dos conteos
  (`canchas`, `reservas`) que son la información que el admin necesita para decidir sin
  abrir tres pantallas: un dueño con 4 canchas no es el mismo caso que uno con ninguna.
- `PATCH /api/usuarios/{id}/rol` acepta `{"rol": "cliente"|"dueno"}` y `{"activo": false}`.
  Es la **única** vía para dar de alta un dueño o un admin (así lo dice §3.1) y por eso
  tiene sus propias guardas:
  - Un admin **no se cambia a sí mismo** el rol ni se desactiva (`422`). Con una sola
    cuenta de administración, permitírselo sería un botón de cierre del sistema. Un
    `403` estaría mal: el permiso sí existe, lo que no se permite es la acción.
  - **Bajar de `dueno` a `cliente` exige que no tenga canchas activas** (`422`, con el
    número en el mensaje). Si se permitiera, sus canchas quedarían con un dueño que ya
    no puede gestionarlas: nadie las baja, nadie las ve en el catálogo activo y nadie
    sabe por qué. Las canchas **inactivas sí se quedan** con el usuario, de modo que
    devolverle el rol de dueño recupera su operación. El camino no es un callejón:
    el admin las baja antes con `PATCH /api/gestion/canchas/{id}`, que §3.4 ya le
    permite porque `dueno_o_admin` acepta el rol admin sobre cualquier cancha.
  - Desactivar un usuario no es borrarlo: sus reservas y su historial se quedan, igual
    que con las canchas. Se reactiva con el mismo `PATCH` (`{"activo": true}`).
- Un usuario **inactivo no puede iniciar sesión** (`403` con mensaje propio, después de
  validar la contraseña: si la contraseña fuera incorrecta seguiría siendo `401`, así que
  el mensaje no confirma si el email existe). Además, un token ya emitido deja de servir
  en la siguiente petición, porque `usuario_del_token` valida `activo` en cada llamada:
  desactivar es una medida de seguridad, no un gesto que espere a que el token expire.
- `GET /api/reporte` devuelve agregados listos para dibujar, sin que la app tenga que
  traer reservas y sumar en el cliente:
  - `ingresos.total` suma **pagos aprobados**, no reservas: un pago rechazado o
    pendiente no es dinero. Una reserva cancelada **sí** cuenta, porque cancelar no
    reembolsa (§3.2), así que ese dinero entró.
  - `ingresos.por_cancha` y `reservas.por_cancha` traen `monto`, `reservas` y el nombre
    para poder etiquetar la gráfica sin otra llamada.
  - `ingresos.por_dia` agrupa por `reserva.fecha` (el eje natural de "cuánto entró cada
    día"), no por `pago.creado_en`.
  - Los conteos de reservas salen por estado, incluidas las canceladas, porque al admin le
    interesa ver la tasa de cancelación, no borrarla del agregado.
  - El reporte **no filtra** por `activo`. Una cancha dada de baja hizo ingresos igual, y
    ocultar su fila haría que la suma de la gráfica no cuadrara con el total de arriba: el
    admin lo leería como un bug. El desglose siempre suma el total, y hay un test que lo
    comprueba.
- Desactivar a un dueño **sí** se permite aunque tenga canchas activas, a diferencia de
  quitarle el rol: desactivar es una medida de seguridad y las canchas quedan
  igualmente gestionables por el admin vía §3.4. Un cambio de rol, en cambio, sí exige
  bajar antes las canchas.
- El reporte **no** acepta rango de fechas: la spec no lo promete y agregar un filtro
  que nadie pidió es alcance nuevo. Si hace falta, es una sesión aparte.

#### Errores de §3.5

| Código | Cuándo |
|---|---|
| 400 | Cuerpo sin `rol` o `activo`, o `rol` que no existe en la maestra |
| 403 | Rol distinto de `admin`; usuario inactivo intentando iniciar sesión |
| 404 | `PATCH` sobre un id de usuario que no existe |
| 422 | Admin cambiándose a sí mismo; bajar de dueño con canchas activas |

### 3.6 Asistente de reserva por lenguaje natural

**Estado: implementado en backend y app (28 sep 2026).** El backend está verificado con 43
tests (`test_motores_gemini.py` + `test_asistente.py`) y la app con `asistente_flow_test.dart`.
Corre con `LLM_PROVEEDOR=mock` por omisión; `gemini` está conectado y su integración viva se
probó parcialmente el 28 sep (un saludo respondió `motor=gemini` y una petición disparó la
herramienta con una consulta correcta a la base), quedando la vuelta completa pendiente por la
cuota diaria del free tier. El modelo por omisión es `gemini-3.6-flash`, configurable con
`GEMINI_MODELO`.

```
POST /api/asistente    → respuesta redactada + sugerencias de reserva
```

```json
// cuerpo
{ "mensaje": "quiero jugar mañana en la noche" }

// respuesta
{
  "respuesta": "Mañana por la noche hay dos canchas libres.",
  "sugerencias": [
    { "cancha_id": 1, "cancha": "Las Palmeras", "fecha": "2026-09-28",
      "horario_id": 4, "hora_inicio": "18:00", "hora_fin": "19:00", "tarifa": 45000.0 }
  ],
  "motor": "mock"
}
```

**Reglas de esta sección**
- Sólo el rol `cliente` entra aquí: un `dueño` o un `admin` reciben `403`. El asistente
  reserva en nombre de quien pregunta, y quien pregunta es un cliente.
- **La llave del LLM no sale del backend** (§7.2). La app habla con `/api/asistente` y
  nunca con el proveedor: una llave embebida en un APK es una llave pública.
- El modelo **no ve la base de datos**. Decide qué herramienta llamar, la herramienta se
  ejecuta contra PostgreSQL, y el resultado vuelve al modelo para redactarlo. Lo que sale
  en `sugerencias` son **slots reales**, con su `horario_id`.
- El asistente **no reserva ni paga**. Sugiere; quien confirma es la persona, pulsando un
  botón que lleva a `POST /api/reservas` (§3.2), que es la única vía que reserva. Así el
  alcance se puede recortar sin dejar la app a medias.
- El motor se elige con `LLM_PROVEEDOR` detrás de la interfaz `MotorLLM`, **espejando
  `PasarelaPago` de §3.3**. `mock` responde sin red: es lo que permite probar el endpoint
  en CI y lo que impide que una prueba dependa de un servicio de terceros.

**Herramienta que se expone al modelo**

| Parámetro | Tipo | Qué hace |
|---|---|---|
| `cancha` | texto | nombre o parte del nombre; **el backend lo resuelve a un `Cancha.id`** |
| `fecha` | `YYYY-MM-DD` | dentro de la ventana de 6 días de §3.2 |
| `franja` | `mañana` \| `tarde` \| `noche` \| `cualquiera` | filtro por hora de inicio, definido abajo |

`cancha` es texto y no un id a propósito: el modelo no conoce identificadores, y pedirle
uno lo invitaría a inventarlo en lugar de pedir aclaración. Que lo resuelva el backend es
lo que hace que la sugerencia sea real y no una alucinación con forma de cita.

Una cancha que no se resuelve **no es un error**: devuelve cero sugerencias y una frase
para que el modelo la diga. Es la diferencia entre "no encontré una cancha con ese nombre"
y "te recomiendo una cancha que no existe", y la segunda es la que hace que la gente deje
de confiar en el asistente.

#### Los límites de `franja`

Esta sección declaraba `franja` como un filtro de §3.2 y §3.2 no tiene ninguno, así que
había que definirlos aquí. El criterio es la **hora de inicio** del slot y las fronteras
son medias, para que un slot no pueda estar en dos franjas:

| Franja | Horarios |
|---|---|
| `mañana` | 06:00 a 11:59 |
| `tarde` | 12:00 a 17:59 |
| `noche` | 18:00 en adelante |
| `cualquiera` | todos |

Viven en `dominio/disponibilidad.py` y son valores de negocio, no una constante del
endpoint: `GET /api/disponibilidad` siempre pasa `cualquiera`, así que su comportamiento no
depende de ellos.

#### Errores de §3.6

| Código | Cuándo |
|---|---|
| 400 | `mensaje` ausente, vacío o que no es texto |
| 401 | Token ausente o vencido |
| 403 | Rol distinto de `cliente` |
| 422 | Fecha fuera de la ventana de 6 días, o `franja` que no existe |
| 502 | El proveedor del LLM no respondió, o respondió algo que no se pudo interpretar |

## 4. Códigos de error comunes

| Código | Significado |
|---|---|
| 400 | Request mal formado / validación de campos |
| 401 | Token ausente/vencido, credenciales inválidas o cuenta desactivada |
| 403 | Sin permisos para el rol (Ej. cliente llama endpoint de dueño) |
| 404 | Recurso no existe |
| 409 | Conflicto (slot ya ocupado, email en uso) |
| 422 | Regla de negocio violada (ej. fecha pasada) |
| 500 | Error de servidor — la app muestra estado genérico |
| 502 | Un servicio de terceros no respondió (§3.6, el proveedor del LLM) |

`502` está separado de `500` a propósito: un `500` es un fallo de este código y merece una
corrección, mientras que un `502` es un proveedor externo que no respondió, se arregla
reintentando y la app debe poder ofrecerlo sin que el usuario piense que perdió su sesión.

**Formato de error (único para toda la API)**, para que el mapeo en Flutter sea trivial:

```json
{ "error": { "codigo": 409, "mensaje": "El email ya está registrado" } }
```

`mensaje` está redactado en español y es apto para mostrar al usuario (HEUR-2 y HEUR-9):
no incluye stack traces, SQL ni identificadores internos. Los detalles técnicos sólo van al log del servidor.

## 5. Criterios de aceptación por feature

Estado al cierre: `backend` = cubierto por `pytest` (`278 passed`, los mismos contra
PostgreSQL 16), `app` = cubierto por pruebas de Flutter (`101 passed`, más `9` de contrato
real que corren en CI).

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
- [x] La app del Dueño lista, crea y edita canchas y horarios, y ve sus reservas — `app` `test/gestion_dueno_test.dart` ("el dueño ve sólo sus canchas", "crear una cancha manda nombre y ubicación", "editar carga los datos actuales y manda el PATCH", "crear un horario manda día, horas y tarifa", "las reservas listan quién reservó", "confirmar manda la acción y refresca la lista", "una reserva cancelada no ofrece ni confirmar ni cancelar")
- [x] La app del Dueño da de baja una cancha sin perder su historial y la puede reactivar — `app` "dar de baja pide confirmación y usa DELETE" / "reactivar una cancha inactiva usa PATCH con activo true"
- [x] Un 409 o 422 de la API se muestra con el mensaje del backend y sin dejar la pantalla a medias — `app` "un 422 por solape muestra lo que dice el backend" / "un 422 al confirmar muestra el motivo y refresca"

**Admin**
- [x] Sólo el rol `admin` entra al panel; cliente y dueño reciben `403` — `backend` "un cliente recibe 403" / "un dueño recibe 403"
- [x] Puede ver todos los usuarios con rol, estado y conteos, y cambiar roles — `backend` "lista todos los usuarios con rol y activo" / "trae los conteos de canchas y reservas" / "promueve un cliente a dueño" / "desactiva y reactiva un usuario"
- [x] El admin no puede dejar la plataforma sin administración ni dejar canchas sin dueño — `backend` "el admin no se cambia a sí mismo" / "el admin no se desactiva" / "bajar de dueño con canchas activas da 422 con el número" / "bajar de dueño sólo con canchas inactivas sí se puede"
- [x] Un usuario desactivado no puede entrar ni con un token ya emitido — `backend` "no puede iniciar sesión" / "contraseña incorrecta sigue siendo 401" / "un token ya emitido deja de servir" (`test_auth.py` cubre el 403 del login; `test_sesion_desactivada.py` barre las 18 rutas protegidas una por una, y `test_el_barrido_cubre_toda_ruta_nueva` obliga a clasificar cada endpoint nuevo)
- [x] El reporte refleja agregados correctos (monto, conteos por cancha/día) — `backend` "suma solo pagos aprobados" / "una reserva cancelada con pago aprobado sigue siendo ingreso" / "agrupa por cancha con el nombre para la gráfica" / "agrupa por día de reserva" / "los conteos de reservas salen por estado" / "el reporte conserva el histórico de las canchas dadas de baja"
- [x] La app del Admin muestra usuarios con su rol y sus conteos — `app` `test/admin_flow_test.dart` ("lista cada cuenta con su rol y lo que tiene encima", "sin usuarios se explica, sin romper la pantalla")
- [x] La app cambia roles y activa/desactiva con confirmación — `app` "promover a dueño manda el rol y refresca la lista" / "desactivar pide confirmación y avisa qué se conserva" / "cancelar la confirmación no manda nada al backend" / "una cuenta desactivada lo dice en la tarjeta y se puede activar"
- [x] La app muestra el `422` del backend tal cual, sin traducirlo — `app` "un 422 por canchas activas se muestra tal cual lo dice el backend"
- [x] La app dibuja el reporte con cifras exactas, no sólo la barra — `app` "muestra los tres totales y el desglose por cancha" / "los estados salen con su nombre, no sólo como número" / "sin reservas el reporte lo explica en vez de mostrar ceros solos"

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
| Gestión Dueño | integración: `test_gestion.py` (aislamiento, solape, baja/reactivación, confirmar exige pago, 71 casos) | widget: `test/gestion_dueno_test.dart` (lista, alta/edición, baja/reactivación, horarios, reservas, 24 casos) + `models_test.dart` (reglas de UI) |
| Roles | unit + integración: `dueno_id` derivado del token, admin sin filtro | unit: `AuthNotifier` y mapeo de rol |
| Admin | integración: `test_admin.py` (403 por rol, guardas de autoprotección, agregados del reporte) | widget: `test/admin_flow_test.dart` (lista, cambio de rol, deactivate, reporte) |
| Contrato | — | unit: `models_test.dart` (enums y campos anidados) y `format_test.dart` (fechas, moneda, cuerpo del POST) |
| Asistente IA (§3.6) | integración: `test_motores_gemini.py` (los dos motores, reintentos, errors) + `test_asistente.py` (la herramienta consulta la base, saludo sin sugerencias) | widget: `asistente_flow_test.dart` (mensaje → tarjeta → preselección → confirmar, saludo, caída del proveedor) + `contrato_real_test.dart` (forma de la respuesta contra la API real) |

La fila del asistente estuvo vacía hasta la fase B de [`PLAN.md`](PLAN.md): §3.6 no estaba
implementado y la trazabilidad spec → test **no puede cerrarse con una afirmación falsa**.
Se rellenó el 28 de septiembre, en la misma commit que implementa el asistente.

Los tests de widget usan `test/support/fake_api.dart`: un `Dio` con el mismo
`crearApiClient` de producción (base URL, timeouts e interceptor de token) y sólo el
adaptador HTTP sustituido por una tabla de rutas. Se prueba el código real, no una copia.


## 6. Alcance fuera de este documento

- Cancelación con regla de 24h (roadmap backend)
- Motor de sugerencias
- Recordatorios por email (APScheduler)
- Recuperación de contraseña y verificación de email
- Sesiones activas multi-dispositivo (revocar tokens)

## 7. Esquema, migraciones y despliegue

Todo lo anterior se construyó y probó contra SQLite. SQLite es cómodo en desarrollo
porque ignora cosas que PostgreSQL no: los `varchar(n)` no se truncan (ni se rechazan),
los `NUMERIC` son `float` y el orden alfabético es por byte. **Una base de desarrollo
más permisiva que la de producción esconde exactamente los errores que revientan al
desplegar**, así que esta sección fija cómo se maneja el esquema y cómo se verifica el
contrato contra la base real.

### 7.0 Quién gobierna el esquema

**Alembic es la fuente de verdad del esquema.** `db.create_all()` queda relegado a los
tests (`tests/conftest.py`), por velocidad, y en ningún punto del camino de producción.

- Motivo: `create_all()` **sólo crea lo que falta**; no altera ni borra nada. Un cambio de
  columna en producción se aplicaría a medias, en silencio, sin avisar y sin forma de volver
  atrás. Un `ALTER` equivocado con datos reales no tiene "deshacer" con `rm -f`.
- Un autogenerado, en cambio, es un **borrador**: recoge los `CHECK` de `Horario` y el
  índice parcial (con su `postgresql_where`), y aun así hay que leer el diff, porque lo
  peligroso no es que no sepa crear las tablas sino que no avise de que un `String(120)`
  pasó a `String(180)`, de que un `server_default` desapareció o de que un `ondelete`
  cambió. La revisión manual no comprueba que el archivo esté bien escrito: comprueba que
  diga lo que queríamos decir.

### 7.1 Migraciones

```sh
cd backend
alembic upgrade head          # aplica el esquema; en producción, antes de levantar la API
flask seed-catalogo           # catálogos de `maestra` (idempotente)
flask seed                    # datos de demostración (opcional, fuera de producción)
```

- El **esquema** lo migra Alembic; los **datos** los siembran los comandos de Flask. La
  razón de separarlos: las filas de `maestra` son catálogos cerrados que cambian cuando
  el dominio cambia, y mezclarlos con el esquema obliga a rehacer la base cada vez que se
  agrega un estado nuevo.
- `flask init-db` desaparece. Existía por el `create_all()` y sin migraciones ya no
  significa nada: sobre una base ya migrada no hace nada, y sobre una vacía deja el
  esquema sin control de versiones.
- Cada migración es un archivo versionado, se revisa a mano y es reversible con
  `alembic downgrade`. El autogenerado es un borrador, no una fuente.

### 7.2 Variables de entorno en producción

Las mismas variables de §3.0, con tres exigencias adicionales:

| Variable | Desarrollo | Producción | Por qué |
|---|---|---|---|
| `DATABASE_URL` | `sqlite:///goaltime.db` | `postgresql+psycopg://…` | driver ya en `requirements.txt` |
| `JWT_SECRET_KEY` | clave de `.env` | **obligatoria, aleatoria** | `dev-secret-cambiar-en-produccion` es público en el repo: con él se puede firmar el token de cualquier rol |
| `CORS_ORIGINS` | `*` | dominios reales | HEUR-5: no abrir más superficie de la necesaria |
| `PAGADORA` | `mock` | `stripe` | §3.3 |
| `APP_URL_BASE` | `localhost:5000` | dominio público | de aquí salen las URLs de retorno de Stripe |
| `LLM_PROVEEDOR` | `mock` | `ollama` o `gemini` | §3.6, el mismo mecanismo que `PAGADORA` |
| `GEMINI_API_KEY` | vacía | **obligatoria si `LLM_PROVEEDOR=gemini`** | §3.6: nunca viaja en la app, un APK es público |
| `OLLAMA_URL` | `http://127.0.0.1:11434` | host del servidor | motor local |
| `OLLAMA_MODELO` | `qwen2.5:1.5b` | el que se despliegue | debe sostener function calling |

Las cuatro de abajo son **especificadas y no usadas todavía** (§3.6 no está implementado).
Se documentan aquí para que quien monte el despliegue no las descubra por sorpresa.

### 7.3 Despliegue

`docker-compose.yml` levanta dos servicios: `db` (PostgreSQL 16, volumen nombrado,
healthcheck) y `api` (gunicorn sobre el código de `backend/`). El orden lo garantiza la
dependencia de health, no un `sleep`.

- **La base se crea con `LC_COLLATE=C`.** SQLite ordena por byte y PostgreSQL con locale
  ordena por reglas del idioma: con `es_ES`, `"Zuleima"` aparecería después de `"ana"`.
  Fijar `C` deja el orden igual que en desarrollo y, sobre todo, **determinista**: el
  orden de las listas no puede depender de la configuración regional del servidor.
- La API se sirve con `gunicorn`, no con el servidor de desarrollo de Flask.
- La app no cambia para hablar con el contenedor: el emulador de Android sigue
  apuntando a `http://10.0.2.2:5000`.

### 7.4 Verificación del contrato contra el backend real

`test/support/fake_api.dart` reimplementa a mano el JSON del backend. Es cómodo y rápido,
pero es una **copia**: si un campo se renombra en Flask, los 101 tests de la app siguen en
verde y el error aparece en el dispositivo, en la entrega, delante del profesor.

`test/contrato_real_test.dart` ejercita los repositorios y modelos **reales** contra un
backend real: login de verdad, `GET /api/usuarios`, `GET /api/reporte`, `GET /api/canchas`
y los errores (401, 404, 422) pasando por `ApiException`.

Vive en `test/` y no en `integration_test/` porque `flutter test integration_test/...` exige
un dispositivo conectado, y en este entorno no hay emulador. La suite por defecto lo ve y lo
omite: sin `GOALTIME_API_URL` no se habla con la red, así que `flutter test` sigue siendo
hermético. Lo corre `tool/verificar_integracion.sh` (levanta el `compose`, espera
`/api/health`, siembra y corre la prueba) y el job de integración de CI.

Dos detalles de implementación que no son evidentes:

- `flutter_test` sustituye `HttpClient` por un doble que no habla con nadie. El test lo
  quita con `HttpOverrides.global = null` alrededor de cada llamada y lo restaura después;
  `HttpOverrides.runZoned` no sirve en esta versión.
- El margen de espera del test es de 90 segundos, no los 20 de la app. Verificar una
  contraseña con scrypt cuesta alrededor de un segundo de CPU, y medido en un equipo de dos
  núcleos cargados un login tardó 18 segundos. Los 20 segundos de la app están puestos para
  una red móvil, no para una CPU compartida.

### 7.5 Guardián anti-drift

`alembic check` compara el esquema de la base contra los modelos y **falla si difieren**.
Corre dentro de `pytest` (sobre un SQLite temporal, para no depender de Docker) y en CI
contra PostgreSQL. Es lo que hace de §7.0 una regla y no una intención: sin él, el próximo
`db.Column` sin migración volvería a pasar desapercibido.

### 7.6 Criterios de aceptación

- [x] `alembic upgrade head` crea el esquema completo en una base PostgreSQL vacía, con el índice parcial y los `CHECK` intactos
- [x] Los catálogos se siembran con un comando aparte del esquema y es idempotente
- [x] `alembic check` pasa en verde con los modelos actuales y **falla** si se añade una columna sin migración
- [x] `docker compose up` levanta API + PostgreSQL y `/api/health` responde `ok`
- [x] El orden de usuarios y canchas es el mismo en SQLite y en PostgreSQL (`LC_COLLATE=C`)
- [x] La app monta sus repositorios reales contra el backend real y parsea usuarios, reporte y catálogo
- [x] Un dato más largo que su `varchar` se rechaza con un `4xx` y no revienta con `500` (`400` si es formato o longitud, `422` si es una regla de negocio como la tarifa)
- [x] CI corre backend, app e integración en cada push

Los dos criterios que estaban sin marcar se marcan porque ya se corrieron, no porque se
supiera que debían cumplirse. El workflow `.github/workflows/ci.yml` tiene cuatro jobs —`backend`
(SQLite), `backend-postgres` (la suite completa contra PostgreSQL 16, más `alembic
upgrade head` y `alembic check`), `app` (`flutter analyze --fatal-infos` y la suite) e
`integracion` (el contrato real)— y la primera corrida sobre `main` dio los cuatro en
verde: `278 passed` en SQLite, `278 passed` en PostgreSQL y los `9` tests de
`contrato_real_test.dart` pasando contra una API de verdad.

Eso último es lo que este capítulo llevaba días esperando. El contrato real no se puede
ejecutar en la máquina de desarrollo: `flutter_tester` no sobrevive a la red real con
3.7 GB de RAM y el swap lleno, el kernel lo mata y `flutter_tools` reporta `did not
complete`. Por eso el criterio estaba escrito y sin marcar, con la comprobación manual
de los endpoints como evidencia provisional —login 200, `/api/reporte` sin token 401,
`PATCH /api/usuarios/999999/rol` 404—. Marcarlo sin haberlo corrido habría sido la clase
de mentira que este capítulo existe para evitar; ahora que CI lo corrió, la evidencia es
la corrida entera y el criterio se marca sin reservas.

Un matiz que conviene no perder: el job de integración **depende de que el contrato se
omita en silencio cuando falta `GOALTIME_API_URL`**. En el job `app`, que no define esa
variable, los `9` tests aparecen como `skipped` y el job sigue verde. Es deliberado —
sin la variable la suite por defecto no habla con la red— pero significa que un job
verde no siempre es un job que comprobó algo. El workflow lo evita pasando la variable
explícitamente en el job que sí debe hablar con la API.

### 7.7 Fuera de alcance

- Capturas en dispositivo real: no hay emulador ni dispositivo disponible en el entorno de
  desarrollo. Queda pendiente de hacer a mano, no se puede automatizar desde aquí.
- `PAGADORA=stripe` con claves reales: el camino verificado es el de `mock` (§3.3), que
  recorre el mismo `_aplicar()`. Con claves, además, hay que exponer el webhook.
- Correr el contrato real en este equipo: requiere que `flutter_tester` tenga memoria
  disponible. En CI corre en cada push (§7.6).
## Extensión demostrativa: equipos

El contrato del avance de equipos y jugadores está en [`EQUIPOS.md`](EQUIPOS.md).
Amplía la app del cliente sin alterar reservas ni pagos. Torneos completos quedan
fuera del alcance de esta entrega.

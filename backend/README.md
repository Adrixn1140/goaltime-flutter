# GoalTime API (Flask)

Backend REST de GoalTime. Es la implementación de [`../docs/spec.md`](../docs/spec.md);
si el código y la spec discrepan, **la spec manda** (y se corrige la spec primero).

## Puesta en marcha

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
python -c "import secrets; print(secrets.token_hex(32))"   # -> JWT_SECRET_KEY

alembic upgrade head    # crea el esquema
flask seed-catalogo     # carga los catálogos de `maestra`
flask seed              # usuarios, canchas y horarios de prueba (idempotente)

flask --app app run --host=0.0.0.0 --port=5000
```

`--host=0.0.0.0` es necesario para que la app en un dispositivo Android real alcance
el servidor; desde el emulador basta `127.0.0.1`.

### Cambios de esquema

El esquema lo gobierna **Alembic**, no `db.create_all()`. `create_all()` sólo aparece en
los tests, y `flask init-db` ya no existe: se quitó para que no hubiera dos maneras de
construir el esquema, de las cuales una siempre se olvida.

Si cambia un modelo, la migración va con el modelo, en el mismo commit:

```sh
alembic revision --autogenerate -m "agrega columna X a cliente"
# revisá el archivo generado: alembic no sabe de CHECKs, índices parciales ni renombres
alembic upgrade head
alembic check          # debe decir que no hay diferencias
```

`alembic check` es el guardián: compara el esquema de la base contra los modelos y falla
si divergen. Corre dentro de `pytest` y en CI. Sin él, un `db.Column` sin migración
pasaría desapercibido hasta el despliegue.

Para empezar de cero en desarrollo:

```sh
rm -f instance/goaltime.db && alembic upgrade head && flask seed-catalogo && flask seed
```

### Dónde está la base

`DATABASE_URL=sqlite:///goaltime.db` es una ruta **relativa** a propósito:
Flask-SQLAlchemy la resuelve contra `app.instance_path`, así que el archivo vive en
`backend/instance/goaltime.db` y nunca junto al código (que además está en `.gitignore`).

En producción se cambia la variable y el resto no se toca:
`DATABASE_URL=postgresql+psycopg://usuario:clave@host:5432/goaltime`. El driver
(`psycopg`) ya está en `requirements.txt`; no hace falta en desarrollo ni en los tests.

### Con Docker

Hay un `docker-compose.yml` en la raíz del repositorio, con PostgreSQL 16 y la API:

```sh
cp .env.compose.example .env        # en la raíz, no en backend/
docker compose up -d --build         # migra y siembra al arrancar
curl http://127.0.0.1:5000/api/health
```

PostgreSQL queda en `127.0.0.1:5433` para poder correr la suite y `alembic check`
contra él:

```sh
TEST_DATABASE_URL=postgresql+psycopg://goaltime:goaltime-local@127.0.0.1:5433/goaltime_test pytest -q
```

## Datos de prueba

Password común: `Goaltime123!`

| Rol | Email |
|---|---|
| Admin | `admin@goaltime.test` |
| Dueño | `dueno1@goaltime.test` (2 canchas) · `dueno2@goaltime.test` (1 cancha) |
| Cliente | `cliente@goaltime.test` |

3 canchas × 7 días × 3 slots (08:00, 10:00, 16:00) = 63 horarios. Las fotos quedan
vacías a propósito: se agregan los assets antes de las capturas de la entrega.

## Endpoints

| Método | Ruta | Auth | Estado |
|---|---|---|---|
| GET | `/api/health` | — | ✅ |
| POST | `/api/register` | — | ✅ 201 · 400 · 409 |
| POST | `/api/login` | — | ✅ 200 · 400 · 401 · 403 |
| POST | `/api/logout` | JWT | ✅ 204 |
| GET | `/api/canchas` | — | ✅ 200 (sólo activas, con `tarifa_base`) |
| GET | `/api/disponibilidad` | — | ✅ 200 · 400 · 404 (6 días, con `motivo`) |
| POST | `/api/reservas` | JWT cliente | ✅ 201 · 400 · 401 · 403 · 404 · 409 · 422 · 500 |
| GET | `/api/mis-reservas` | JWT cliente | ✅ 200 (propias, fecha descendente) · 401 · 403 |
| POST | `/api/pagos/checkout` | JWT (dueño o admin) | ✅ 201 · 400 · 401 · 403 · 404 · 409 |
| POST | `/api/pagos/webhook` | firma Stripe | ✅ 200 (`aplicado`) · 400 · 413 |
| GET | `/api/pagos/{id}` | JWT (dueño o admin) | ✅ 200 · 401 · 403 · 404 |
| POST | `/api/pagos/{id}/simular` | JWT (dueño o admin) | ✅ 200 · 400 · 401 · 403 · 404 — sólo con `PAGADORA=mock` |
| — | Gestión del dueño | `/api/gestion/*` (12 endpoints) | ✅ spec.md 3.4 |
| — | Administración | `/api/usuarios`, `/api/reporte` | ✅ spec.md 3.5 |

## Pagar sin claves: la pasarela `mock`

`PAGADORA=mock` (por defecto) permite recorrer el flujo completo sin cuenta de Stripe:
el `checkout_url` es ilustrativo y el pago se cierra con `/simular`, que atraviesa **la
misma** función `_aplicar()` que el webhook. Con `PAGADORA=stripe` hace falta
`STRIPE_SECRET_KEY` y `STRIPE_WEBHOOK_SECRET`, y `/simular` responde `403`.

Flujo con `PAGADORA=mock`:

```sh
BASE=http://127.0.0.1:5000/api
TOKEN=$(curl -s -X POST $BASE/login -H 'Content-Type: application/json' \
  -d '{"email":"cliente@goaltime.test","password":"Goaltime123!"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

# 1) Reservar el primer slot libre que devuelva la disponibilidad
# 2) POST /api/reservas      -> 201 {reserva_id, estado, pago}
# 3) POST /api/pagos/checkout -> 201 {pago_id, checkout_url}
curl -s -X POST $BASE/pagos/1/simular -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"resultado":"aprobado"}'
# -> {"aplicado": true, "pago": {...,"estado":"aprobado"}, "estado_reserva":"confirmada"}
```

Con Stripe real, en vez de `/simular` llega el webhook firmado:

```sh
stripe listen --forward-to localhost:5000/api/pagos/webhook
# copiaprueba el secreto whsec_... a STRIPE_WEBHOOK_SECRET y reinicia el backend
```

## Probar con curl

```sh
curl -s http://127.0.0.1:5000/api/health

TOKEN=$(curl -s -X POST http://127.0.0.1:5000/api/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"cliente@goaltime.test","password":"Goaltime123!"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

curl -s -X POST http://127.0.0.1:5000/api/logout -H "Authorization: Bearer $TOKEN" -i
```

## Tests

```sh
.venv/bin/python -m pytest -q          # toda la suite, sobre SQLite en memoria

# Y la misma suite contra PostgreSQL, que es donde están los tipos que SQLite no aplica:
TEST_DATABASE_URL=postgresql+psycopg://goaltime:goaltime-local@127.0.0.1:5433/goaltime_test pytest -q
```

| Archivo | Qué cubre |
|---|---|
| `tests/test_auth.py` | contrato de `spec.md 3.1` (registro, login, token, códigos) y los topes de longitud de los textos |
| `tests/test_modelos.py` | restricciones de base de datos: `UNIQUE`, `CHECK`, FK y `ondelete=RESTRICT` |
| `tests/test_canchas.py` | catálogo público: sólo activas, orden, `tarifa_base`, sin `dueno_id` |
| `tests/test_disponibilidad.py` | ventana de 6 días, día ISO, motivos `ocupado` / `transcurrido`, validaciones |
| `tests/test_reservas.py` | reserva atómica con su pago, `403`/`422` de rol y de slot, `409` por índice, slot liberado al cancelar, `mis-reservas` |
| `tests/test_pagos.py` | quién paga, idempotencia, firma HMAC real del webhook, `MAX_CONTENT_LENGTH`, pasarela intercambiable |
| `tests/test_gestion.py` |Dueño: aislamiento entre canchas, calendario, y el `422` de tarifa |
| `tests/test_admin.py` | Panel: `403` por rol, conteos, el `422` que no deja degradar a un dueño con canchas, reporte |
| `tests/test_migraciones.py` | el guardián anti-drift: `upgrade head` construye el esquema de los modelos y `alembic check` detecta una columna sin migración |

Las pruebas de disponibilidad usan fechas futuras para no depender de la hora de
ejecución; la regla de "slot transcurrido" se verifica con `slot_vencido()` de forma
determinista y, además, sobre el endpoint con el reloj real.

Las de pagos calculan la firma `Stripe-Signature` con `hmac` y el mismo secreto que la
pasarela, así que ejercitan la verificación real sin red ni claves de Stripe. Las
fixtures de `conftest.py` hacen `commit`: si vivieran en la transacción pendiente, el
`rollback` de un `409` se llevaría por delante al cliente y la cancha de prueba y las
pruebas de atomicidad no podrían distinguir un fallo real de un artefacto del andamiaje.

## Notas de implementación

- **Layout plano** (módulos de primer nivel) al estilo Flask: `flask --app app run`.
  `tests/conftest.py` añade la raíz de `backend/` al `sys.path`.
- **Un formato de error**: `{"error": {"codigo": n, "mensaje": "..."}}`. El mensaje es
  apto para mostrar al usuario (HEUR-2, HEUR-9); el detalle técnico va al log.
- **`POST /api/logout` es un no-op**: el JWT es stateless y no hay lista de revocados
  (queda fuera de alcance, `spec.md 6`).
- **SQLite con `PRAGMA foreign_keys=ON`**: sin él, `ondelete` y las FK no se upholden;
  se activa en el listener de `app.py`.
- **Enums centralizados** en `models.CATALOGOS`; los valores por defecto de las
  columnas se referencian desde ahí, no como literales sueltos.
- **`tarifa_base` sin N+1**: una consulta agregada (`MIN(tarifa)` por cancha) cruzada
  con el catálogo.
- **Ocupación con índice UNIQUE parcial** `(cancha_id, horario_id, fecha) WHERE estado !=
  'cancelada'`: el `409` lo impone la base de datos y no un `SELECT` previo, así que dos
  peticiones simultáneas no pueden colarse; además, una reserva `cancelada` libera el
  slot sin perder su histórico. El calendario nunca revela quién reservó.
- **Reserva y pago en una sola transacción**: si el `INSERT` del pago falla, el `rollback`
  se lleva también la reserva. Nunca queda una reserva sin pago.
- **Pasarelas detrás de `PasarelaPago`** (`pasarelas/`): `mock` y `stripe` implementan
  `crear_checkout` y `verificar_evento`; el blueprint no sabe cuál está activa, la
  resuelve `obtener_pasarela()` según `PAGADORA`. `stripe` sólo se importa con
  `PAGADORA=stripe`, así que los tests corren sin el SDK.
- **El webhook se verifica antes de parsearse**: `construct_event` con la firma y la
  tolerancia de 5 minutos, y `MAX_CONTENT_LENGTH` para acotar el cuerpo. El pago se
  identifica por `metadata.pago_id`; el `cliente_email` que reporta la pasarela no se
  usa, y el monto lo fijó el backend desde `horario.tarifa`.
- **Idempotencia sin tabla auxiliar**: `UPDATE pago SET estado = ? WHERE id = ? AND estado
  = 'pendiente'`. De dos eventos simultáneos sólo uno cambia filas; el otro recibe
  `200 {"aplicado": false}` sin reescribir.
- **Los secretos no se versionan**: `.env` está en `.gitignore` y sólo se versiona
  `.env.example`. Las claves de Stripe entran por `STRIPE_SECRET_KEY` y
  `STRIPE_WEBHOOK_SECRET`.

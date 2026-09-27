# GoalTime

Sistema de **reservas de canchas sintéticas** (Riohacha, Colombia). Proyecto de
asignatura de desarrollo móvil: app **Flutter (Android/iOS)** + **API REST propia**
construida con **Flask + SQLAlchemy** en este mismo repositorio.

**Multi-rol**: `Cliente` (reservar), `Dueño` (gestiona sus canchas) y `Admin` (gestión global).

## Trazabilidad

La v0 de la spec apuntaba a una API ya existente (`goaltime-app.onrender.com`). Al
implementar se verificó que **ese backend no es recuperable**: el repositorio asociado
era una app React + Firebase, sin `api.py` ni despliegue configurado, y el servicio de
Render respondía HTTP 503. No hay código que migrar: el backend se construye desde cero
en [`backend/`](backend/) siguiendo [`docs/spec.md`](docs/spec.md), que pasa a ser el
contrato de construcción (no de migración).

## Stack

| Capa | Tecnología |
|---|---|
| App | Flutter 3 (Android/iOS) — Material 3 |
| Estado | Riverpod |
| Navegación | go_router (shells por rol) |
| Red | dio + interceptor JWT |
| Backend | Flask 3 + Flask-SQLAlchemy + flask-jwt-extended + Alembic |
| Base de datos | SQLite en desarrollo · PostgreSQL 16 en producción (misma capa de modelos) |
| Servidor | gunicorn detrás del `docker compose` |
| CI | GitHub Actions: pytest, PostgreSQL con migraciones, `flutter analyze`/`test` y contrato real |
| Pago | Stripe Checkout + webhook (modo test) tras interfaz `PasarelaPago` |

## Documentación (entregables del curso)

- [`docs/spec.md`](docs/spec.md) — Especificación *spec-driven*: contrato de API, catálogos, restricciones y criterios de aceptación
- [`docs/heuristics.md`](docs/heuristics.md) — Evaluación heurística (Nielsen) + guía de diseño trazable
- [`backend/README.md`](backend/README.md) — Cómo correr la API, variables de entorno y datos de prueba

## Estructura

```
lib/            app Flutter
  core/         dio client + interceptor, tema M3, router, storage seguro
  features/     auth · cliente (canchas/reservas/pago) · gestion (dueño) · usuarios (admin)
  shared/       widgets, formato (fechas y moneda), utilidades
backend/        API Flask
  blueprints/   auth · canchas · disponibilidad · reservas · pagos · gestion · admin
  pasarelas/    base · stripe_pasarela · mock_pasarela
  migrations/   Alembic: el esquema lo gobierna aquí, no `create_all()`
  tests/        pytest (auth, reglas de negocio, anti-drift)
test/           pruebas de Flutter (modelos, formato y widget)
  support/      fake_api.dart: Dio en memoria con el JSON del backend
tool/           verificar_integracion.sh: backend real + contrato de la app
.github/        CI: backend, PostgreSQL con migraciones, app y contrato
```

## Estado del proyecto

- [x] Repo + scaffolding Flutter (Android/iOS)
- [x] Spec API v1 (contract-first) y evaluación heurística
- [x] Fases de contrato cerradas: enums, restricciones, formato de error y flujo de pago
- [x] Backend Flask: estructura, `/api/health` y auth (register/login/logout)
- [x] Seed de datos de prueba
- [x] Sesión 2: catálogo de canchas y disponibilidad de 6 días
- [x] Sesión 3 (API): reservas atómicas con su pago, checkout, webhook firmado e idempotencia, con pasarela `mock` para correr sin claves
- [x] Sesión 4 (app): módulo Cliente completo — login/registro reales con sesión persistente, catálogo, reserva con confirmación, pago (Stripe o simulado), "Mis reservas" con reintento y perfil con cierre de sesión
- [x] Módulo Dueño (CRUD canchas/horarios, reservas propias)
- [x] Módulo Admin (usuarios, reporte)
- [x] Esquema con Alembic y contenedores (`docker compose` con PostgreSQL 16 y gunicorn)
- [x] Verificación en cada push: backend, PostgreSQL con migraciones y anti-drift, app y contrato app ↔ backend real
- [ ] Capturas de la app en dispositivo real

## Ejecutar el backend

```sh
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # claves reales; .env no se versiona
alembic upgrade head          # esquema
flask seed-catalogo           # catálogos
flask seed                    # usuarios, canchas y horarios de prueba
flask --app app run --host=0.0.0.0 --port=5000
```

O con contenedores, que es como se despliega:

```sh
cp .env.compose.example .env  # en la raíz del repositorio
docker compose up -d --build # migra y siembra al arrancar
```

Con `PAGADORA=mock` (por defecto) el flujo de pago se recorre entero sin claves de
Stripe: el checkout devuelve una URL ilustrativa y el pago se confirma con
`POST /api/pagos/{id}/simular`. Detalle en [`backend/README.md`](backend/README.md).

## Ejecutar la app

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000   # emulador Android
```

| Destino | `API_BASE_URL` |
|---|---|
| Emulador Android | `http://10.0.2.2:5000` (valor por defecto) |
| Dispositivo Android real (misma WiFi) | `http://<ip-del-pc>:5000` — ver `backend/README.md` |
| iOS simulator | `http://localhost:5000` |

El valor por defecto es `http://10.0.2.2:5000` porque `10.0.2.2` es el alias que usa el
emulador de Android para alcanzar el `localhost` de la máquina. En un teléfono físico hay
que pasar la IP de la máquina en la red local.

## Pruebas

```sh
flutter analyze   # sin issues
flutter test      # 101 pruebas: modelos, formato, sesión, auth, catálogo, reserva, pago, gestión del dueño y panel de admin
cd backend && pytest -q   # 258 pruebas del backend

# El contrato de la app contra el backend real (levanta Docker, migra, siembra y baja):
tool/verificar_integracion.sh
```

Las pruebas de widget no tocan la red: `test/support/fake_api.dart` monta un `Dio` con un
adaptador propio que responde con el mismo JSON del backend, y la sesión se guarda en un
almacenamiento en memoria. Así se ejercitan los repositorios, los providers y las
pantallas reales, no una copia de la lógica.

Ese doble es una copia, así que hay algo que la vigila:
`test/contrato_real_test.dart` habla con un backend de verdad —login, catálogo, reporte y
los errores 401/404/422 pasando por `ApiException`— y se omite salvo que se le pase
`GOALTIME_API_URL`. `tool/verificar_integracion.sh` se la pasa; en CI corre en cada push.

## Recorrido del módulo Cliente

1. `Iniciar sesión` o `Regístrate` (el registro siempre crea rol `cliente`).
2. `Canchas`: catálogo con nombre, ubicación y precio "desde".
3. Toca una cancha → tira de 6 días y slots; los ocupados y los ya pasados salen
   deshabilitados con su motivo.
4. `Reservar` → resumen con el precio que va a cobrar el backend → `Pagar ahora`.
5. Con `PAGADORA=mock` aparecen "Simular pago aprobado/rechazado"; con Stripe, "Pagar con
   tarjeta" abre el checkout en el navegador y la app consulta el estado al volver.
6. `Mis reservas`: paga o reintenta sin repetir el flujo; `Perfil` cierra sesión.

## Recorrido del módulo Dueño

1. Inicia sesión con una cuenta de rol `dueño`; la app entra directo a `Mis canchas`.
2. `Mis canchas`: lista sólo las tuyas, con cuántos horarios tiene cada una.
3. Toca una cancha → hoja de acciones: `Horarios`, `Reservas`, `Editar datos` y
   `Dar de baja`/`Reactivar`. Ninguna acción destructiva ocurre sin confirmar.
4. `Horarios`: una tira por día de la semana, cada horario con su rango y tarifa.
   Alta, edición y borrado con confirmación; el backend avisa si un horario tiene
   reservas y por eso no se puede borrar.
5. `Reservas`: quién reservó, fecha, estado del pago y qué se puede hacer. `Confirmar`
   sólo aparece con pago aprobado; `Cancelar` avisa que no hay reembolso.
6. `Perfil` cierra sesión y borra también lo que la app tenía en memoria de la gestión.

## Recorrido del módulo Admin

1. Inicia sesión con una cuenta de rol `admin`; la app entra directo a `Usuarios`.
2. `Usuarios`: cada cuenta con su rol, si está activa y cuántos turnos y reservas tiene.
3. Toca la tarjeta → `Cambiar rol` (cliente / dueño / administrador) o
   `Activar`/`Desactivar cuenta`. Desactivar pide confirmación y avisa que el historial
   se conserva; activar no la pide porque no es una acción destructiva.
4. `Reporte`: ingresos cobrados, reservas y usuarios, con el desglose por cancha y por
   día. Cada barra lleva su cifra, y si el desglose no sumara el total la app lo
   advierte en vez de mostrar una gráfica que miente.
5. `Perfil` cierra sesión y limpia la lista y el reporte de la memoria.

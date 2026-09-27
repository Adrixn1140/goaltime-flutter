# Estado de la aplicación

**Snapshot al 26 de septiembre de 2026.** No es un documento de contrato ni una
especificación: el contrato es [`spec.md`](spec.md) y la evaluación de diseño es
[`heuristics.md`](heuristics.md). Este archivo existe para responder, de una vez, *qué
está construido y qué está comprobado*, con la fecha y la evidencia. Si algo aquí
contradice a la spec, manda la spec.

## Resumen

GoalTime es un sistema de reservas de canchas sintéticas para Riohacha: app Flutter
(Android/iOS) y API REST propia en Flask, con tres roles —`Cliente`, `Dueño` y
`Admin`—. Los tres módulos están completos de extremo a extremo, el backend corre en
contenedores contra PostgreSQL 16, y hay verificación automática en cada push con
cuatro jobs, uno de los cuales ejecuta el contrato de la app contra un backend de verdad.

Los 8 criterios de aceptación de [`spec.md` §7.6](spec.md#76-criterios-de-aceptación)
están marcados. Ninguno se marcó sin haberse corrido.

## Avance por sesión

| Etapa | Qué se construyó | Fecha | Commits |
|---|---|---|---|
| Base | Scaffolding Flutter, Android e iOS | 24 sep | `fba586e` |
| Sesión 2 | Catálogo de canchas y disponibilidad de 6 días | 25 sep | `5421f0b` `be2b306` |
| Sesión 3 | Reservas atómicas con su pago, checkout, webhook firmado e idempotencia | 25 sep | `f24bdbe` |
| Sesión 4 | Módulo Cliente completo en la app | 25 sep | `af3c357` |
| Sesión 5 | Módulo Dueño, API y app | 25 sep | `7c34889` `f581102` |
| Sesión 6 | Módulo Admin: usuarios, roles y reporte | 25 sep | `b68b7e6` `f7c7af2` |
| §7 | Alembic como fuente del esquema, contenedores, topes de columna, `LC_COLLATE=C` | 25 sep | `8eb01f6` `bd73019` `105f29f` |
| Cierre | CI en cada push, contrato real, suite ejecutable contra PostgreSQL | 26 sep | `f120849` |
| Seguridad | Una cuenta desactivada no conserva la sesión | 26 sep | `fdc575e` |
| Documentación | Criterios de §7.6 marcados con su evidencia | 26 sep | `e77cfd2` |

Dos commits quedan fuera de la tabla porque no construyen funcionalidad: `ddb4058`
(documentación de estado y trazabilidad heurística) y `61ec5cc` (alinear configuración y
spec con lo que el código hacía).

## Evidencia de verificación

Todo lo de esta tabla se ejecutó, no se dedujo. La corrida de CI citada es
[`36287072950`](https://github.com/Adrixn1140/goaltime-flutter/actions/runs/36287072950).

| Comprobación | Resultado |
|---|---|
| `pytest` sobre SQLite | **278 pasan** |
| `pytest` sobre PostgreSQL 16 | **278 pasan** (17m50s) |
| `alembic check` contra PostgreSQL | `No new upgrade operations detected` |
| `flutter analyze --fatal-infos` | sin issues |
| `flutter test` | **101 pasan**, 9 de contrato real omitidos sin red |
| `contrato real` contra la API en CI | **9 pasan** |
| CI en `main` | **4 de 4 jobs en verde** |

Los cuatro jobs se llaman `Backend (SQLite)`, `Backend (PostgreSQL, migraciones y
anti-drift)`, `App (analyze + tests)` e `integracion`, que en la interfaz de GitHub
aparece como *Contrato app ↔ backend real*.

### Backend: 278 tests

| Archivo | Tests | Qué cubre |
|---|---|---|
| `test_gestion.py` | 74 | Dueño: canchas, horarios, reservas, `dueno_id` del token, solapes |
| `test_pagos.py` | 44 | Checkout, webhook firmado, idempotencia, pasarela `mock` |
| `test_disponibilidad.py` | 36 | Tira de 6 días, slots ocupados y transcurridos |
| `test_admin.py` | 31 | Usuarios, roles, reporte, no dejar la plataforma sin admin |
| `test_reservas.py` | 27 | Atomicidad reserva+pago, `409` por slot ocupado |
| `test_auth.py` | 23 | Registro, login, logout, contraseñas, topes de columna |
| `test_sesion_desactivada.py` | 20 | Barrido de las 18 rutas protegidas ante cuenta desactivada |
| `test_modelos.py` | 12 | `to_dict` y reglas de dominio de los modelos |
| `test_canchas.py` | 8 | Catálogo público |
| `test_migraciones.py` | 3 | Guardián anti-drift: `alembic check` pasa y también falla |

### App: 101 tests + 9 de contrato real

| Archivo | Tests | Qué cubre |
|---|---|---|
| `models_test.dart` | 26 | Parseo de la respuesta del backend a los modelos de la app |
| `gestion_dueno_test.dart` | 24 | Módulo Dueño de punta a punta con la red simulada |
| `admin_flow_test.dart` | 14 | Panel de admin, cambio de rol, activar/desactivar |
| `format_test.dart` | 12 | Fechas, días de la semana y moneda |
| `auth_flow_test.dart` | 8 | Validación, sesión guardada, login, registro, logout |
| `mis_reservas_flow_test.dart` | 6 | Historial, pago pendiente y reintento tras rechazo |
| `reserva_flow_test.dart` | 6 | Catálogo, tira de días, confirmación de la reserva |
| `sesion_expirada_test.dart` | 5 | Un `401` con token cierra la sesión y vuelve al login |
| `contrato_real_test.dart` | 9 | **Sólo en CI.** Repositorios reales contra una API real |

## Decisiones que conviene conocer

Cada una está argumentada en el sitio al que apunta; aquí sólo está el índice.

1. **El backend se construyó desde cero.** La v0 de la spec apuntaba a una API ya
   existente que resultó no ser recuperable: era una app React + Firebase sin `api.py`
   ni despliegue, y el servicio de Render respondía 503. No había código que migrar.
   Ver [`README.md` §Trazabilidad](../README.md#trazabilidad).
2. **Alembic gobierna el esquema.** `create_all()` sólo se usa en los tests, por
   velocidad. Ver [`spec.md` §7.0](spec.md#70-quién-gobierna-el-esquema).
3. **`con_rol` es el filtro único de sesión y de rol.** Vive fuera de cualquier blueprint
   porque gestión, admin y cliente responden a la misma pregunta. Ver
   `backend/auth_helpers.py`.
4. **`mock` es la pasarela verificada.** Recorre el mismo `_aplicar()` que Stripe, sin
   claves. Ver [`spec.md` §3.3](spec.md#33-pago-stripe--modo-test-en-desarrollo).
5. **`LC_COLLATE=C` en la base.** SQLite ordena por byte y PostgreSQL con locale no: con
   `es_ES`, `"Zuleima"` saldría después de `"ana"`. Fijar `C` hace el orden determinista.
   Ver [`spec.md` §7.3](spec.md#73-despliegue).
6. **El doble de la app es una copia, y algo la vigila.** `test/support/fake_api.dart`
   reimplementa a mano el JSON del backend, así que un campo renombrado en Flask dejaría
   los 101 tests en verde. Lo vigila `contrato_real_test.dart`. Ver
   [`spec.md` §7.4](spec.md#74-verificación-del-contrato-contra-el-backend-real).

## Huecos conocidos

Lo que el proyecto **no** hace, escrito sin adornos.

1. **Capturas de la app: pendiente.** No se tomó ninguna. El toolchain de Android está
   instalado y con las licencias aceptadas —SDK 36, emulador 37.1.11, imagen de sistema
   `android-34` y un AVD llamado `cel_test`—, y `/dev/kvm` está presente, así que la
   aceleración por hardware está disponible. Lo que no llegó a pasar es **arrancar el
   emulador**: con 2 núcleos y 3.7 GB de RAM no se intentó. Queda como tarea manual, con
   las instrucciones en [`ENTORNO.md`](ENTORNO.md#emulador-de-android).
2. **Stripe con claves reales no está verificado.** El camino probado de punta a punta
   es el de `PAGADORA=mock`. Con claves reales además habría que exponer el webhook, que
   aquí no se puede. El código de Stripe está detrás de la interfaz `PasarelaPago` y es
   el mismo `_aplicar()`.
3. **El consejo de la app ante un `401` de cuenta desactivada es incorrecto.**
   `lib/core/network/api_exception.dart:114` responde siempre *"Vuelve a iniciar
   sesión."*, pero para una cuenta desactivada ese camino no funciona: el login contesta
   `403` con su propio mensaje. El usuario sí se entera del motivo, pero en la pantalla
   de login y no en el `SnackBar` donde ocurrió el error. Se documenta en vez de
   arreglarse: corregirlo exigiría distinguir en la app dos `401` con el mismo código, y
   el beneficio no compensaba el cambio de contrato.
4. **El contrato real no se puede ejecutar en la máquina de desarrollo.**
   `flutter_tester` no sobrevive a la red real con 3.7 GB de RAM y el swap lleno: el
   kernel lo mata y `flutter_tools` reporta `did not complete`. Corre en CI, que es
   donde está en el workflow.
5. **El contrato se omite en silencio cuando falta `GOALTIME_API_URL`.** En el job
   `app` los 9 tests aparecen como `skipped` y el job sigue verde. Es deliberado —sin
   esa variable la suite por defecto no habla con la red— pero significa que **un job
   verde no siempre es un job que comprobó algo**. El workflow lo evita pasando la
   variable explícitamente en el único job que debe hablar con la API.
6. **Los helpers de token de los tests están duplicados** en `test_admin.py`,
   `test_pagos.py`, `test_reservas.py` y `test_sesion_desactivada.py`. Se duplicaron
   durante el trabajo de la Fase 3 y no se limpió: subir los login helpers a `conftest.py`
   es lo correcto, pero toca cuatro archivos de tests que hoy pasan, y no era parte del
   arreglo que se estaba haciendo.

## Cómo reproducir la verificación

```sh
# Backend, en SQLite
cd backend && . .venv/bin/activate && pytest -q

# El mismo backend contra PostgreSQL de verdad, que es lo que SQLite no puede
# representar (varchar, Numeric, orden por collation). Requiere el stack de Docker
# levantado: docker compose up -d
cd backend
createdb -h 127.0.0.1 -U goaltime goaltime_test   # una vez
TEST_DATABASE_URL=postgresql+psycopg://goaltime:goaltime-local@127.0.0.1:5433/goaltime_test pytest -q

# El guardián anti-drift, contra la base de verdad
DATABASE_URL=postgresql+psycopg://goaltime:goaltime-local@127.0.0.1:5433/goaltime alembic check

# App
flutter analyze --fatal-infos
flutter test

# El contrato de la app contra el backend real, de punta a punta
tool/verificar_integracion.sh
```

## Estado en GitHub

| | |
|---|---|
| Repositorio | [`Adrixn1140/goaltime-flutter`](https://github.com/Adrixn1140/goaltime-flutter) (público) |
| Rama | `main`, sin crotchear, con la verificación de este snapshot en verde |
| Workflow | `.github/workflows/ci.yml`, en cada push a `main` y en cada pull request |
| Entregable | App Flutter + API Flask en `backend/`, con el esquema gobernado por Alembic |

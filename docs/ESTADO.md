# Estado de la aplicación

**Snapshot al 29 de septiembre de 2026 (noche).** No es un documento de contrato ni una
especificación: el contrato es [`spec.md`](spec.md) y la evaluación de diseño es
[`heuristics.md`](heuristics.md). Este archivo existe para responder, de una vez, *qué
está construido y qué está comprobado*, con la fecha y la evidencia. Si algo aquí
contradice a la spec, manda la spec.

> **Actualizado el 29 de septiembre (noche).** Por encima de la nota de la tarde: se
> construyó el **APK de release** y se firmó con una clave local, así que la fase C₂ de
> [`PLAN.md`](PLAN.md) queda a medio camino. Entra con su evidencia en *Evidencia de
> verificación*. **No cambia ningún número de tests** —no hay código nuevo más allá de la
> configuración de firma, `378a0bd`— y sobre todo: **el APK no se ha instalado**, que era
> justo lo que faltaba. Sigue faltando, y en el mismo orden, arrancar el emulador y el
> build de iOS.

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
| Asistente IA (backend) | `POST /api/asistente` + `backend/motores/` (mock/ollama/gemini), disponibilidad extraída | 28 sep | `41658e2` `2efca43` |
| Asistente IA (app) | Chat con sugerencias que preseleccionan la reserva, caso en el contrato real | 28 sep | `557c317` |
| Prueba real de Gemini | `/api/asistente` de punta a punta contra Google, 7 llamadas | 29 sep | `bc42218` |
| Trazabilidad heurística | `heuristics.md` con el mapeo del chat del asistente, 13 decisiones | 29 sep | — |
| APK de release | `flutter build apk --release` con firma local, 55 MB, y `build.gradle.kts` leyéndola de `key.properties` | 29 sep | `378a0bd` |

Dos commits quedan fuera de la tabla porque no construyen funcionalidad: `ddb4058`
(documentación de estado y trazabilidad heurística) y `61ec5cc` (alinear configuración y
spec con lo que el código hacía).

## Evidencia de verificación

Todo lo de esta tabla se ejecutó, no se dedujo. La corrida de CI citada es
[`36465285576`](https://github.com/Adrixn1140/goaltime-flutter/actions/runs/36465285576)
(28 de septiembre, ya con el asistente). Las filas marcadas *"(local, 29 sep)"* se
repitieron en esta máquina el 29 de septiembre.

| Comprobación | Resultado |
|---|---|
| `pytest` sobre SQLite | **322 pasan** (CI 28 sep · local 29 sep) |
| `pytest` sobre PostgreSQL 16 | **322 pasan** (CI 28 sep) |
| `alembic check` contra PostgreSQL | `No new upgrade operations detected` |
| `flutter analyze --fatal-infos` | sin issues (local 29 sep) |
| `flutter test` | **105 pasan**, 10 de contrato real omitidos sin red (local 29 sep) |
| `contrato real` contra la API en CI | **10 pasan**, incluido el caso del asistente |
| CI en `main` | **4 de 4 jobs en verde** (28 sep) |
| **Prueba real de Gemini** | **`POST /api/asistente` con `LLM_PROVEEDOR=gemini` responde `motor:"gemini"` contra Google, de punta a punta** (29 sep, local, ver abajo) |
| `flutter build apk --debug` | **BUILD SUCCESSFUL in 31m11s** (28 sep) |
| APK de debug con `aapt2` y `apksigner` | `com.goaltime.goaltime_flutter` 1.0.0 · target 36 · 3 ABIs · firmado |
| `flutter build apk --release` | **terminó, 55 MB** (29 sep, local) |
| **APK de release** | **`com.goaltime.goaltime_flutter` 1.0.0 · target 36 · 3 ABIs · firmado con `CN=GoalTime Local`, no con la clave de debug** (29 sep, local, ver abajo) |

Los cuatro jobs se llaman `Backend (SQLite)`, `Backend (PostgreSQL, migraciones y
anti-drift)`, `App (analyze + tests)` e `integracion`, que en la interfaz de GitHub
aparece como *Contrato app ↔ backend real*.

Las filas de los **APK** y de la **prueba real de Gemini** no las cubre CI: son de esta
máquina. Hay dos APKs, y conviene no confundirlos. El de **debug** son 164 MB porque lleva
las tres ABIs y los símbolos, y va firmado con el certificado de debug. El de **release**
son 55 MB porque va compilado a código de máquina por AOT, sin símbolos, y va firmado con
un keystore local desechable generado para esto.

**Y no son intercambiables: el de debug no tiene el asistente.** No es una diferencia de
tamaño sino de contenido. El APK de debug se construyó el 28 de septiembre a la 01:03 y el
primer commit del asistente es de las 02:41 del mismo día (`41658e2`), con la app dos horas
más tarde (`557c317`): el binario es anterior al módulo. Se comprobó sobre el código
compilado, no por las fechas del repo — contando el label de la cuarta pestaña
(`cliente_shell.dart:28`), que aparece 9 veces en `libapp.so` del release y **0** en el
`kernel_blob.bin` del debug, mientras que los labels previos (`Canchas`, `Mis reservas`,
`Perfil`) aparecen en los dos. **Para demostrar el asistente hay que usar el de release.**

**Construir un APK no es lo mismo que haberlo probado:** ninguno de los dos se ha instalado
ni ejecutado, que es el hueco 1 y sigue abierto.

### APK de release (29 de septiembre de 2026)

Se generó `android/goaltime-local.jks` con `keytool` y su `key.properties`, y
`android/app/build.gradle.kts` se cambió para que la firma de release salga de ese archivo,
con la de debug como reserva si no está (`378a0bd`). Eso quita el `TODO` de Flutter que
pedía editar el build a mano cada vez que cambiaba la clave, y deja el repo clonado
construyendo sin pasos extra: `key.properties` y `**/*.jks` están en `android/.gitignore`
desde antes, así que **la clave no se versiona y no debe versionarse**.

La firma se comprobó por fuera: no se vio nada más.

| Comprobación | Resultado |
|---|---|
| `apksigner verify --print-certs` | `Signer #1 certificate DN: CN=GoalTime Local, OU=Curso, O=GoalTime, L=Riohacha, ST=La Guajira, C=CO` |
| `aapt2 dump badging` | `com.goaltime.goaltime_flutter` 1.0.0 · target SDK 36 · `arm64-v8a`, `armeabi-v7a`, `x86` |
| Tamaño | 55 MB, con `libapp.so` en las tres ABIs |
| SHA-1 | junto al APK, en `app-release.apk.sha1` |

Las tres ABIs son deliberadas: `x86` es lo que necesita el emulador y `arm64-v8a` lo que
necesita un teléfono físico, así que el mismo archivo sirve para los dos.

**Lo que esto no prueba.** Nada de lo anterior es una prueba de que la app funcione: es
la misma distinción de siempre entre construir y correr. El `adb install` sigue sin
hacerse y, con él, el recorrido completo, las capturas y el cierre del hueco 1. Por eso la
fase C₂ está **a medias** en [`PLAN.md`](PLAN.md), no hecha.

### El APK de release del 29 de septiembre no podía hacer una sola llamada de red

**Verificado el 1 de octubre de 2026, y es el hallazgo más útil de este documento.** Al
preparar la prueba en teléfono físico se comprobó el binario con `aapt2` y `strings`, y el
APK de release **no declaraba `android.permission.INTERNET`**:

```
$ aapt2 dump xmltree --file AndroidManifest.xml app-release.apk | grep -A3 uses-permission
  E: uses-permission
    A: ...:name="com.goaltime.goaltime_flutter.DYNAMIC_RECEILER_NOT_EXPORTED_PERMISSION"
```

El único permiso era el que genera una librería. Flutter declara `INTERNET` por su cuenta
**sólo en debug y profile**; el release se arma con el `AndroidManifest.xml` del proyecto
y nada más. Y el APK de debug **sí** lo traía — se compararon los dos lado a lado:

| | `app-release.apk` | `app-debug.apk` |
|---|---|---|
| `android.permission.INTERNET` | **ausente** | presente |
| `res/xml/network_security_config.xml` | **ausente** | ausente |
| URL horneada en `libapp.so` | `http://10.0.2.2:5000` | `http://10.0.2.2:5000` |

Lo segundo tampoco servía en un teléfono: `10.0.2.2` es el alias que usa el emulador para
alcanzar al host y no resuelve en el LAN. Las dos cosas se corrigieron y se versionaron, y
el APK se reconstruyó el 1 de octubre con la IP del equipo:

```
$ strings libapp.so | grep -E '^http://[0-9.]+:5000'
http://192.168.18.23:5000
```

**Lo que esto corrige de lo escrito arriba:** la sección del APK de release dice que "no son
intercambiables" por el asistente, y eso sigue siendo cierto —pero la razón de fondo era
más grave. El de release no sólo tenía una diferencia de contenido, sino que **no podía
hablar con el backend**. Cualquiera que hubiera leído "el APK de release está firmado y
verificado" y lo hubiera instalado en un teléfono habría visto una app que no carga
nada, sin mensaje. Construir y firmar, entonces, es todavía menos de lo que parecía.

### Prueba real de Gemini (29 de septiembre de 2026)

Se corrió `app.test_client()` in-process contra una SQLite aislada en `/tmp`, con
`LLM_PROVEEDOR=gemini` y la llave de `backend/.env` —el camino que ya recomendaba
[`ENTORNO.md`](ENTORNO.md#problemas-que-ya-ocurrieron-de-verdad), sin tocar el compose—.
Cuatro frases, **7 llamadas** a la API (el cupo diario del free tier es 20 por modelo),
todas con `motor:"gemini"`:

| Frase | HTTP | Motor | Sugerencias | Lectura |
|---|---|---|---|---|
| `hola` | 200 | gemini | 0 | Saludo: el modelo decide no consultar la herramienta |
| `quiero jugar mañana por la noche en cancha El Rodadero` | 200 | gemini | 0 | **Correcto**: el seed no tiene slots de noche (franja = inicio ≥ 18:00) y Gemini lo dice con palabras |
| `quiero jugar en una cancha que no existe llamada Fantasía` | 200 | gemini | 0 | Admite que no encontró la cancha; no la inventa |
| `quiero jugar el próximo mes` | 200 | gemini | 3 | **Borde**: Gemini tradujo "próximo mes" a mañana (2026-09-30), dentro de la ventana, y no hubo `422`. Los `horario_id` son reales y reservables; la fecha fue decisión del modelo |

Todas las sugerencias llegaron con `horario_id` existente y libre en la base aislada: la
propiedad que justifica las dos vueltas del asistente no se rompió con el proveedor real.
El `422` de ventana no se pudo ejercitar contra el proveedor real en esta corrida porque
el modelo nunca devolvió una fecha fuera de la ventana; esa ruta sigue cubierta con motor
inyectado en `test_asistente.py`.

### Backend: 322 tests

| Archivo | Tests | Qué cubre |
|---|---|---|
| `test_gestion.py` | 74 | Dueño: canchas, horarios, reservas, `dueno_id` del token, solapes |
| `test_pagos.py` | 44 | Checkout, webhook firmado, idempotencia, pasarela `mock` |
| `test_disponibilidad.py` | 36 | Tira de 6 días, slots ocupados y transcurridos |
| `test_admin.py` | 31 | Usuarios, roles, reporte, no dejar la plataforma sin admin |
| `test_reservas.py` | 27 | Atomicidad reserva+pago, `409` por slot ocupado |
| `test_auth.py` | 23 | Registro, login, logout, contraseñas, topes de columna |
| `test_asistente.py` | 22 | Asistente: slots reales, topes, cancha inexistente, franja, 400/401/403/422/502 |
| `test_motores_gemini.py` | 21 | Parser de Gemini sin red: herramienta, texto, errores y esquema traducido |
| `test_sesion_desactivada.py` | 21 | Barrido de las 19 rutas protegidas —incluida `/api/asistente`— ante cuenta desactivada |
| `test_modelos.py` | 12 | `to_dict` y reglas de dominio de los modelos |
| `test_canchas.py` | 8 | Catálogo público |
| `test_migraciones.py` | 3 | Guardián anti-drift: `alembic check` pasa y también falla |

### App: 105 tests + 10 de contrato real

| Archivo | Tests | Qué cubre |
|---|---|---|
| `models_test.dart` | 26 | Parseo de la respuesta del backend a los modelos de la app |
| `gestion_dueno_test.dart` | 24 | Módulo Dueño de punta a punta con la red simulada |
| `admin_flow_test.dart` | 14 | Panel de admin, cambio de rol, activar/desactivar |
| `format_test.dart` | 12 | Fechas, días de la semana y moneda |
| `auth_flow_test.dart` | 8 | Validación, sesión guardada, login, registro, logout |
| `mis_reservas_flow_test.dart` | 6 | Historial, pago pendiente y reintento tras rechazo |
| `reserva_flow_test.dart` | 6 | Catálogo, tira de días, confirmación de la reserva |
| `asistente_flow_test.dart` | 4 | Asistente: respuesta, sugerencia → reserva, saludo y caída del proveedor |
| `sesion_expirada_test.dart` | 5 | Un `401` con token cierra la sesión y vuelve al login |
| `contrato_real_test.dart` | 10 | **Sólo en CI.** Repositorios reales contra una API real |

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
   los 105 tests en verde. Lo vigila `contrato_real_test.dart`. Ver
   [`spec.md` §7.4](spec.md#74-verificación-del-contrato-contra-el-backend-real).

## Huecos conocidos

Lo que el proyecto **no** hace, escrito sin adornos.

1. **La app no se ha ejecutado en un dispositivo: no hay capturas.** Hay **dos APKs, y
   los dos se construyeron y se verificaron por fuera**: el de debug el 28 sep y el de
   release el 29, firmado ya con la clave local. Pero **instalar y verlos correr sigue sin
   hacerse**, y sin eso no hay ni una captura; a estas alturas es el único hueco que
   impide cerrar la entrega. El toolchain de Android está instalado y con las licencias
   aceptadas —SDK 36, emulador 37.1.11, imagen de sistema `android-34` y un AVD llamado
   `cel_test`—, y `/dev/kvm` está presente, así que la aceleración por hardware está
   disponible. Lo que no llegó a pasar es **arrancar el emulador**: con 2 núcleos y 3.7 GB
   de RAM no se intentó. Queda como tarea manual, con las instrucciones en
   [`ENTORNO.md`](ENTORNO.md#emulador-de-android) y planificada como fase D en
   [`PLAN.md`](PLAN.md). Ahora que existe el APK de release, es también la fase que
   instala el que de verdad se entregaría.
   **Un requisito que este hueco no mencionaba y que bloquea el APK**: faltaba CMake
   3.22.1, que exige la cadena `flutter_secure_storage` → `jni` → C++ nativo. Está
   documentado en [`ENTORNO.md`](ENTORNO.md#problemas-que-ya-ocurieron-de-verdad) y ya
   está resuelto, así que no es un hueco abierto sino una trampa para quien clone el repo.
   - **Actualizado el 1 de octubre:** este hueco se partida en dos, porque el hardware no
     da para cerrarlo en un solo equipo. La fase **D1** es el teléfono físico y corre aquí;
     la **D2** es el emulador y necesita un equipo con 16 GB de RAM, porque el emulador
     pide 1536 MB por AVD sobre 3.7 GB ya ocupados. El APK de release **se reconstruyó**
     con el permiso `INTERNET` y la URL del LAN —sin eso no podía hacer ni una llamada de
     red, y está medido sobre el binario—, y las comprobaciones sobre ese APK nuevo están
     en *Evidencia de verificación*. Lo que sigue abierto es exactamente lo que dice la
     primera línea: **`adb install` y el recorrido**. El paso a paso de ambas pistas está
     en [`PRUEBA-EN-DISPOSITIVO.md`](PRUEBA-EN-DISPOSITIVO.md).
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
7. **El asistente real mapea mal las fechas relativas fuera de la ventana.** En la prueba
   del 29 sep, "quiero jugar el próximo mes" devolvió sugerencias para mañana
   (2026-09-30), dentro de la ventana: Gemini tradujo mal la fecha, el `422` no salió y la
   persona vería slots del día siguiente en vez de que le dijeran que sólo hay 6 días. Los
   datos sugeridos son reales y reservables —no es una alucinación de horarios—; lo que es
   del modelo es la interpretación de la fecha. La ruta del `422` sigue cubierta con motor
   inyectado en `test_asistente.py`.

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

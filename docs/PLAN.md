# Plan de trabajo pendiente

**Snapshot al 27 de septiembre de 2026.** Este documento es lo contrario de
[`ESTADO.md`](ESTADO.md): aquel responde *qué está construido y qué está comprobado*; este
responde *qué se va a construir, en qué orden y con qué riesgos*. El contrato sigue siendo
[`spec.md`](spec.md) y, si algo aquí lo contradice, **manda la spec**.

Casi nada de lo que sigue se ha ejecutado. Por eso cada afirmación lleva su marca:

- **verificado** — comprobado en esta máquina, con el comando a la vista.
- **inferido** — deducido de la configuración o de la lectura del código, **sin ejecutar**.

Si algo marcado como inferido resulta falso al probarlo, se corrige aquí y en
[`ENTORNO.md`](ENTORNO.md) en el mismo commit. No se deja el texto en un sitio y la
realidad en otro.

## 1. Decisiones tomadas

Tres decisiones que fijan el resto del plan. Se tomaron el 27 de septiembre de 2026.

| Decisión | Elección | Por qué |
|---|---|---|
| Motor del LLM | **Los dos, intercambiables** | `ollama` local y `gemini` free tier detrás de una interfaz, alternados por `LLM_PROVEEDOR`. Cero costo en ambos casos y, sobre todo, testeable sin red |
| iOS | **Hay una Mac disponible** | El ítem 6 del checklist se cierra, aunque el build no se pueda hacer en esta máquina |
| Orden | **Primero los cierres rápidos** | Saber si esta máquina puede producir un APK decide si la fase D existe |

La decisión del LLM es la que más valor aporta al proyecto y la que menos cuesta: espeja
un patrón que **ya existe en el repo**. `backend/pasarelas/` resuelve el mismo problema para
el pago — una interfaz, dos implementaciones, una factory con import perezoso y caché — y
`LLM_PROVEEDOR` juega exactamente el papel de `PAGADORA`. La llave de Gemini vive sólo en el
backend, igual que las de Stripe (§7.2).

## 2. Hallazgos de hardware, con su evidencia

La máquina de desarrollo tiene **3.7 GB de RAM y 2 núcleos**. Este es el número que
gobierna todo el plan, y es más apretado de lo que sugiere el hueco que se quiere cerrar.

| Hallazgo | Marca | Evidencia |
|---|---|---|
| RAM total 3.7 GB, **1.9 GB disponibles**, 2 núcleos | verificado | `free -h`, `nproc` |
| Swap de 3.9 GB con **9.6 MB usados** | verificado | `swapon --show` |
| `/dev/kvm` presente, imagen `android-34`, AVD `cel_test` (1536 MB, 2 núcleos, sin GPU) | verificado | `avdmanager list avd` |
| Caché de Gradle **caliente**: distribución `gradle-9.3.1-all` y AGP **9.1.0** ya descargados | verificado | `~/.gradle` (5.3 GB), `ls ~/.gradle/caches/modules-2/files-2.1/com.android.tools.build/gradle/` |
| 313 GB de disco libre | verificado | `df -h /` |
| Sin APK construido nunca | verificado | `ls build/` sólo tiene artefactos de test |
| `docker ps` vacío | verificado | el stack no está levantado |
| Egress a internet funciona | verificado | `curl` a google/github responde 200 |

**El swap casi vacío corrige una afirmación de `ESTADO.md`.** Su hueco 4 dice que
`flutter_tester` no sobrevive porque "el swap está lleno". Hoy el swap está prácticamente
vacío, así que esa explicación ya no aplica y la causa real es otra: 1.9 GB disponibles no
alcanzan para el proceso de test más el backend. Cuando se toque ese hueco, se corrige el
texto.

### 2.1 La landmine: `-Xmx8G` en una máquina de 3.7 GB

**Verificado el 27 de septiembre de 2026.** `android/gradle.properties` traía el valor por
defecto del template de Flutter:

```properties
org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m
```

Pedia 8 GB de heap en una caja que tiene 3.7 GB. Como el archivo **está versionado**, el
problema lo heredaba cualquiera que clone el repo en una máquina modesta. Bajado a lo que
sí cabe:

```properties
org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=256m
```

Con ese valor el build llegó a 184 tareas y generó el APK, así que la predicción se
cumplió. **Pero no era el bloqueo real**, y aquí está la lección: se corrigió una causa
plausible sin comprobar antes si era la causa. El build con `-Xmx8G` habría muerto, sí,
pero también moría con la memoria arreglada, y por otra razón (§2.2).

### 2.2 Lo que sí bloqueaba el APK: falta CMake

**Verificado el 27 de septiembre de 2026.** El bloqueo real no era la memoria:

```
> Task :app:configureCMakeDebug[arm64-v8a] FAILED
> [CXX1300] CMake '3.22.1' was not found in SDK, PATH, or by cmake.dir property.
```

La cadena es `flutter_secure_storage` → `jni` → C++ nativo → AGP 9.1.0 exige CMake 3.22.1.
El build muere **al final**, después de casi todo lo demás, que es lo que lo hace
confuso. `flutter doctor` lo avisaba, pero como requisito de escritorio, y parecía no
importar para Android. Sí importa: instalar el `cmake` de la distribución no basta, hace
falta el del SDK con la versión exacta, `sdkmanager "cmake;3.22.1"`.

Nadie lo había detectado porque **nunca se había construido un APK** en este repo. La
cadena de herramientas de Android nunca se exertó.

### 2.3 El build se cuelga en la red sin fallar

**Verificado el 27 de septiembre de 2026.** El primer intento (`flutter build apk --debug`,
con red) pasó unos 40 minutos sin escribir un solo archivo: Gradle esperaba conexiones a
`dl.google.com` que no avanzaban ni daban error. Se reconoce porque el proceso consume
poca CPU y `build/` no cambia.

Se resuelve compilando directo y en modo offline, que es legítimo porque la caché de
Gradle ya tiene la distribución 9.3.1 y el AGP 9.1.0:

```sh
cd android && ./gradlew assembleDebug --offline -Dorg.gradle.daemon=false
```

### 2.4 Qué cuesta de verdad un build en esta máquina

**Verificado el 27 de septiembre de 2026**, con el detalle importante de por qué:

| Condición | Tiempo |
|---|---|
| Con OracleXE corriendo (2 GB en 57 procesos) | **31 min**, swap a 3480/3979 MB |
| Primer intento, además colgado en la red, hasta morir por CMake | 1 h 54 min |

Lo que convierte minutos en horas no es Flutter: es el *oversubscription*. El plan §3.1 ya
advertía de la memoria, y acertó, pero la palanca mayor resultó ser **parar OracleXE**, no
bajar el heap. En una máquina de 8 GB o más, esta fase son minutos.

## 3. Por qué el emulador va de último

El bucle de desarrollo **no necesita emulador**, y esto se verificó antes de planificar:

| Sospecha | Realidad |
|---|---|
| `flutter_secure_storage` exige un dispositivo | No: `lib/core/storage/token_storage.dart:34` tiene `MemoriaSegura`, un almacén en memoria que los tests inyectan. El plugin nunca se toca |
| El contrato real exige un dispositivo | No: `test/contrato_real_test.dart:48` corre en `flutter_tester` y sólo lee `GOALTIME_API_URL`. Es un proceso headless que habla HTTP |

`flutter test` y `pytest` corren headless. El emulador no participa del desarrollo, sólo de
tres momentos: **capturas**, **instalar y verificar el APK**, y **la demo de sustentación**.

La regla que sale de esto: *se construye y se verifica todo lo que se puede medir
automáticamente, y el emulador se enciende una sola vez, al final, cuando ya no queda nada
por cambiar.* Si algo sale mal en A–B, se descubre con tests, no con capturas.

### 3.1 Los tres no caben a la vez

Es la restricción operativa más importante del plan. El emulador pide 1.5 GB y un modelo
local de 1.5 GB pediría lo mismo: compiten por los mismos 1.9 GB.

| Momento | Qué corre | Emulador | Ollama | Peak |
|---|---|---|---|---|
| C₁ | Gradle | apagado | parado | ~1.5 GB |
| A–B | `pytest` / `flutter test` | apagado | opcional | ~1 GB |
| C₂ | Gradle | apagado | parado | ~1.5 GB |
| **Demo del asistente** | Ollama + backend | **apagado** | **encendido** | ~1.5 GB |
| **D** | Emulador + backend | **encendido** | **parado** | 1.5 GB |

`docker compose up -d` sí puede convivir con cualquiera de los dos, porque el stack pesa
~300–400 MB. Lo que no se puede es el emulador y el modelo local a la vez.

### 3.2 Opciones para el modelo local

**tinyllama**, que ya está descargado, es demasiado débil para function calling: no es
que rinda poco, es que no sostiene el protocolo. La alternativa sin costo es `qwen2.5:1.5b`
(~1 GB), que sí cabe. Si se prefiere no depender de la red ni de una Mac, `gemini` con la
capa gratuita de AI Studio cumple el mismo papel con mejor seguimiento de herramientas, a
cambio de una API key.

## 4. Las fases

Cada una con su criterio de aceptación, en forma de lista de verificación: mientras la casilla
esté vacía, la fase no está hecha, por mucho que haya código escrito.

### Fase C₁ — Sondeo de build (**primero**) — **HECHA el 27 de septiembre de 2026**

Arreglar `org.gradle.jvmargs` y `flutter build apk --debug`, con el emulador apagado y
Ollama parado.

*Por qué va primero:* responde una sola pregunta binaria — ¿puede esta máquina producir un
APK? Si la respuesta es no, la fase D hay que replantearla entera, y conviene saberlo en
el minuto 20 y no después de tres días escribiendo backend.

*Resultado: **sí puede**, pero no por la razón que se suponía. La respuesta correcta
estaba en §2.2, no en §2.1. El emulador no hizo falta ni se encendió: el sondeo se
cumple entero en headless, como se suponía en §3.

- [x] El APK se construye sin `OutOfMemoryError` → `BUILD SUCCESSFUL in 31m 11s`
- [x] Existe `build/app/outputs/flutter-apk/app-debug.apk` → 164 MB, firmado e instalable
- [x] `android/gradle.properties` con la memoria ajustada, y nota en `ENTORNO.md` §20

**Lo que se averigua de paso:** el APK es `com.goaltime.goaltime_flutter` 1.0.0, target SDK
36, con `arm64-v8a`, `armeabi-v7a` y `x86`, y firma de debug. Con esto queda probado que
la fase D es posible y que la C₂ no debería tener sorpresas de toolchain.

### Fase A — Asistente IA, backend

`backend/llm/` espejando `backend/pasarelas/`: `base.py` con el ABC y los dataclasses,
`__init__.py` con la factory, y un módulo por motor. `mock_llm.py` es lo que permite que los
tests corran **sin red**, que es la condición para que CI siga en verde.

El único refactor de código existente: la lógica de disponibilidad vive *dentro* del view
(`backend/blueprints/disponibilidad.py:85` lee `request.args`), así que hay que extraer
`calcular_slots(cancha_id, fecha_inicio)` y dejar el view con su validación y sus
`error_response` intactos, para no romper los 36 tests de `test_disponibilidad.py`.

El blueprint nuevo es `POST /api/asistente`, bajo `@con_rol(ROL_CLIENTE)`, registrado en
`app.py`. La llave del LLM sólo en el backend (§7.2).

- [x] `pytest` verde con `LLM_PROVEEDOR=mock`, sin red → **322 pasan**
- [x] `test_asistente.py`: la herramienta devuelve slots **reales** de la base, no un fixture
- [x] `403` para `dueno` y `admin`; `401` sin token
- [x] `calcular_slots` extraído y los 36 tests de disponibilidad siguen en verde

**Desviación del plan, y por qué.** El plan decía `backend/llm/` y `mock_llm.py`; lo
hecho es `backend/motores/` y `mock.py`. El motivo es que `llm` se confunde con el modelo
—el motor es el *proveedor*, y el proveedor trae el prompt, el esquema de la herramienta y
el transporte HTTP—. Se llama `motores` por el mismo motivo por el que existe
`pasarelas`: el patrón es "una interfaz, varias implementaciones, un selector por
configuración", y conviene que el nombre del paquete lo diga.

Lo segundo: el plan decía extraer `calcular_slots(cancha_id, fecha_inicio)`, y la firma
acabó siendo `calcular_slots(cancha, fecha_inicio, ...)`. Recibe la cancha ya resuelta
porque quien la resuelve son dos callers distintos con dos criterios distintos —el endpoint
por id, el asistente por nombre de texto— y meter esa diferencia dentro de la función
significa que el asistente pasaría un id que no tiene.

**Lo que el plan no anticipó:** `franja` está en la spec como un "filtro de §3.2" y §3.2 no
tiene filtro de franja. Los límites había que decidirlos en algún sitio, y ahora están
en `dominio/disponibilidad.py` y en §3.6 de la spec.

### Fase B — Asistente IA, app

`lib/features/asistente_ia/` con `data/`, `state/` y `presentation/`, cuarto
`NavigationDestination` en `cliente_shell.dart` y ruta `/cliente/asistente` en
`app_router.dart`. Toca `test/support/fake_api.dart`, que es donde vive la debilidad
documentada como decisión 6 en `ESTADO.md`: por eso el caso nuevo entra **también** en
`contrato_real_test.dart`, que es lo único que vigila que esa copia no se desincronice.

- [x] `flutter test` verde y `flutter analyze --fatal-infos` sin issues → **105 pasan**
- [x] `asistente_flow_test.dart`: mensaje → opciones → confirmar
- [x] El caso de contrato entra en `contrato_real_test.dart` (sólo CI)
- [x] El contrato entra al CI verde: corrió con **10 tests** en `36465285576`, 28 sep

**Lo que se decidió construyendo.** La UI es un chat en burbujas (`asistente_screen.dart`)
y las sugerencias viajan como tarjetas con botón *Reservar* que navegan a la reserva con
`?fecha=...&horario_id=...`. Ese query params es nuevo: `PantallaReserva(canchaId)`. La ruta
de reserva ahora acepta `fecha` y `horario_id` opcionales para preseleccionar el horario
que el asistente sugirió, y sin ellos se comporta igual que antes (desde el catálogo).
El asistente **no reserva ni cobra**: presentar es `GET/POST /api/asistente` y confirmar es
`POST /api/reservas`, como manda §3.6. El plan no lo decía y se decidió por el flujo.

**Pendiente de la fase B, ya cerrado.** La prueba real con Gemini en el servidor había
funcionado parcialmente el 28 sep —saludo `motor=gemini` y una vuelta con `functionCall`—,
bloqueada por la cuota del free tier (`generate_content_free_tier_requests`, 20
peticiones/día/modelo). **Verificada de punta a punta el 29 de septiembre**, tras el reset
de medianoche PT:

- Corrida con `app.test_client()` in-process contra una SQLite aislada en `/tmp` y
  `LLM_PROVEEDOR=gemini`, **7 llamadas** a la API (cupo diario: 20).
- Cuatro frases, todas con `motor:"gemini"`: saludo, búsqueda nocturna sin slots
  (correcta: el seed no tiene ≥18:00), cancha inexistente que no se inventa, y una
  búsqueda con 3 sugerencias de `horario_id` reales.
- **Borde visible:** "quiero jugar el próximo mes" devolvió sugerencias para mañana
  (2026-09-30) — Gemini tradujo mal la fecha relativa y quedó dentro de la ventana, así
  que el `422` no se ejercitó. Está documentado en `ESTADO.md` (hueco 7) y la ruta del
  `422` sigue cubierta con motor inyectado en los tests.

### Fase C₂ — APK de entrega

`flutter build apk --release` con un keystore local desechable. Es gratis y se instala por
sideload, sin cuenta de Google ni los USD 25 de Play Store. `**/*.jks` ya está en
`android/.gitignore`, así que la clave no se versiona. Ojo: **este** APK ya contiene el
asistente, a diferencia del de la C₁.

- [x] El APK se construye firmado con la clave local → `app-release.apk`, 55 MB,
  `CN=GoalTime Local`, y `app-release.apk.sha1` al lado
- [ ] `app-release.apk` instalado con `adb install`
- [ ] Login y un recorrido completo funcionando en el emulador

**Lo que se hizo el 29 de septiembre por la noche.** Se generó el keystore
`android/goaltime-local.jks` con `keytool` (`CN=GoalTime Local, OU=Curso, O=GoalTime,
L=Riohacha, ST=La Guajira, C=CO`) y su `key.properties`, y `build.gradle.kts` se cambió para
que la firma de release salga de ahí, con la de debug como reserva si el archivo no está
(`378a0bd`). Se quitó así el `TODO` de Flutter que pedía editar el build a mano.

`flutter build apk --release` terminó y produjo 55 MB, frente a los 164 MB del debug: la
diferencia es que el de release va compilado a código de máquina por AOT y no lleva los
símbolos de depuración.
`apksigner verify --print-certs` confirma la firma, y `aapt2 dump badging` da
`com.goaltime.goaltime_flutter` 1.0.0, target SDK 36, con `arm64-v8a`, `armeabi-v7a` y
`x86`. Las tres ABIs son las que hacen que sirva tanto en un teléfono físico como en el
emulador `x86`.

**Lo que sigue sin hacerse, y es lo que de verdad importa:** el APK **no se ha instalado**.
`adb devices` no lista nada y el emulador nunca arrancó, así que las dos casillas que
quedan abiertas las cierra la fase D, no esta. Construirlo y firmarlo no es probarlo: sigue
sin haber ni una captura.

### Fase D — Emulador, instalación y capturas

`emulator -avd cel_test -no-window` con **un solo `adb` en el `PATH`** (el problema que ya
recoge `ENTORNO.md` §Problemas). Levanta el stack y apunta la app a `10.0.2.2:5000`, que ya
es el default de `lib/core/config/api_config.dart:15`.

- [ ] Capturas de los tres recorridos de `README.md` §Recorridos
- [ ] Cierra el hueco 1 de `ESTADO.md`
- [ ] `flutter_tester` con el contrato real, ahora que hay RAM de sobra

### Fase E — iOS, en la Mac

No es reproducible aquí: `flutter build ios` necesita Xcode. Con la Apple ID personal es
gratis, con la limitación de que **la app expira a los 7 días**. Los pasos exactos van a
`ENTORNO.md` en esta fase, no antes: documentar un procedimiento que nadie ha ejecutado
contamina el separador verificado/inferido de ese archivo.

### Fase F — Documentación y CI — **HECHA el 29 de septiembre de 2026**

`heuristics.md` con el mapeo de la pantalla de chat, `ESTADO.md` actualizado al nuevo
estado, `README.md` con el checklist al día y `ci.yml` si el asistente entra al contrato.
`ESTADO.md` es un snapshot fechado de lo *verificado*: **no se le toca nada hasta que A–B
existan**, porque su función es que nadie lo lea como promesa.

Lo que se hizo, en orden: `ESTADO.md` y `PLAN.md` con la prueba real de Gemini del 29 sep
(`bc42218`), y el mapeo del chat en `heuristics.md` con 13 decisiones trazadas a su archivo
—cada referencia comprobada contra el código, no de memoria—. El contrato del asistente ya
entró al CI verde con `36465285576`, así que `ci.yml` no necesitó cambios.

## 5. Trazabilidad

Cómo se cierra cada punto pendiente. La columna de la izquierda es el checklist de
entrega del plan de referencia de CanchaYa; la del medio, los huecos que el propio
`ESTADO.md` reconoce.

### Checklist de CanchaYa

| Ítem | Estado | Fase |
|---|---|---|
| 1. Login/registro JWT en los 3 roles | ya estaba | — |
| 2. Cliente reserva y paga de punta a punta | ya estaba (`PAGADORA=mock`) | — |
| 3. Dueño aislado por `dueno_id` | ya estaba | — |
| 4. Admin ve todo y cambia roles | ya estaba | — |
| 5. **Asistente IA con disponibilidad real** | **hecho** | A + B (28 sep) + prueba real (29 sep) |
| 6. APK instalable + build de iOS | **a medias** | **C₂** (Android) · **E** (iOS) |
| 7. Documentación con heurísticas por pantalla | **hecho** | F (29 sep, incluye el chat) |

El delta real contra aquel plan era el ítem 5, y se cerró con las fases A y B de este plan
(28 sep) más la prueba real contra Gemini (29 sep), documentada en `ESTADO.md`. De aquel
checklist queda **el ítem 6, y a medias**: el APK de release ya está construido y firmado
con la clave local (C₂, 29 sep por la noche), pero **instalarlo y verlo correr es fase D**,
y el build de iOS sigue siendo fase E sin empezar. De los siete, seis cerrados.

### Huecos de ESTADO.md

| Hueco | ¿Lo cierra este plan? |
|---|---|
| 1. Capturas de la app | **Sí** — fase D |
| 2. Stripe con claves reales | No — sin acceso a exponer el webhook |
| 3. Mensaje del `401` de cuenta desactivada | No — se documentó a propósito, corregirlo cambia el contrato |
| 4. El contrato real no corre en local | Parcialmente — la causa era RAM, y la fase D la resuelve |
| 5. El contrato se omite en silencio sin `GOALTIME_API_URL` | No — es deliberado, ya justificado |
| 6. Helpers de token duplicados en 4 tests | No — deuda de tests, no de funcionalidad |

Fuera del alcance de este plan: cancelación con regla de 24 h, recordatorios por email,
recuperación de contraseña y sesiones multi-dispositivo. Siguen listados en `spec.md` §6.

## 6. Fuera de alcance

Escrito de antemano para que no crezca solo:

- **Publicar en Play Store o App Store.** El APK va por sideload; no se paga ni un peso.
- **Reescribir `test/support/fake_api.dart`.** Se le añade el endpoint del asistente y
  nada más.
- **Refactor del `FakeApi` a generador de OpenAPI.** Sería lo correcto a futuro y es
  alcance nuevo.
- **Habilitar el target de escritorio de Linux** (`apt install cmake ninja-build
  pkg-config libsecret-1-dev`) para tener hot reload. Descartado: el chat es una lista y
  unos botones, los tests de widget ya lo cubren, y sumaría un tercer target que mantener.
- **Renombrar el proyecto a CanchaYa.** Aquel documento dice que el nombre es desechable;
  aquí el nombre es GoalTime y no hay razón para moverlo.

## 7. Cómo se ejecuta cada verificación

```sh
# Fases A y B: nada de esto necesita emulador
cd backend && . .venv/bin/activate && pytest -q
flutter analyze --fatal-infos
flutter test

# C₁ y C₂: con el emulador apagado y Ollama parado, por §3.1
flutter build apk --debug      # C₁
flutter build apk --release    # C₂

# El asistente con motor local, sin red y sin pagar
ollama pull qwen2.5:1.5b
LLM_PROVEEDOR=ollama OLLAMA_MODELO=qwen2.5:1.5b . .venv/bin/activate && flask --app app run

# D: emulador
emulator -avd cel_test -no-window -no-audio -no-boot-anim
adb install build/app/outputs/flutter-apk/app-release.apk
```

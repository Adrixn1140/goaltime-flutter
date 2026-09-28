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

**inferido.** `android/gradle.properties` trae el valor por defecto del template de Flutter:

```properties
org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m
```

Pide 8 GB de heap en una caja que tiene 3.7 GB. Sumado al daemon de Kotlin, que pide su
propia memoria, el build **no tiene cómo pasar**: el JVM crece hasta que el OOM-killer del
kernel lo mata, o entra en swap y se cuelga. El archivo **está versionado**, así que el
problema lo hereda cualquiera que clone el repo en una máquina modesta.

El arreglo es bajarlo a algo que quepa, del orden de `-Xmx1536m`:

```properties
org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=256m
```

**El arreglo se aplica en la fase C₁, no aquí.** Documentar el problema sí; tocar la
configuración sólo cuando se haya observado el fallo, para no escribir una evidencia que no
existe. Si el build pasa con 8 GB, esta sección se retira.

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

### Fase C₁ — Sondeo de build (**primero**)

Arreglar `org.gradle.jvmargs` y `flutter build apk --debug`, con el emulador apagado y
Ollama parado.

*Por qué va primero:* responde una sola pregunta binaria — ¿puede esta máquina producir un
APK? Si la respuesta es no, la fase D hay que replantearla entera, y conviene saberlo en
el minuto 20 y no después de tres días escribiendo backend. Se usa `--debug` porque es el
build más barato y comparte casi todo el compilado con el de `release`: si el debug pasa, la
RAM está probada. La caché de Gradle ya está caliente, así que no hay descargas grandes.

- [ ] `flutter build apk --debug` termina sin `OutOfMemoryError`
- [ ] Existe `build/app/outputs/flutter-apk/app-debug.apk`
- [ ] `android/gradle.properties` con la memoria ajustada, y nota en `ENTORNO.md` §20

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

- [ ] `pytest` verde con `LLM_PROVEEDOR=mock`, sin red
- [ ] `test_asistente.py`: la herramienta devuelve slots **reales** de la base, no un fixture
- [ ] `403` para `dueno` y `admin`; `401` sin token
- [ ] `calcular_slots` extraído y los 36 tests de disponibilidad siguen en verde

### Fase B — Asistente IA, app

`lib/features/asistente_ia/` con `data/`, `state/` y `presentation/`, cuarto
`NavigationDestination` en `cliente_shell.dart` y ruta `/cliente/asistente` en
`app_router.dart`. Toca `test/support/fake_api.dart`, que es donde vive la debilidad
documentada como decisión 6 en `ESTADO.md`: por eso el caso nuevo entra **también** en
`contrato_real_test.dart`, que es lo único que vigila que esa copia no se desincronice.

- [ ] `flutter test` verde y `flutter analyze --fatal-infos` sin issues
- [ ] `asistente_flow_test.dart`: mensaje → opciones → confirmar
- [ ] El caso de contrato entra en `contrato_real_test.dart` (sólo CI)

### Fase C₂ — APK de entrega

`flutter build apk --release` con un keystore local desechable. Es gratis y se instala por
sideload, sin cuenta de Google ni los USD 25 de Play Store. `**/*.jks` ya está en
`android/.gitignore`, así que la clave no se versiona. Ojo: **este** APK ya contiene el
asistente, a diferencia del de la C₁.

- [ ] `app-release.apk` instalado con `adb install`
- [ ] Login y un recorrido completo funcionando en el emulador

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

### Fase F — Documentación y CI

`heuristics.md` con el mapeo de la pantalla de chat, `ESTADO.md` actualizado al nuevo
estado, `README.md` con el checklist al día y `ci.yml` si el asistente entra al contrato.
`ESTADO.md` es un snapshot fechado de lo *verificado*: **no se le toca nada hasta que A–B
existan**, porque su función es que nadie lo lea como promesa.

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
| 5. **Asistente IA con disponibilidad real** | **pendiente** | **A + B** |
| 6. APK instalable + build de iOS | **pendiente** | **C₂** (Android) · **E** (iOS) |
| 7. Documentación con heurísticas por pantalla | parcial | F (el chat aún no existe) |

El delta real contra este repo es el ítem 5: no existe `blueprints/asistente.py` ni carpeta
`asistente_ia/` en `lib/features/`, y no hay una sola mención a Claude, Gemini, Anthropic ni
`llm` en todo el código. Las fases 3 y 7 de aquel plan están enteras sin hacer.

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

# Puesta en marcha en otro equipo

Guía para ejecutar GoalTime completo en una PC que no es donde se construyó. Está pensada
para llegar con la máquina vacía y no haber visto el proyecto antes. Al final de cada fase
hay una **verificación**: si pasa, esa fase está hecha. No sigas sin comprobar.

Tres documentos, tres responsabilidades distintas —no es lo mismo leerlos:

| Documento | Para qué |
|---|---|
| **Este** | Installar, levantar y comprobar. Empieza por aquí. |
| [`ENTORNO.md`](ENTORNO.md) | Referencia de versiones exactas y problemas. Consulta, no lectura lineal. |
| [`PRUEBA-EN-DISPOSITIVO.md`](PRUEBA-EN-DISPOSITIVO.md) | Por qué la prueba cuesta: los tres bloqueos que se hornean en el binario |

Las versiones que aparecen son las que el CI fija, así que otra versión no verifica lo
mismo. Si algo falla, mira el requisito de hardware más abajo antes de depurar.

---

## Fase 1 — Levantar el backend

### Requisitos

| | Mínimo | Recomendado |
|---|---|---|
| Núcleos | 2 | 4 o más |
| RAM | 8 GB | 16 GB |
| Disco libre | 20 GB | 50 GB |
| Aceleración | — | `/dev/kvm` en Linux, Hyper-V en Windows |

**Verificado el 1 de octubre de 2026**: con 2 núcleos y 3.7 GB de RAM la API y el emulador
no caben a la vez. El emulador pide **1536 MB por AVD** y sobre esa máquina ya había 1.7 GB
ocupados. Los 16 GB no son un lujo: sin ellos la Fase 2 no arranca, y además el contrato
real de la app no se puede ejecutar en local porque el kernel mata `flutter_tester`.

Comprueba la aceleración antes de nada — sin ella el emulador va por emulación de
software y es inservible:

```sh
ls -la /dev/kvm        # Linux: debe existir
```

En Windows es la Hyper-V activada; en macOS no aplica.

### 1. Herramientas base

```sh
sudo apt update
sudo apt install -y git curl unzip xz-utils zip libglu1-mesa \
    python3 python3-venv python3-pip postgresql-client
```

### 2. Flutter

El CI fija la versión exacta, así que se clona por git en esa revisión:

```sh
git clone https://github.com/flutter/flutter.git ~/flutter
git -C ~/flutter checkout 3.47.5
export PATH="$PATH:$HOME/flutter/bin"
```

En Windows va el zip de `storage.flutter-io.cn` o el paquete de la comunidad; en macOS,
`brew install --cask flutter`. Las secciones de `ENTORNO.md` §Instalar en Windows y
§Instalar en macOS tienen los pasos de esas plataformas, **inferidos**: no se ejecutaron
desde aquí.

### 3. Android SDK

```sh
sudo apt install -y sdkmanager avdmanager     # alternativa: Android Studio
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" \
    "emulator" "system-images;android-34;google_apis;x86_64" \
    "cmake;3.22.1"
sdkmanager --licenses    # debe terminar en "All Android SDK package licenses accepted."
```

> **Trampa 1 — `cmake;3.22.1` exacto, no el de tu distribución.** Sin él el build avanza
> por casi todas las tareas y **muere al final** con:
>
> ```
> > Task :app:configureCMakeDebug[arm64-v8a] FAILED
> > [CXX1300] CMake '3.22.1' was not found in SDK, PATH, or by cmake.dir property.
> ```
>
> La cadena que lo exige es `flutter_secure_storage` → `jni` → C++ nativo. `flutter doctor`
> lo presenta como requisito de escritorio y parece irrelevante si sólo quieres Android.
> Instalar el `cmake` del sistema **no basta**: AGP busca primero en el SDK y sólo acepta
> esa versión.

> **Trampa 2 — un solo `adb` en el PATH.** Si instalaste el SDK a mano y además está el de
> `/usr/lib/android-sdk`, `flutter doctor` avisa y **la detección de dispositivos se rompe**.
> Deja uno solo.

### 4. JDK 21

```sh
sudo apt install -y openjdk-21-jdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
```

Con Android Studio, el JDK va incluido: `flutter config --jdk-dir` apunta a él.

### 5. Variables de entorno

Lo exportado arriba caduca al cerrar la sesión. Para que sobreviva:

```sh
cat >> ~/.bashrc <<'EOF'
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH="$PATH:$HOME/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
EOF
```

### 6. Clonar el proyecto

```sh
git clone https://github.com/Adrixn1140/goaltime-flutter.git
cd goaltime-flutter
flutter pub get
```

### 7. Un solo comando levanta todo

```sh
tool/verificar_integracion.sh
```

**Verificado**: este script hace el ciclo completo —copia `.env` si falta, levanta el
compose, espera a que `/api/health` responda, siembra catálogos, usuarios, canchas y
horarios, y corre el contrato de la app contra el backend real. Si termina con

```
Contrato verificado contra el backend real.
```

**la Fase 1 está completa.** No hace falta `docker compose up` a mano.

Opciones: `--keep` deja los contenedores arriba, `--volumes` borra el volumen de Postgres y
arranca desde cero, que es la prueba de que migraciones y seed bastan para tener un sistema
funcionando.

#### Si prefieres hacerlo a mano

**Alternativa local sin Docker (Windows, Linux o macOS):** instala Python y las
dependencias de `backend/requirements.txt` en `backend/.venv`. Desde la raíz:

```powershell
backend\.venv\Scripts\python.exe tool\iniciar_demo.py
```

```sh
backend/.venv/bin/python tool/iniciar_demo.py
```

El arranque local prepara el esquema con Alembic y carga las cuentas de demostración
antes de servir la API. No borra datos. Solo para desarrollo; consulta
[`backend/README.md`](../backend/README.md) para instalación y producción.

**No copies el entorno virtual de otro equipo** ni `android/local.properties`:
contienen rutas locales. Recréalo e instala las herramientas en el computador destino.

```sh
cp .env.compose.example .env          # en la raíz, lo lee docker compose
cp backend/.env.example backend/.env  # lo lee Flask/Alembic/pytest
python3 -c "import secrets; print(secrets.token_hex(32))"   # pega esto en JWT_SECRET_KEY
```

> **La `JWT_SECRET_KEY` tiene que ser aleatoria.** El valor por defecto de la configuración
> está versionado, y con él **se puede firmar el token de cualquier rol, incluido admin**.
> Sin esta variable `docker compose up` se niega a arrancar.

> **Trampa 3 — el arranque es lento, y reiniciar el contenedor lo alarga.** En el equipo
> donde se construyó tardó **más de 13 minutos** y los contenedores pasaron por `unhealthy`
> todo ese rato: PostgreSQL reparaba un cierre sucio anterior y su `fsync` tardó 130
> segundos por el disco lento. **No mates los contenedores durante ese rato** — cada intento
> de reinicio encadena otra recuperación. Espera a que el healthcheck diga `healthy`.

```sh
docker compose ps          # ambos en "healthy"
curl http://127.0.0.1:5000/api/health
# {"estado":"ok","servicio":"goaltime-api","version":"1.0.0"}
```

Datos de prueba (contraseña `Goaltime123!`): `cliente@goaltime.test`, `dueno1@goaltime.test`,
`dueno2@goaltime.test`, `admin@goaltime.test`. Comprobar el login:

```sh
curl -X POST http://127.0.0.1:5000/api/login \
  -H "Content-Type: application/json" \
  -d '{"email":"cliente@goaltime.test","password":"Goaltime123!"}'
```

La ruta es `/api/login`, **no** `/api/auth/login`.

---

## Fase 2 — La app en el emulador

### 1. Crear el AVD

**El AVD no viaja con el repositorio.** Vive en `~/.android/avd/`, así que hay que crearlo
una vez por equipo aunque el SDK esté completo:

```sh
sdkmanager "system-images;android-34;google_apis;x86_64"
avdmanager create avd -n cel_test -k "system-images;android-34;google_apis;x86_64" -d pixel_6
emulator -list-avds            # debe mostrar cel_test
```

### 2. Arrancar

```sh
emulator -avd cel_test -no-window -no-audio -no-boot-anim &
adb wait-for-device
flutter devices                # debe listarlo como device
```

### 3. Correr la app

```sh
flutter run
```

**No lleva `--dart-define`, y no es descuido.** `http://10.0.2.2:5000` ya es el valor por
defecto (`lib/core/config/api_config.dart:15`), `10.0.2.2` es el alias que usa el emulador
para alcanzar al host, y `10.0.2.2` está en el allowlist de
`android/app/src/main/res/xml/network_security_config.xml`. Además el build de **debug**
trae el permiso `INTERNET` solo, así que aquí no se toca el manifiesto.

### 4. Recorrer los tres roles

Los recorridos completos están en el
[README](../README.md#recorrido-del-módulo-cliente) — `Cliente`, `Dueño` y `Admin`. Con
`PAGADORA=mock`, que es el default, el flujo de pago se recorre entero sin claves de
Stripe.

Nuevo avance: con rol cliente abre **Equipos**, crea uno y añade jugadores con datos
ficticios. Consulta [`EQUIPOS.md`](EQUIPOS.md) para el recorrido y las limitaciones.

### 5. Capturas

```sh
mkdir -p docs/capturas
adb exec-out screencap -p > docs/capturas/01-cliente-catalogo.png
```

`adb exec-out screencap -p` y no `adb shell screencap`: el segundo mete saltos de línea al
escribir a un archivo y produce un PNG corrupto. Nombres sugeridos:

```
01-cliente-catalogo.png        04-cliente-mis-reservas.png
02-cliente-disponibilidad.png  05-dueno-mis-canchas.png
03-cliente-pago.png            06-admin-usuarios.png
                               07-admin-reporte.png
```

`docs/capturas/` no está en `.gitignore`, así que se versionan bien.

### Verificación de la fase 2

- `flutter devices` lista el AVD como `device`.
- Los cuatro pasos de autenticación, catálogo, reserva con pago y panel de admin se ven en
  pantalla, en ese orden.
- Existen las capturas en `docs/capturas/`.

---

## Fase 3 — APK de entrega

Sólo si necesitas el binario. Para probar la app, la Fase 2 basta.

### 1. Compilar

```sh
flutter build apk --release
```

El build de debug tarda minutos en un equipo decente. El de release con las tres ABIs es
más pesado: **49 minutos** en el equipo de 2 núcleos y 3.7 GB que construyó el primero.

### 2. Verificar el binario

```sh
# permiso de red: debe aparecer INTERNET
aapt2 dump xmltree --file AndroidManifest.xml \
  build/app/outputs/flutter-apk/app-release.apk | grep -A3 uses-permission

# firma
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

**Verificado el 1 de octubre de 2026** que el permiso y la firma están, pero que **faltaban
en el APK del 29 de septiembre**: `flutter build apk --release` no declara `android.permission.INTERNET`
—Flutter lo añade sólo en debug y profile—, así que ese APK no podía hacer una sola llamada
de red. Está corregido y versionado. La explicación completa, con el dato de por qué, está
en [`PRUEBA-EN-DISPOSITIVO.md`](PRUEBA-EN-DISPOSITIVO.md#1-el-apk-de-release-no-trae-permiso-internet).

La firma de release cae a la de debug si no existe `android/key.properties`, que **no se
versiona**. Así un repo recién clonado construye sin pasos extra.

### 3. Instalar en un teléfono

Sólo aquí se necesita un teléfono. Va en
[`PRUEBA-EN-DISPOSITIVO.md`](PRUEBA-EN-DISPOSITIVO.md#pista-a--telefono-android-fisico),
con el diagnóstico de "no carga datos" en cinco pasos.

### Verificación de la fase 3

Las dos comprobaciones del binario en verde. El `adb install` sólo si hay teléfono.

---

## Fase 4 — Las pruebas

Ninguna de estas es obligatoria para usar la app, y todas menos una corren sin red.

```sh
flutter analyze                       # sin issues
flutter test                          # 105 pruebas
cd backend && . .venv/bin/activate && pytest -q    # 322 pruebas
```

Para el backend sin Docker, sobre SQLite:

```sh
cd backend && python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
alembic upgrade head
flask seed-catalogo
flask seed
pytest -q
```

### El contrato real

```sh
GOALTIME_API_URL=http://127.0.0.1:5000 flutter test test/contrato_real_test.dart
```

> **Un test verde no siempre es un test que comprobó algo.** Sin `GOALTIME_API_URL` los tests
> del contrato aparecen como `skipped` y la suite sigue verde. Es deliberado —la suite por
> defecto no habla con la red— pero conviene saberlo antes de leer un verde como una
> verificación. El workflow del CI pasa la variable explícitamente en el único job que debe
> hablar con la API.

Éste es el test que **no se puede ejecutar en un equipo con menos de 8 GB**: el kernel mata
`flutter_tester` y `flutter_tools` reporta `did not complete`. Con los 16 GB recomendados
sale, y es una de las razones por las que esta guía pide esa cifra.

---

## El asistente IA

Por defecto `LLM_PROVEEDOR=mock`: el circuito se ejercita entero **sin red y sin pagar**, y
los `horario_id` de las sugerencias salen de la base de datos, no del modelo.

Con motor local, en un equipo con RAM de sobra:

```sh
ollama pull qwen2.5:1.5b
LLM_PROVEEDOR=ollama OLLAMA_MODELO=qwen2.5:1.5b docker compose up -d
```

Con Gemini hace falta la llave **del backend**, nunca en la app: se pone en `backend/.env`
como `GEMINI_API_KEY`, y `.env` está en `.gitignore`.

---

## Cuando algo falla

Ordenados por probabilidad, con lo que se sabe que pasó de verdad:

1. **`Failed connecting to the daemon in 4 retries`** — Gradle lanza un daemon de Kotlin
   aparte y los dos JVM no caben. El repo ya lo corrige con
   `kotlin.compiler.execution.strategy=in-process` en `android/gradle.properties`; si
   reaparece, revisa que ese archivo tenga esa línea.
2. **`CMake '3.22.1' was not found`** — trampa 1 de la Fase 1.
3. **El build se cuelga en `dl.google.com` sin fallar** — con la caché de Gradle
   incompleta, Gradle espera conexiones que no avanzan ni dan error: puede pasar 40
   minutos escribiendo `Running Gradle task 'assembleDebug'...`. Se reconoce mirando si el
   proceso consume CPU. Se resuelve con `--offline`, que es legítimo porque todo lo
   necesario ya está en la caché.
4. **La API muere al arrancar contra PostgreSQL** — el healthcheck consulta antes de que el
   esquema esté listo; es una condición de carrera conocida.
5. **`OutOfMemoryError` en el build** — `android/gradle.properties` ya viene con el heap
   ajustado a `-Xmx1536m` para equipos modestos.
6. **La app carga pero no muestra datos** — eso no es del emulador. Casi siempre es la URL
   horneada o el allowlist; [`PRUEBA-EN-DISPOSITIVO.md`](PRUEBA-EN-DISPOSITIVO.md) tiene el
   diagnóstico paso a paso.

La lista completa, con la evidencia de cada caso, está en
[`ENTORNO.md`](ENTORNO.md#problemas-que-ya-ocurrieron-de-verdad).

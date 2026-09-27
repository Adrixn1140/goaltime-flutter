# Entorno y puesta en marcha en otro equipo

Este documento es para instalar GoalTime **en un equipo que no es este** y poder
ejecutarlo y probarlo de punta a punta. El contrato del sistema está en
[`spec.md`](spec.md) y el estado de qué está comprobado, en [`ESTADO.md`](ESTADO.md);
aquí no se repite ninguno de los dos.

Cada bloque va marcado con su grado de confianza:

- **Verificado**: se ejecutó en el equipo donde se escribió esto (Linux/Kali, 2 núcleos y
  3.7 GB de RAM) y dio el resultado que se dice.
- **Inferido**: el comando es el que corresponde por versión y plataforma, pero **no se
  ejecutó aquí**. En Windows y macOS casi todo lo de esas secciones es inferido.

Lo que aquí no se cubre: capturas de la app, despliegue en producción y el camino de
Stripe con claves reales. Las capturas siguen abiertas y están anotadas en
[`ESTADO.md`](ESTADO.md#huecos-conocidos); para lo segundo,
[`spec.md` §3.3](spec.md#33-pago-stripe--modo-test-en-desarrollo).

## Requisitos de hardware

Este equipo tiene 2 núcleos, 3.7 GB de RAM y 3.7 GB de swap, y con eso funciona todo
**excepto el contrato real de la app**, que muere por falta de memoria: el kernel mata
`flutter_tester` y `flutter_tools` reporta `did not complete`. Ese es el motivo real de
que esa prueba sólo corra en CI.

| | Mínimo | Recomendado |
|---|---|---|
| Núcleos | 2 | 4 o más |
| RAM | 8 GB | 16 GB |
| Disco libre | 20 GB | 50 GB |
| Aceleración | — | `/dev/kvm` en Linux, Hyper-V en Windows |

Los 8 GB son el mínimo porque el emulador de Android pide 1536 MB de RAM por AVD y
Docker levanta PostgreSQL y la API al mismo tiempo. Con 16 GB se puede correr el
emulador, la API y el contrato real a la vez, que es la diferencia entre probar y
verificar.

## Versiones, y por qué importan

Todas verificadas en este equipo el 26 de septiembre de 2026.

| Herramienta | Versión aquí | Por qué importa |
|---|---|---|
| Flutter | 3.47.5 stable, rev `6a19cca564` | El CI la fija exacta, así que otra versión no verifica lo mismo |
| Dart | 3.13.4 | `pubspec.yaml` exige `sdk: ^3.13.4` |
| Python | 3.14.6 en el venv | El CI fija **3.12**. Los dos pasan las 278; ver la nota de abajo |
| Docker | 29.3.0, Compose v5.1.0 | Es `docker compose`, no el `docker-compose` de antes |
| PostgreSQL | `postgres:16-alpine` en compose | El que manda es el del contenedor; el cliente local es 18.3 |
| Android SDK | 36.0.0; platforms 34, 35 y 36 | `compileSdk` lo toma de Flutter, no de aquí |
| Build-tools | 36.0.0 | La que reporta `flutter doctor` en este equipo |
| Emulador | 37.1.11.0 | Corre el AVD, no la app de escritorio |
| System image | `android-34;google_apis;x86_64` | La que usa el AVD de este equipo |
| NDK | 28.2.13676358 | También lo toma Flutter por `flutter.ndkVersion` |
| JDK | Temurin 21.0.12.1 | La que usa Flutter aquí; se cambia con `flutter config --jdk-dir` |
| Gradle | wrapper 9.3.1-`all` | El wrapper lo descarga: no hay que instalarlo |
| AGP / Kotlin | 9.1.0 / 2.4.0 | Los declara `android/settings.gradle.kts` |

**Sobre la versión de Python.** El venv de este equipo es 3.14.6 y la suite completa
pasa las 278 pruebas. El CI usa 3.12 y también las pasa. Para un equipo nuevo, **3.12**
es la apuesta más segura: es la que verifica el CI en cada push, así que si algo se rompe
por versión se rompe en el CI primero y no en tu máquina. `psycopg[binary]` trae su
propio binario, así que no hace falta compilar nada.

## Instalar en Linux (Debian, Ubuntu, Kali)

**Verificado** en Kali, con una diferencia que se detalla al final.

```sh
# Sistema
sudo apt update
sudo apt install -y git curl unzip xz-utils zip libglu1-mesa \
    python3 python3-venv python3-pip postgresql-client

# Flutter, por git, que es como está aquí
git clone https://github.com/flutter/flutter.git ~/flutter
git -C ~/flutter checkout 3.47.5

# Android: SDK, emulador e imagen de sistema
sudo apt install -y sdkmanager avdmanager   # alternativa: Android Studio
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" \
    "emulator" "system-images;android-34;google_apis;x86_64"
sdkmanager --licenses    # tiene que terminar en "All Android SDK package licenses accepted."

# JDK 21
sudo apt install -y openjdk-21-jdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

# Docker
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"    # cierra sesión y vuelve a entrar
```

Las cuatro líneas de `export` van en `~/.bashrc` o `~/.zshrc`; sin ellas, `flutter` no
se encuentra. Este equipo tiene además dos espejos de China en el shell
(`PUB_HOSTED_URL` y `FLUTTER_STORAGE_BASE_URL` apuntando a `flutter-io.cn`): sólo hacen
falta si tu red no alcanza `pub.dev`, y en ese caso hay que ponerlos también.

**Verificar** antes de seguir:

```sh
flutter doctor -v
```

Aquí da verde en Flutter y en el Android toolchain, y dos avisos que son el estado
normal de un equipo sin navegador ni toolchain de escritorio: *Chrome* no encontrado y
*Linux toolchain* incompleto por `cmake`, `ninja` y `pkg-config`. Si te importa compilar
para escritorio, instálalos:

```sh
sudo apt install -y cmake ninja-build pkg-config clang libgtk-3-dev liblzma-dev
```

**Las diferencias de Kali**: el repositorio de Docker que se usa arriba es el de Debian.
Kali deriva de Debian y el mismo script funciona, pero si falla con un error de
repositorio, el camino más corto es usar el de la documentación de Kali para el
contenedor de Docker. `postgresql-client` en Kali puede traer la 18, que es lo que hay
aquí: sólo se usa para `createdb` contra el contenedor, así que la diferencia no afecta.

### Si prefieres Android Studio

Instalarlo trae el SDK, el emulador y el AVD Manager, y es más cómodo para crear
dispositivos virtuales. Lo que importa después es que `ANDROID_HOME` apunte al mismo
directorio y que el JDK que use sea el 21:

```sh
flutter config --jdk-dir=/ruta/al/jdk21
```

## Instalar en Windows

**Inferido.** No se ejecutó aquí. Todo lo de esta sección necesita una terminal PowerShell
*como administrador* para el SDK y Docker.

```powershell
# Herramientas base
winget install Git.Git
winget install Python.Python.3.12
winget install Google.AndroidStudio
winget install Docker.DockerDesktop

# Flutter: el paquete oficial de la comunidad, o el zip de storage.flutter-io.cn
winget install --id=Flutter -e
```

Después, en *Android Studio* se acepta el SDK y se instalan `platforms;android-36`,
`build-tools;36.0.0`, `emulator` y `system-images;android-34;google_apis;x86_64`, y se
aceptan las licencias. Flutter se comprueba con `flutter doctor -v`.

Docker Desktop necesita WSL2 activado, y conviene activar en *Settings → Resources →
WSL Integration* la integración con la distribución que uses. Hay que reiniciar el
equipo al menos una vez entre activarlo y levantar Docker.

El backend tiene dos caminos y **ambos funcionan en Windows**:

- **Con Docker Desktop**, que es lo más parejo a como se verificó aquí: el mismo
  `docker compose up -d --build` del apartado siguiente, sin más cambios.
- **Con Python nativo**, usando PowerShell en vez de `sh`. Donde el guía dice `export`,
  aquí es `$env:NOMBRE = "valor"`, y donde dice `source .venv/bin/activate`, aquí es
  `.venv\Scripts\Activate.ps1`. Si PowerShell bloquea la activación por política de
  ejecución, `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` lo resuelve.

Para crear la base de los tests **no hace falta instalar `psql`**: el contenedor de
PostgreSQL ya lo trae, y así se verificó en este equipo.

```powershell
docker compose exec db createdb -U goaltime -h 127.0.0.1 goaltime_test
```

## Instalar en macOS

**Inferido.** No se ejecutó aquí. Xcode sí es necesario: **iOS no se compila fuera de
macOS**, así que si el objetivo incluye iOS, macOS es el único camino.

```sh
xcode-select --install                 # herramientas de línea de comandos de Apple
sudo xcodebuild -runFirstLaunch        # las acepta
brew install --cask flutter
brew install python@3.12
brew install --cask docker              # Docker Desktop
brew install --cask android-commandlinetools
```

Android Studio también por `brew install --cask android-studio` si se quiere el AVD
Manager. El JDK va incluido en Android Studio, pero `flutter config --jdk-dir` apunta
Flutter al que se use.

## Qué no hay que instalar a mano

Las dependencias de Python y de Dart ya están declaradas y se resuelven solas. Instalar
una a mano sólo introduce la posibilidad de que la versión no sea la que el CI verifica.

```sh
# Python: 10 paquetes con versión fijada
cd backend && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt

# Dart: 8 dependencias de runtime y 2 de desarrollo
flutter pub get
```

`pip install -r requirements.txt` instala las diez, y no hay que quitar ninguna. Sólo
importa saber cuál hace falta para qué: `stripe` no se importa mientras `PAGADORA=mock`,
así que el camino de desarrollo no lo toca; y `psycopg` sólo se usa si `DATABASE_URL` es
una URL de PostgreSQL, que es justo lo que hace falta para correr la suite de verdad y lo
que usa el contenedor en producción.

## Levantar el backend

Hay dos modos y ninguno es el "bueno": el primero es rápido, el segundo es el que se
parece a producción y el único donde se puede correr la suite contra PostgreSQL.

### Opción A: venv y SQLite

**Verificado.**

```sh
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
python -c "import secrets; print(secrets.token_hex(32))"   # -> JWT_SECRET_KEY

alembic upgrade head    # crea el esquema
flask seed-catalogo     # catálogos de la tabla maestra
flask seed              # usuarios, canchas y horarios de prueba; idempotente

flask --app app run --host=0.0.0.0 --port=5000
```

Comprobar: `curl http://127.0.0.1:5000/api/health` responde
`{"estado":"ok","servicio":"goaltime-api","version":"1.0.0"}`.

El `--host=0.0.0.0` es obligatorio para que un teléfono real alcance el servidor. Desde
el emulador de Android, `127.0.0.1` alcanza la máquina anfitriona, así que ahí no hace
falta.

### Opción B: Docker y PostgreSQL

**Verificado**, y es lo que usa el contrato real y el job de integración del CI.

```sh
# En la raíz del repositorio, no en backend/
cp .env.compose.example .env
# .env exige JWT_SECRET_KEY: sin ella `docker compose up` se niega a arrancar.
python3 -c "import secrets; print(secrets.token_hex(32))"

docker compose up -d --build
curl http://127.0.0.1:5000/api/health
```

PostgreSQL queda en `127.0.0.1:5433`, no en 5432, para no chocar con un PostgreSQL local.
PostgreSQL y la API llevan *healthcheck*, y la API espera a que la base esté sana, así que
el orden no hay que controlarlo a mano.

## Levantar la app

El repositorio scaffoldea **sólo `android/` e `ios/`**. No hay carpeta `web/`, ni
`linux/`, ni `macos/`, ni `windows/`, así que `flutter run -d chrome` o `-d linux` no
tienen contra qué arrancar aunque `flutter doctor` los liste como dispositivos
disponibles. Para web habría que añadir la plataforma con `flutter create --platforms=web .`
y eso cambia el proyecto, así que no se hizo.

El backend se elige en build, no en el código:

```sh
flutter run                                                  # emulador: 10.0.2.2:5000
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:5000   # teléfono real
```

`10.0.2.2` es el alias con el que el emulador alcanza al `localhost` de la máquina. Es el
valor por defecto de `ApiConfig.baseUrl`, y se cambia con `--dart-define`, que es la
única variable de la app.

### Emulador de Android

Aquí ya existe un dispositivo virtual, `cel_test`, así que sólo hay que arrancarlo:

```sh
emulator -list-avds            # debería mostrar cel_test
emulator -avd cel_test &       # o "flutter emulators" y "flutter emulators --launch cel_test"
adb wait-for-device
flutter devices                # debe listarlo como device
```

**Verificado**: el AVD existe, la imagen de sistema está instalada y `/dev/kvm` está
presente, que es lo que habilita la aceleración por hardware. **No verificado**: que el
emulador llegara a completarlo, porque nunca se arrancó en este equipo. Con 3.7 GB de RAM
conviene subirlos a 16 GB antes de intentarlo.

Para crear un AVD nuevo, que es lo que haría falta en otro equipo:

```sh
sdkmanager "system-images;android-34;google_apis;x86_64"
avdmanager create avd -n nombre -k "system-images;android-34;google_apis;x86_64" -d pixel_6
```

### Teléfono Android físico

Es la vía que produce las capturas que quedaron pendientes, y la de las pruebas reales
sobre el hardware de verdad. Requiere tres cosas: habilitar *Opciones de desarrollador* y
*Depuración USB* en el teléfono, y que el backend escuche en `0.0.0.0`. Después,
`flutter devices` lo ve por USB y se lanza con la IP del equipo en el LAN:

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.18.21:5000
```

`192.168.18.21` hay que cambiarlo por la IP real del equipo. Está en
`ip addr | grep 'inet '` en Linux, `ipconfig` en Windows y `ipconfig getifaddr en0` en
macOS. El teléfono y el equipo tienen que estar en la misma red, y algunos routers
aislan el tráfico entre clientes: si la app no conecta, es lo primero que hay que
descartar.

## Correr las verificaciones

```sh
# Backend sobre SQLite: rápido, sin infraestructura
cd backend && . .venv/bin/activate && pytest -q

# El mismo backend contra PostgreSQL, que es donde están los tipos que SQLite no aplica
createdb -h 127.0.0.1 -U goaltime goaltime_test
TEST_DATABASE_URL=postgresql+psycopg://goaltime:goaltime-local@127.0.0.1:5433/goaltime_test pytest -q

# El guardián anti-drift: falla si un modelo cambió sin migración
DATABASE_URL=postgresql+psycopg://goaltime:goaltime-local@127.0.0.1:5433/goaltime alembic check

# App
flutter analyze --fatal-infos
flutter test
```

Y el contrato de la app contra el backend de verdad, que es lo único que no se puede
ejecutar en este equipo por la memoria:

```sh
tool/verificar_integracion.sh
```

El script levanta el stack, espera `/api/health`, siembra con `flask seed` y corre los 9
tests del contrato. Con `--keep` deja los contenedores arriba y con `--volumes` borra
también el volumen de PostgreSQL, que es la prueba de que `alembic upgrade head` y los
seeds bastan para tener un sistema funcionando desde cero.

Sin `GOALTIME_API_URL`, los 9 tests del contrato se **omiten en silencio** y la suite
sigue verde. Para correrlos a mano contra la API del modo B:

```sh
GOALTIME_API_URL=http://127.0.0.1:5000 flutter test test/contrato_real_test.dart
```

## Variables de entorno

Hay dos plantillas y no son intercambiables, porque las lee cada una en un sitio
distinto:

| Plantilla | Copiar en | La lee |
|---|---|---|
| `backend/.env.example` | `backend/.env` | Flask, Alembic y `pytest` |
| `.env.compose.example` | `.env`, en la raíz | `docker compose` |

Las dos piden `JWT_SECRET_KEY`, y tiene que ser aleatoria: el valor por defecto de la
configuración está en el repositorio, y con él se puede firmar el token de cualquier
rol, incluido admin. Generarla con
`python -c "import secrets; print(secrets.token_hex(32))"`.

`.env` está en `.gitignore` y no debe versionarse nunca. Para las claves de Stripe, en
`.env.example` está el procedimiento: salen del panel de pruebas de Stripe y el secreto
del webhook, de `stripe listen --forward-to localhost:5000/api/pagos/webhook`.

## Problemas que ya ocurrieron de verdad

No son hipótesis: pasó cada una de estas durante el trabajo.

1. **Dos `adb` en el mismo equipo.** `flutter doctor` avisa que hay un `adb` en el SDK y
   otro en `/usr/lib/android-sdk`, y que eso rompe la detección de dispositivos. Se
   resuelve dejando uno solo en el `PATH`, y conviene quitar el que venga con el sistema
   si instalaste el SDK a mano.
2. **La API muere al arrancar contra PostgreSQL.** Pasa si el *healthcheck* consulta el
   socket unix en vez de TCP: durante el arranque PostgreSQL levanta un servidor
   temporal que sólo escucha ahí, el *healthcheck* da "ok" antes de que exista un
   listener TCP, y el contenedor de la API muere con *connection refused*. Ya está
   corregido en `docker-compose.yml` con `pg_isready -h 127.0.0.1`.
3. **`createdb` antes de la suite contra PostgreSQL.** La fixture borra el esquema entre
   tests, y por eso la base de los tests es aparte. Sin crearla, la suite no arranca.
4. **El contrato real muere por memoria** con 3.7 GB de RAM. El síntoma es un fallo sin
   mensaje útil: `flutter_tools` dice `did not complete` y el kernel mata el proceso.
   Con 16 GB funciona; mientras tanto, en CI.
5. **Un `401` que no es un `401`.** La app responde siempre *"Vuelve a iniciar sesión."*
   ante cualquier `401`, pero una cuenta desactivada contesta `403` al volver a
   iniciar sesión, así que el consejo no lleva a ninguna parte. Está anotado en
   [`ESTADO.md`](ESTADO.md#huecos-conocidos) como hueco conocido.
6. **El orden de las listas cambia con la configuración regional.** Con el locale de
   español, `"Zuleima"` se ordena después de `"ana"` en PostgreSQL, y en SQLite no. La
   base se inicializa con `LC_COLLATE=C` por eso, y si se crea a mano sin eso, el orden
   de los catálogos no coincide con el que verifica el CI.

## Qué de este documento no está verificado

Para que nadie confunde una instrucción con una comprobación:

- **Windows y macOS**: ninguna instrucción de sus secciones se ejecutó. La versión de
  los comandos de PowerShell, la ruta del JDK y la activación de WSL2 son las que
  corresponde por versión, y hay que ajustarlas a la máquina.
- **El arranque del emulador**: el AVD, la imagen de sistema y `/dev/kvm` están
  verificados uno por uno, pero nunca se arrancó el emulador completo. El arranque en
  un equipo con 3.7 GB de RAM es lo menos probado de este documento.
- **iOS**: no se compiló para iOS, y `flutter build ios` necesita macOS con Xcode. Los
  archivos de `ios/` están en el repositorio, pero eso es todo lo que se puede afirmar
  desde aquí.
- **El escritorio de Linux**: `flutter doctor` marca el *toolchain* incompleto por falta
  de `cmake`, `ninja` y `pkg-config`, así que compilar para escritorio no se probó. Sin
  embargo, no hay carpeta `linux/`, con lo que la app no se puede ejecutar ahí
  igualmente.
- **El camino de Stripe con claves reales**: lo verificado es el de `PAGADORA=mock`. La
  CLI de Stripe no está instalada en este equipo, y `ngrok` sí, en
  `/usr/local/bin/ngrok`, pero sin probar.

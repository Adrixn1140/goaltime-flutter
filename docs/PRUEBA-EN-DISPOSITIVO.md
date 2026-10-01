# Probar GoalTime en un teléfono real y en el emulador

Este documento es el paso a paso para ejecutar la app en hardware y para cerrar las
capturas. Complementa a [`ENTORNO.md`](ENTORNO.md), que instala el toolchain; aquí sólo
está lo que pasa **después** de tener Flutter y el SDK instalados.

Hay dos pistas y son independientes entre sí, de modo que cada equipo necesita sólo la
suya:

| Pista | Dónde | Qué necesita | Qué demuestra |
|---|---|---|---|
| **A — Teléfono físico** | el equipo donde esté el cable | 8 GB de RAM, un teléfono, un cable | la app en hardware real, que es el entregable |
| **B — Emulador** | un equipo con 16 GB de RAM | AVD propio, Docker | que el circuito funciona sin hardware, y el contrato real de la app |

Cada bloque va marcado con su grado de confianza, igual que en `ENTORNO.md`:

- **Verificado**: se ejecutó y dio el resultado que se dice.
- **Inferido**: el comando es el que corresponde por versión y plataforma, pero no se
  ejecutó aquí.

---

## Los tres bloqueos que hacen perder una tarde

Léelos antes de compilar nada. Los tres son reales, los tres seestringido en el binario, y
ninguno se ve leyendo el código Dart.

### 1. El APK de release no trae permiso `INTERNET`

**Verificado el 1 de octubre de 2026.** Flutter declara `android.permission.INTERNET` por
su cuenta **sólo en las variantes debug y profile**. La de release se arma con el
`AndroidManifest.xml` del proyecto y nada más, así que sale sin ese permiso:

```sh
aapt2 dump xmltree --file AndroidManifest.xml \
  build/app/outputs/flutter-apk/app-release.apk | grep -A3 uses-permission
```

El APK del 29 de septiembre devolvía un único permiso, el
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` que genera una librería. **Sin `INTERNET` la
app no puede hacer una sola llamada de red** — ni al backend, ni a nada. No falla con un
error legible: falla con un `SocketException` genérico que no señala el motivo.

Por eso `android/app/src/main/AndroidManifest.xml` declara el permiso explícitamente, y ese
cambio **está versionado**. Un clon del repo lo trae.

> **Por qué el APK de debug sí funcionaba y el de release no.** La diferencia no está en el
> código Dart sino en el manifiesto que se fusiona en cada variante. Es el tipo de
> diferencia que hace que "construir" y "probable" sean dos cosas distintas.

### 2. La URL del backend se hornea en el binario

`lib/core/config/api_config.dart:13` lee `API_BASE_URL` con `String.fromEnvironment`, que se
resuelve **en tiempo de compilación**:

```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:5000',
);
```

El valor por defecto es `10.0.2.2`, que es el alias que usa el emulador para alcanzar al
host. **Un APK tiene una sola URL y no se puede cambiar sin recompilar.** Para un teléfono
hay que compilar con la IP del equipo:

```sh
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.18.23:5000
```

Y se comprueba lo que quedó dentro:

```sh
unzip -p build/app/outputs/flutter-apk/app-release.apk lib/arm64-v8a/libapp.so \
  > /tmp/libapp.so && strings /tmp/libapp.so | grep -E '^http://[0-9.]+:5000'
```

Si sale `10.0.2.2` en un teléfono físico, el APK no sirve para esa prueba y hay que
recompilarlo. No hay forma de corregirlo desde el teléfono.

### 3. Android 9+ bloquea el HTTP plano, y la lista de hosts es explícita

La API de desarrollo corre en HTTP, no en HTTPS. Desde Android 9 (API 28) el tráfico en
claro está bloqueado salvo que se diga lo contrario, y aquí se dice con
`android/app/src/main/res/xml/network_security_config.xml`:

```xml
<base-config cleartextTrafficPermitted="false" />
<domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">10.0.2.2</domain>
    <domain includeSubdomains="false">localhost</domain>
    <domain includeSubdomains="false">127.0.0.1</domain>
    <domain includeSubdomains="false">192.168.18.23</domain>
</domain-config>
```

Dos cosas que se ven ahí y que hay que entender:

- **La lista es explícita y el backend tiene que estar en ella.** Si la IP del equipo no
  está, la conexión se corta aunque todo lo demás esté bien. La última entrada es la IP
  del equipo donde se compila: **cámbiala por la tuya antes de compilar.**
- **`base-config` está en `false` a propósito.** Un APK que permite HTTP plano a cualquier
  host no debería entregarse. La alternativa de abrirlo todo (`cleartextTrafficPermitted=
  "true"`) se Discussió y se descartó: para una demo en LAN cerrada es tentador, pero
  rompe la garantía de que producción va por HTTPS.

> **El archivo XML y el manifiesto tienen que versionarse juntos.** El manifiesto lo
> referencia con `android:networkSecurityConfig`. Si sube el manifiesto sin el XML, el
> build de cualquiera que clone el repo falla al resolver el recurso. Es el error más
> fácil de cometer de este documento.

### La IP cambia por DHCP

La IP del equipo en el LAN no es fija, y el APK la lleva horneada. Si el router reasigna
la dirección, el APK deja de conectar **sin ningún aviso**: la app simplemente no carga
datos.

**Decisión tomada: reservar la IP por DHCP en el router.** Es lo que hace estable el allowlist
estricto sin abrirlo. Si no se puede tocar el router, la alternativa es reconstruir el
APK el mismo día de la entrega con la IP que toque en ese momento:

```sh
ip -4 -brief addr | grep -v LOOPBACK    # la IP real, en Linux
```

En Windows `ipconfig`, en macOS `ipconfig getifaddr en0`.

---

## Pista A — Teléfono Android físico

### Requisitos

- Un teléfono con *Opciones de desarrollador* → *Depuración USB* activadas.
- El teléfono y el equipo **en la misma red WiFi**. Algunos routers aíslan el tráfico
  entre clientes; si la app no conecta, esto es lo primero que hay que descartar.
- El backend escuchando en `0.0.0.0`, no en `127.0.0.1` — ver más abajo.

### 1. Backend en `0.0.0.0`

```sh
cp .env.compose.example .env
# .env exige JWT_SECRET_KEY: sin ella `docker compose up` se niega a arrancar.
python3 -c "import secrets; print(secrets.token_hex(32))"

docker compose up -d --build
curl http://127.0.0.1:5000/api/health
```

PostgreSQL queda en `127.0.0.1:5433`, no en 5432, para no chocar con un PostgreSQL local.
PostgreSQL y la API llevan *healthcheck*, y la API espera a que la base esté sana.

**Lo que hay que comprobar no es el `curl` a `127.0.0.1`, sino el que simula al teléfono:**

```sh
curl http://192.168.18.23:5000/api/health
# {"estado":"ok","servicio":"goaltime-api","version":"1.0.0"}
```

Si ese `curl` falla desde el propio equipo, el teléfono tampoco va a poder conectar, y
no tiene nada que ver con Android.

> **Verificado el 1 de octubre de 2026, y una advertencia útil.** En este equipo el
> arranque tardó **más de 13 minutos** y los contenedores pasaron por `unhealthy` durante
> todo ese rato: PostgreSQL estaba reparando un cierre sucio anterior (`database system was
> not properly shut down; automatic recovery in progress`) y su *fsync* tardó **130
> segundos** por el disco lento. **No mates los contenedores durante ese rato**: cada
> intento de reinicio encadena otra recuperación y lo alarga. Espera a que el *healthcheck*
> diga `healthy`, que es la única señal fiable.

### 2. Datos de prueba

```sh
docker compose exec api python -m seed
```

Es **idempotente**: se puede correr las veces que haga falta sin duplicar nada. Deja
cuatro cuentas con la contraseña `Goaltime123!`:

| Correo | Rol |
|---|---|
| `cliente@goaltime.test` | Cliente |
| `dueno1@goaltime.test` | Dueño |
| `dueno2@goaltime.test` | Dueño |
| `admin@goaltime.test` | Admin |

Comprobar que el login responde, antes de culpar al teléfono:

```sh
curl -X POST http://127.0.0.1:5000/api/login \
  -H "Content-Type: application/json" \
  -d '{"email":"cliente@goaltime.test","password":"Goaltime123!"}'
```

La ruta es `/api/login`, **no** `/api/auth/login`: el blueprint se registra con
`url_prefix="/api"` y las rutas dentro son `/login` y `/register`
(`backend/app.py:46`, `backend/blueprints/auth.py:41`).

### 3. Conectar el teléfono

```sh
adb devices -l      # debe listarlo como device, no como unauthorized
flutter devices
```

`unauthorized` significa que falta aceptar el diálogo de depuración en la pantalla del
teléfono. Si no aparece, cable de datos que cargue, no sólo un cable de carga.

### 4. Compilar con la IP correcta

Añade la IP de tu equipo al allowlist de
`android/app/src/main/res/xml/network_security_config.xml` **y** compila con la misma IP:

```sh
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.18.23:5000
```

El build tardó **31 minutos** en este equipo de 2 núcleos y 3.7 GB de RAM; en una máquina
de 8 GB o más son minutos ([`ENTORNO.md`](ENTORNO.md#el-requisito-que-no-está-en-la-tabla-orggradlejvmargs)).
Para iterar rápido es mejor `flutter run`, que además instala y hot-reloada.

### 5. Instalar y verificar

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Antes de declarar que se probó, comprueba el binario — es lo que distingue "instalado" de
"funcionando":

```sh
# permiso de red, presente
aapt2 dump xmltree --file AndroidManifest.xml \
  build/app/outputs/flutter-apk/app-release.apk | grep -A3 "uses-permission" \
  | grep "name(0x01010003)"

# URL horneada, la del LAN y no 10.0.2.2
unzip -p build/app/outputs/flutter-apk/app-release.apk lib/arm64-v8a/libapp.so \
  > /tmp/libapp.so && strings /tmp/libapp.so | grep -E '^http://[0-9.]+:5000'

# firma
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

### 6. Capturas

```sh
mkdir -p docs/capturas
adb exec-out screencap -p > docs/capturas/01-cliente-catalogo.png
```

`adb exec-out screencap -p` es el camino correcto: `adb shell screencap` mete saltos de
línea al escribir a un archivo y produce un PNG corrupto. Los nombres siguen el recorrido,
por rol:

```
01-cliente-catalogo.png        04-cliente-mis-reservas.png
02-cliente-disponibilidad.png  05-dueno-mis-canchas.png
03-cliente-pago.png            06-admin-usuarios.png
                               07-admin-reporte.png
```

Los tres recorridos completos están en el
[README](../README.md#recorrido-del-módulo-cliente) (`Cliente`, `Dueño` y `Admin`).

### Diagnóstico: si la app no carga datos

En orden, porque cada paso descarta algo más:

1. `curl http://<IP-del-equipo>:5000/api/health` — ¿el backend responde desde el LAN?
2. `adb shell ping -c 3 <IP-del-equipo>` — ¿el teléfono llega al equipo?
3. ¿La IP del allowlist es la misma que la del `--dart-define` y la del equipo *ahora*?
4. ¿El APK instalado es el que acabas de compilar? Sin `adb uninstall` previo,
   `adb install -r` puede dejar el binario viejo si la firma cambió.
5. `adb logcat | grep -i goaltime` — el error real suele estar ahí y la app no lo enseña.

---

## Pista B — Emulador, en un equipo con RAM

### El AVD no viaja con el repositorio

`cel_test` vive en `~/.android/avd/`, **fuera del repo**. Un clon en otra máquina no lo
trae, ni siquiera aunque tenga el SDK completo. Hay que crearlo una vez por equipo:

```sh
sdkmanager "system-images;android-34;google_apis;x86_64"
avdmanager create avd -n cel_test -k "system-images;android-34;google_apis;x86_64" -d pixel_6
```

### Requisitos: 16 GB de RAM

**Verificado el 1 de octubre de 2026** en el equipo de 3.7 GB por el camino contrario: no
se intentó arrancar el emulador, y el motivo está medido, no supuesto. El emulador pide
**1536 MB por AVD**, y ese equipo tiene 3.7 GB de los que ya estaban ocupados 1.7 GB por
otros procesos. La suma no da.

En 3.7 GB tampoco corre `flutter_tester` con el contrato real: el kernel lo mata y
`flutter_tools` reporta `did not complete`. Ese es el motivo de que esa prueba sólo exista
en CI ([`ESTADO.md`](ESTADO.md) hueco 4).

### Pasos

```sh
emulator -avd cel_test -no-window -no-audio -no-boot-anim &
adb wait-for-device
flutter devices                       # debe listarlo como device

docker compose up -d --build         # el emulador alcanza al host por 10.0.2.2
flutter run                          # el default ya es 10.0.2.2:5000
```

Dos diferencias con la Pista A que ahorran pasos:

- **`flutter run` en debug no necesita `--dart-define`**: `10.0.2.2` ya es el valor por
  defecto, y en el LAN la IP se alcanza sin intermediario.
- **El build de debug trae `INTERNET` solo**, así que el許可 del manifiesto no hace falta
  para esta pista. Sigue estando en el repo para el release, que es el que se entrega.

### El contrato real, que es lo que la RAM desbloquea

Es el otro motivo para usar el equipo grande, y el que la Pista A no puede ejecutar:

```sh
GOALTIME_API_URL=http://127.0.0.1:5000 flutter test test/contrato_real_test.dart
```

Sin esa variable los 9–10 tests aparecen como `skipped` y el comando sale verde sin haber
comprobado nada ([`ESTADO.md`](ESTADO.md) hueco 5). Es deliberado —la suite por defecto no
habla con la red— pero conviene saberlo antes de leer un verde como una verificación.

---

## Decisiones tomadas, y por qué

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Allowlist estricto de cleartext con la IP del equipo | `base-config cleartextTrafficPermitted="true"` | No rompe la garantía de que producción va por HTTPS. Cuesta rearmar la IP cuando el router reasigna; se resuelve reservándola por DHCP. |
| IP reservada por DHCP en el router | Recompilar el APK el día de la entrega | Es una línea en el router contra media hora de build. |
| Un backend independiente por equipo | Un backend compartido accesible por el LAN | El emulador alcanza al suyo por `10.0.2.2` sin saltos de red, y ningún equipo depende de que el otro esté encendido. |
| Las capturas de las dos pistas en un solo commit | Un commit desde cada equipo | Evita empujar dos veces y sincronizar ramas. `docs/capturas/` no está en `.gitignore`. |
| Un APK por destino, compilado en cada sitio | Un APK que sirva para los dos | `String.fromEnvironment` se resuelve en build: no hay forma de que un solo binario apunte a `10.0.2.2` y a la IP del LAN a la vez. |

## Qué sigue sin verificarse

- **La instalación del APK en un teléfono real.** Las comprobaciones sobre el binario
  (permiso, URL, firma) están hechas; el `adb install` y el recorrido, no. Son la fase D1
  del plan.
- **El arranque del emulador en este equipo.** El AVD, la imagen y `/dev/kvm` están
  verificados uno por uno, pero nunca se arrancó completo aquí. En el equipo de 16 GB
  tampoco se ha hecho todavía; es la fase D2.
- **iOS.** No compilado, y `flutter build ios` necesita macOS con Xcode.
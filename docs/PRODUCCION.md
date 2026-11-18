# GoalTime: piloto público con Railway + Supabase y APK sin teléfono

Actualizado el **18 de noviembre de 2026**. La API del piloto ya está desplegada en
Railway y conectada a Supabase; se generó y probó un APK *release* en emulador.
**No es una declaración de operación comercial ni disponibilidad garantizada.**
No se han comprobado todos los recorridos en un teléfono físico.

| Elemento | Estado verificado |
|---|---|
| Supabase | Proyecto dedicado `Goaltime` en organización `GoaltimeApk`; Data API desactivada por el titular. PostgreSQL remoto accesible desde la API |
| Railway | Servicio `goaltime-flutter` con Root Directory `/backend`, Dockerfile y dominio `https://goaltime-flutter-production.up.railway.app` |
| API | `/api/health` y `/api/ready` devolvieron `estado: ok`; `/api/canchas` mostró al menos una cancha activa al actualizar este documento |
| Pagos | **Piloto simulado** (`PAGADORA=mock`, `ALLOW_MOCK_PAYMENTS=1`), sin cobros reales |
| Android | APK firmado de 53,6 MB compilado sin teléfono; firma v2 y permiso `INTERNET` verificados. Cuenta cliente probada en emulador |
| Pendiente | No hay evidencia de prueba integral de reserva/pago en teléfono físico, respaldos restaurados, monitoreo continuo ni operación comercial |

El dominio público identifica la **API**, no una página web. La ruta `/` devuelve
`404` por diseño. Prueba [`/api/ready`](https://goaltime-flutter-production.up.railway.app/api/ready)
para consultar el estado actual; un `ok` histórico no promete que siga disponible.

## 1. Qué vamos a desplegar

```text
APK Flutter --HTTPS--> API Flask en Railway --PostgreSQL/SSL--> Supabase
```

Supabase se usa como base de datos PostgreSQL. Conservamos la autenticación JWT,
usuarios, permisos y reglas de Flask. **No usamos Supabase Auth, Edge Functions ni
acceso directo desde Flutter a sus tablas.** No se necesitan claves Supabase en el APK.

El APK del piloto usa la URL HTTPS pública y **no depende del portátil encendido,
de USB, de `adb reverse` ni del servidor Flask local**. El dispositivo sí requiere
internet; si Railway o Supabase se detienen por créditos, pausa o incidencia, las
consultas y reservas no funcionarán. No hay modo sin conexión ni garantía de
servicio gratuito ilimitado. Los datos nuevos se guardan en Supabase, no en
`backend/instance/goaltime.db`.

### Costos

Según [Railway Pricing](https://railway.com/pricing), consultado el 17/11/2026:
prueba de $5 una vez durante 30 días, plan Free con $1 mensual de uso incluido y Hobby
de $5/mes con $5 de uso incluido. Son USD y límites sujetos a cambios. Consumo de
memoria, CPU y red puede superar los créditos. Revisa el panel y configura alertas
o límites antes de publicar. No presupuestes disponibilidad continua con créditos mínimos.

Supabase tiene [planes y límites propios](https://supabase.com/pricing). Revisa las
condiciones de pausa, respaldos y almacenamiento del plan elegido. No actives un plan
de pago sin decidir el presupuesto.

## 2. Crear la base de datos en Supabase

1. Crear una cuenta y un **proyecto nuevo y dedicado a GoalTime**. Elegir una región
   cercana a Railway y guardar la contraseña de la base en un gestor de contraseñas.
2. Antes de cargar información, desactivar **Enable Data API** en Integrations → Data API.
   No la usamos y no queremos exponer tablas por REST/GraphQL.
3. En **Connect → Direct → Session pooler → Type: URI**, copiar la cadena de
   **Session pooler** (puerto 5432) para conexión
   IPv4 desde un backend persistente. Copiar host, usuario y puerto literalmente del
   panel: el usuario suele ser `postgres.PROJECT_REF`, no simplemente `postgres`.
4. Codificar la contraseña como parte de la URL. En PowerShell, ejecutar:

   ```powershell
   py -c 'import getpass, urllib.parse; print(urllib.parse.quote(getpass.getpass(), safe=str()))'
   ```

   La pide sin eco y muestra la versión codificada en la terminal local. Ese resultado
   **también es un secreto**. Sustituir **todo** `[YOUR-PASSWORD]`, incluidos los
   corchetes. No pegar la contraseña ni la URL en chats o archivos versionados.
5. La variable privada del backend queda con este formato:

```text
postgresql+psycopg://USUARIO:CONTRASEÑA_CODIFICADA@HOST_DEL_PANEL:5432/postgres?sslmode=require
```

`postgresql://` también se normaliza al driver instalado `psycopg` 3. No usamos
el transaction pooler de puerto 6543 para este arranque con migraciones. Si dispones
de IPv6, Supabase recomienda conexión directa para migraciones; el session pooler es
la alternativa IPv4 que conserva sesiones. No combines un host de un método con el
usuario de otro.

`sslmode=require` cifra la conexión, pero no verifica la identidad del servidor. Para
verificarla también, configurar el certificado raíz de Supabase en el contenedor y
usar `sslmode=verify-full&sslrootcert=RUTA_DEL_CERTIFICADO`.

### Protección de las tablas

La migración `0004_privacidad_postgres.py` habilita RLS en las tablas de GoalTime y en
`alembic_version`, sin políticas para clientes directos. Flask usa una conexión privada
propietaria de las tablas; aplica sus permisos de negocio en cada endpoint. El dueño
de tabla puede omitir RLS: **no estamos afirmando que RLS reemplaza los permisos Flask**.

Mantener Data API desactivada es la primera barrera. No distribuir la contraseña SQL,
ni claves secretas/service-role. Si se habilita Data API más adelante, hay que auditar
grants, funciones y políticas antes. Cada nueva tabla necesitará su protección.

No subir `backend/instance/goaltime.db` a Supabase ni borrar la base local. Las
migraciones crean el esquema remoto, no copian los usuarios/equipos locales. Si quieres
conservar datos locales en el despliegue, hace falta un proceso separado de exportación,
validación y migración con respaldo previo; esta entrega no lo ejecuta.

## 3. Publicar Flask en Railway

1. Crear la cuenta de Railway y revisar plan y cuotas.
2. Subir los cambios de código y migraciones a tu repositorio GitHub, **sin** `.env`,
   `.venv`, bases, `key.properties` ni keystores. Conectar ese repositorio en Railway.
3. Crear un servicio y elegir **Root Directory: `/backend`**. No usar la raíz de Flutter.
4. Usar el Dockerfile de backend. Configurar el archivo de configuración Railway como
   `/backend/railway.json` si el panel no lo detecta. El contexto debe contener
   `requirements.txt`, `app.py`, `Dockerfile`, `gunicorn.conf.py` y las migraciones.
5. En Networking, generar un dominio público de Railway. Si el primer despliegue falla
   por variables pendientes, no desactivar las validaciones: completar esta configuración.
6. En Variables configurar los valores de `backend/.env.production.example`:

| Variable | Valor |
|---|---|
| `GOALTIME_ENV` | `production` |
| `FLASK_DEBUG` | `0` |
| `DATABASE_URL` | Conexión privada de Supabase con SSL |
| `JWT_SECRET_KEY` | Secreto aleatorio propio, mínimo 32 caracteres |
| `APP_URL_BASE` | `https://TU_DOMINIO_REAL.up.railway.app`, sin `/api` |
| `CORS_ORIGINS` | El origen HTTPS anterior; configurar otros solo si hay frontend web |
| `PORT` | `5000` si Railway pidió elegir ese puerto al generar el dominio; debe coincidir con el puerto objetivo del dominio |
| `WEB_CONCURRENCY` | `1` inicialmente |
| `LLM_PROVEEDOR` | `mock` para empezar sin proveedor externo |
| `PAGADORA` / `ALLOW_MOCK_PAYMENTS` | `mock` / `1` **solo para un piloto sin cobros reales** |

Generar el secreto localmente: `python -c "import secrets; print(secrets.token_hex(32))"`.
Guardar el resultado solo en Railway. Rotarlo cierra la validez de los JWT anteriores.

Para un **piloto sin cobros reales**, `PAGADORA=mock` y
`ALLOW_MOCK_PAYMENTS=1` habilitan simulaciones de pago que pueden
confirmar reservas: no presentarlo como una pasarela real ni usarlo para ventas reales.
Para cobrar, usar `PAGADORA=stripe`, configurar claves y webhook HTTPS, y comprobar el
flujo con Stripe. Cambiar una variable no es certificación de operación comercial.

### Arranque y verificación

El contenedor ejecuta, en orden:

1. Validación de configuración (antes de tocar la base).
2. `alembic upgrade head`.
3. `flask --app app seed-catalogo` — solo roles/estados, sin cuentas conocidas.
4. Gunicorn en `0.0.0.0:$PORT` — Railway inyecta el puerto.

No sustituirlo por `flask run`, ni por el script local `iniciar_demo.py`. Los comandos
que crean cuentas demo quedan bloqueados en producción. No hay admin/usuarios/canchas
de prueba precargados en la base nueva.

Probar desde el navegador y desde otra red:

```text
https://TU_DOMINIO_REAL.up.railway.app/api/health
https://TU_DOMINIO_REAL.up.railway.app/api/ready
```

`health` comprueba proceso; `ready` comprueba acceso a la base, tablas y roles básicos.
Railway está configurado para usar `/api/ready` al activar un despliegue. Sus
healthchecks de despliegue **no son monitoreo continuo**: eso sigue pendiente.

### Primer administrador y primera cancha

La instalación remota **no carga canchas ni cuentas de demostración**. El registro
público solo crea `cliente` o `arbitro`; no puede autoasignarse el rol de dueño ni
el de administrador. Para habilitar el catálogo:

1. Abrir **Railway → servicio → Console** (el contenedor activo) y crear el
   primer administrador una sola vez:

   ```text
   flask --app app crear-admin
   ```

   El comando pide nombre, un correo **que no esté registrado** y una contraseña
   nueva (mínimo 12 caracteres, oculta y confirmada). Nunca pasar la contraseña
   como argumento ni capturarla en pantalla. No usar cuentas `@goaltime.test`.
2. Entrar en la app con esa cuenta de administrador. En **Usuarios**, tocar la
   cuenta de cliente que gestionará la cancha y elegir **Cambiar rol → Dueño**.
3. Cerrar la sesión y volver a entrar como dueño para renovar el rol del token.
   En **Mis canchas → Nueva cancha**, indicar nombre y ubicación. En la tarjeta
   creada, añadir **Horarios**, días, horas y tarifas; sin horarios no hay turnos
   reservables.
4. Entrar con una cuenta cliente y refrescar **Canchas**. No transformar en
   dueño la única cuenta cliente si también necesitas probar reservas: usa otra
   cuenta cliente para ese recorrido.

Se verificó que el catálogo público contiene una cancha; **no se registró en
esta documentación la ejecución del comando de creación de administrador ni
una prueba integral de reserva**. Si ya existe el administrador, no crees otro
por rutina. Los árbitros pueden registrarse como tales.

**Nunca ejecutar `pytest` con la base de producción:** algunas pruebas borran tablas
de su base de tests. Usar una base de pruebas aislada.

## 4. Firma Android del titular

La firma es necesaria para que las futuras actualizaciones puedan instalarse sobre
el mismo paquete. No debe generarse ni reemplazarse automáticamente en cada build.

Desde `android/`, crear `keystores/` si no existe y ejecutar el `keytool` del JDK:

```text
keytool -genkeypair -v -keystore keystores/goaltime-release.jks -alias goaltime -keyalg RSA -keysize 2048 -validity 10000
```

Introduce la contraseña cuando la herramienta la pida, no en el chat. Si `keytool`
no está en PATH, `flutter doctor -v` muestra el JDK utilizado; ejecuta el `keytool`
que hay en su carpeta `bin` (en Windows puede requerir `& 'RUTA\keytool.exe'`).

Si ya hay un keystore de una versión distribuida, **usar ese**, no crear otro. Haz
respaldo seguro del keystore, alias y contraseñas, fuera del repositorio.

Crear `android/key.properties` localmente:

```properties
storeFile=keystores/goaltime-release.jks
storePassword=TU_CONTRASEÑA_PRIVADA
keyAlias=goaltime
keyPassword=TU_CONTRASEÑA_PRIVADA
```

Usar `/` en rutas, incluso en Windows. No pegar esas contraseñas en el chat.
`key.properties` y los `.jks` están excluidos de Git. El archivo de propiedades
contiene secretos en texto: restringir su acceso y almacenarlo con cuidado.

## 5. Compilar el APK SIN teléfono

Requisitos: Flutter, Android SDK, JDK y licencias Android aceptadas. **No necesitas
emulador ni celular**. Desde la raíz de `goaltime-flutter`:

```powershell
flutter pub get
python tool/compilar_apk.py --api-url https://TU_DOMINIO_REAL.up.railway.app
```

El script valida la URL, la existencia de la firma y `/api/ready` antes de ejecutar:

```text
flutter build apk --release --dart-define=API_BASE_URL=https://TU_DOMINIO_REAL.up.railway.app
```

Resultado: `build/app/outputs/flutter-apk/app-release.apk`.
El archivo se puede copiar o renombrar (por ejemplo, `GoalTime.apk`) sin cambiar
firma, nombre instalado ni código; **no mover ni publicar el keystore**. Para
distribuir una actualización, mantener el mismo keystore y aumentar
versión/build en `pubspec.yaml`.
Con `--split-per-abi` en el script se generan APK más pequeños por arquitectura;
el universal es más sencillo para compartir entre distintos Android.

Release rechaza firma debug implícita y direcciones locales/HTTP. La configuración
Android de release no permite tráfico HTTP; fotos y otras URLs también deben ser HTTPS.
Debug conserva el entorno local. En `pubspec.yaml` incrementa la versión/build al
publicar actualizaciones. Para Play Store se necesitará un AAB y los requisitos de la tienda.

Un APK instalado previamente con firma debug no se actualiza directamente con otra
firma release. No desinstalar automáticamente: explica el cambio al usuario y respalda
lo que corresponda. Los datos remotos no se trasladan entre bases por reinstalar la app.

### Prueba de aceptación

1. Compartir **solo el APK** con participantes concretos del piloto (Drive/OneDrive
   con acceso restringido), descargarlo e instalarlo en Android. La compilación
   no necesita USB; un emulador también puede instalar el APK.
2. Apagar el backend local y probar con datos móviles, no solo la Wi-Fi del portátil.
3. Registrar cliente y árbitro; crear equipo/jugador y editarlo; publicar/ocultar perfil.
4. Cerrar y abrir la app y comprobar persistencia en la base remota.
5. Probar dos cuentas: no deben ver/editar equipos ajenos.
6. Verificar reservas y pagos de acuerdo con el modo seleccionado.
7. Revisar pantallas con texto grande, teclado abierto y conexión interrumpida.

Al 18/11/2026 se verificaron la compilación firmada y un registro/uso de cliente
en emulador. **Los demás pasos no se marcan como completados** sin evidencia.

## 6. Si falla

| Síntoma | Qué comprobar |
|---|---|
| No conecta desde el APK | URL compilada HTTPS, `/api/ready` desde datos móviles, cuotas y estado del servicio |
| `ready` devuelve 503 | Logs de Railway, conexión/contraseña Supabase, SSL, host/usuario del mismo pooler y migraciones |
| Railway no arranca | Root Directory, variables completas, puerto `PORT`, DEBUG=0 y secreto válido |
| `ECIRCUITBREAKER` al conectar Supabase | Detener reintentos: el pooler bloquea temporalmente tras muchos fallos. Copiar **la URI completa de Session pooler**, usuario `postgres.PROJECT_REF`, puerto 5432, contraseña codificada una sola vez y **sin corchetes**. Tras corregirla, esperar a que caduque el bloqueo antes de reintentar |
| La raíz `/` muestra `404` | Normal: la API no sirve una página web. Probar `/api/ready` |
| Catálogo vacío | No se copió el seed local. Crear admin, asignar dueño, publicar cancha y añadir horarios; no ejecutar `flask seed` en producción |
| Supabase bloquea filas | Flask debe usar su conexión privada propietaria; no `anon` ni una clave pública |
| Release no compila | Firma, alias/rutas y URL real; no quitar validaciones para forzarlo |
| No se instala sobre la app anterior | Firma distinta o versión inferior; no borrar datos sin revisar |
| Error visual ocasional | Captura, pantalla, pasos, modelo, orientación y tamaño de letra para reproducir |

No habilitar `badCertificateCallback` ni desactivar la verificación TLS para resolver
errores de certificados. No cambiar globalmente HTTP a permitido en release.

## 7. Alcance y pendientes antes de operación comercial

Esto prepara un despliegue inicial; no completa una auditoría de seguridad ni promete
alta disponibilidad. Quedan por configurar/verificar: respaldos y restauración,
monitoreo continuo y alertas, límites de solicitudes, revocación de sesiones,
consentimiento/política de datos personales, presupuesto y pruebas de carga.
No se han diagnosticado todos los errores visuales intermitentes: hacen falta ejemplos.
Una contraseña SQL que haya aparecido en un chat, captura o repositorio se debe
**rotar inmediatamente**, actualizar en Railway y evitar intentos repetidos con
la antigua. No se documentan credenciales ni cadenas de conexión reales.

Fuentes: [Railway healthchecks](https://docs.railway.com/guides/healthchecks),
[Supabase conexiones](https://supabase.com/docs/guides/database/connecting-to-postgres),
[Supabase seguridad de Data API](https://supabase.com/docs/guides/api/securing-your-api).

## 8. Evidencia y alcance de las comprobaciones

**Nueva evidencia (17–18/11/2026):**

- Tras corregir los relojes del backend, **439** pruebas Python pasaron en la
  máquina de desarrollo. La corrección del Dockerfile añadió una prueba
  estática adicional; los cuatro jobs del CI (SQLite, PostgreSQL con
  migraciones, Flutter y contrato real) acabaron en verde al integrar el PR #2
  en `main`. [Ver ejecuciones](https://github.com/Adrixn1140/goaltime-flutter/actions).
- La API pública respondió `estado: ok` en `/api/health` y `/api/ready`, y
  devolvió al menos una cancha activa en `/api/canchas`. Esto prueba una
  consulta remota al esquema y catálogo preparados, no todo el flujo de pago.
- `py tool/compilar_apk.py --api-url https://goaltime-flutter-production.up.railway.app`
  construyó un APK
  *release* de **53,6 MB sin dispositivo conectado**. `apksigner verify`
  confirmó firma v2 (un firmante) y `aapt dump permissions` confirmó
  `android.permission.INTERNET`. El titular creó y respaldó el keystore;
  contraseñas y certificado no se publican.
- El titular instaló el APK en emulador Android, creó una cuenta cliente y
  vio el estado de catálogo vacío. Posteriormente la API remota mostró al
  menos una cancha. No consta que el cliente la haya reservado o pagado.

**Registro histórico anterior, 17/11/2026 (no describe el estado actual):**

Comprobado en Windows el 17/11/2026:

- `flutter analyze`: sin incidencias.
- `flutter test`: 130 aprobadas; 10 de contrato HTTP real omitidas sin `GOALTIME_API_URL`.
- `backend/.venv/Scripts/python.exe -m pytest -q` (usando ese Python desde backend):
  435 pruebas aprobadas con SQLite. No ejecutar contra una base de producción.
- Pruebas visuales a 320 × 640 y texto al 200 % para catálogo/sugerencias del asistente.
  Nombre y precio ya no compiten en una fila estrecha; precio/botón pueden pasar de línea.
  No es una comprobación de todas las pantallas ni de todos los errores ocasionales.
- `flutter build apk --debug`: compiló **sin dispositivo conectado**; artefacto de
  comprobación en `build/app/outputs/flutter-apk/app-debug.apk`. Este APK conserva API
  local de desarrollo: **no es el APK de producción**.
- Tarea Gradle `:app:validateProductionRelease`: rechaza la compilación por ausencia
  de `android/key.properties`, como se diseñó. No se generó ni sobrescribió un keystore.
- En esa fecha, PostgreSQL/Supabase/Railway aún no se habían probado en vivo. La
  migración RLS se había verificado con pruebas de SQL y cobertura de tablas,
  no con una cuenta remota; después se desplegó el esquema en Supabase.

En ese corte todavía faltaban proyectos, API pública, firma y APK; **esos pasos
ya se realizaron**. Permanecen las comprobaciones y medidas operativas del
apartado 7.

# GoalTime

Aplicación Flutter de reservas de canchas sintéticas para Riohacha (Colombia),
con API propia en Flask. El **piloto Android** conecta por HTTPS con la API en
Railway; la API guarda los datos en PostgreSQL de Supabase.

```text
APK Flutter ──HTTPS──> Flask en Railway ──PostgreSQL/SSL──> Supabase
```

**Estado al 18 de noviembre de 2026:** el servicio [responde en
`/api/ready`](https://goaltime-flutter-production.up.railway.app/api/ready),
la base remota contiene al menos una cancha visible y se compiló un APK
*release* firmado sin conectar un teléfono. Se registró y usó una cuenta
cliente en un **emulador Android**. No consta una prueba completa de
reservas/pagos en un teléfono físico, ni una auditoría para operación comercial.
El APK actual es para **piloto con pagos simulados**, no para cobrar dinero.
El estado del servicio puede cambiar: compruébalo antes de una demostración.

## Qué hace

| Rol | Funciones |
|---|---|
| Cliente | Registro/inicio de sesión, catálogo, disponibilidad, reservas, pagos de prueba, equipos y jugadores, asistente |
| Dueño | Crea/edita canchas y horarios, consulta sus reservas |
| Árbitro | Registro, perfil, disponibilidad y tarifa publicados en el directorio |
| Administrador | Usuarios y roles, activación/desactivación y reportes |

El registro público solo crea **clientes o árbitros**. Para crear canchas se
necesita un **dueño**: un administrador asigna ese rol a una cuenta existente.
La base nueva no importa automáticamente los usuarios ni las canchas de la demo local.
Consulta [cómo habilitar el primer dueño y publicar una cancha](docs/PRODUCCION.md#primer-administrador-y-primera-cancha).

## Ponerlo en marcha

### Piloto desplegado

- [Guía de producción/piloto](docs/PRODUCCION.md): Supabase, Railway, secretos,
  dominio, firma Android, APK, comprobaciones y límites del plan.
- URL pública de la API (no es una página web):
  `https://goaltime-flutter-production.up.railway.app`.
  `/api/health` comprueba el proceso; `/api/ready` también comprueba tablas y
  catálogos. La ruta `/` responde **404 por diseño**.
- El archivo firmado construido localmente se llamó `app-release.apk` y se
  renombró a `GoalTime.apk` para compartirlo. El APK **no se versiona en GitHub**.
  Cambiar el nombre del archivo no cambia el nombre de la aplicación instalada.
- Para recompilar **sin emulador ni teléfono conectado**, con firma privada local
  y la API lista:

  ```powershell
  flutter pub get
  py tool/compilar_apk.py --api-url https://goaltime-flutter-production.up.railway.app
  ```

  El resultado nuevo se genera en `build/app/outputs/flutter-apk/app-release.apk`.
  El script exige `android/key.properties`, un keystore propio y respuesta válida
  de `/api/ready`. **No crees otra firma** si ya distribuiste el APK del piloto:
  las actualizaciones requieren la misma clave. No subas `key.properties`,
  `.jks`, `.env`, contraseñas ni URI de la base.

### Desarrollo local (separado del piloto)

La guía [de puesta en marcha local](docs/PUTA-EN-MARCHA.md) y
[`backend/README.md`](backend/README.md) explican SQLite, demo y Docker Compose.
`tool/iniciar_demo.py` crea cuentas **solo de desarrollo**: nunca se ejecuta
en Railway. El valor por defecto de Flutter (`http://10.0.2.2:5000`) es
**solo para debug en el emulador**; el APK *release* lleva la URL HTTPS de
Railway dentro del binario.

```powershell
# Tras configurar el backend de desarrollo y arrancarlo localmente:
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

### Pruebas y CI

```powershell
flutter analyze
flutter test
cd backend
.\.venv\Scripts\python.exe -m pytest -q
```

GitHub Actions comprueba backend con SQLite **y** PostgreSQL, migraciones
con Alembic, Flutter y contrato app ↔ API real; los cuatro trabajos de
[`main`](https://github.com/Adrixn1140/goaltime-flutter/actions) pasaron tras
integrar la corrección de Dockerfile el 18/11/2026. SQLite agiliza pruebas
locales; **Supabase PostgreSQL es la base del piloto**. No ejecutar `pytest`
con credenciales de producción: algunas pruebas recrean tablas.

## Operación y límites

- Apagar el portátil **no apaga** la app ni la API: una instalación consulta
  Railway y Supabase por internet. Sí necesita conexión en el dispositivo y
  ambos servicios activos. Sin conexión, la app no funciona sincrónicamente;
  no hay modo sin conexión ni garantía de alta disponibilidad.
- Los planes gratuitos/de prueba tienen créditos, límites y posibles pausas.
  Comprueba [Railway Pricing](https://railway.com/pricing) y
  [Supabase Pricing](https://supabase.com/pricing) antes de invitar personas.
  Créditos agotados o servicios pausados pueden dejar la API inaccesible.
- En este piloto `PAGADORA=mock` y `ALLOW_MOCK_PAYMENTS=1`: **no hay cobro real**,
  aunque una simulación puede confirmar una reserva. No solicites tarjetas ni
  anuncies ventas. Stripe requiere un despliegue y pruebas separados.
- Respaldos/restauración, monitoreo continuo, alertas, límites de tráfico,
  privacidad de datos y prueba completa en teléfono físico siguen pendientes.
  `ready` verifica el estado al consultarlo, no monitorea continuamente.

## Documentación

- [Producción y piloto](docs/PRODUCCION.md) — configuración y diagnóstico actual.
- [Estado verificado](docs/ESTADO.md) — actualización actual y evidencias
  históricas fechadas.
- [API y desarrollo local](backend/README.md).
- [Especificación de API](docs/spec.md), [equipos](docs/EQUIPOS.md),
  [árbitros y asistente](docs/ARBITROS.md), [optimización](docs/OPTIMIZACION.md).
- [Puesta en marcha local](docs/PUTA-EN-MARCHA.md),
  [entorno](docs/ENTORNO.md) y [pruebas en dispositivo](docs/PRUEBA-EN-DISPOSITIVO.md):
  conservan registros históricos de la demo local; las instrucciones vigentes
  del APK público están en `PRODUCCION.md`.

# Mis equipos — avance demostrativo

## Alcance (9 de octubre de 2026)

Primer paso hacia la organización de torneos. Un cliente autenticado puede crear
equipos y registrar jugadores con **nombre, apellido, número de documento y celular**.
Los datos se guardan en la API y sobreviven al cierre de la app. No es todavía un
organizador de torneos: no hay inscripciones, categorías, partidos ni clasificación.

### Contrato de esta primera versión

Todas las rutas requieren JWT de una cuenta activa con rol `cliente`. El propietario
sale del token, nunca del formulario. Otro cliente no puede consultar un equipo ajeno
(404), y los roles dueño/admin no tienen acceso (403).

| Método | Ruta | Cuerpo / respuesta |
|---|---|---|
| GET | `/api/equipos` | Lista de equipos propios con sus jugadores |
| POST | `/api/equipos` | `{nombre}` → equipo creado, 201 |
| GET | `/api/equipos/{id}` | Equipo propio con jugadores, 200 |
| POST | `/api/equipos/{id}/jugadores` | `{nombre, apellido, documento, celular}` → jugador, 201 |

- Nombre de equipo: 3–80 caracteres. Nombre y apellido: 2–80 caracteres cada uno.
- Documento: texto de 5–20 dígitos; se conservan ceros iniciales.
- Celular: texto de 10–15 dígitos, sin espacios ni `+` (puede incluir código de país).
- Todos los campos son obligatorios. JSON inválido o campos inválidos: 400.
- Un documento no puede repetirse **dentro del mismo equipo** (409). Esta versión no
  impide que un jugador pertenezca a equipos distintos.
- Los equipos nacen sin jugadores. No hay jugadores ficticios precargados.

### Privacidad y límites

Usar **datos ficticios** para la demostración. Documento y celular solo están disponibles
para el creador del equipo; las tarjetas ocultan parcialmente el documento. Esto no
equivale a cifrado en la base de datos ni a una política completa de tratamiento de
datos. Antes de producción se requieren HTTPS, consentimiento de los jugadores,
política de privacidad, retención, eliminación y tratamiento especial para menores.

No se incluyen aún edición/eliminación de equipos o jugadores, invitaciones,
verificación de identidad, reglas de elegibilidad ni vínculo con reservas.

## Cómo probarlo

1. Preparar el backend como indica `backend/README.md`, incluyendo migraciones.
2. Entrar con `cliente@goaltime.test` / `Goaltime123!`.
3. Abrir **Equipos** y pulsar **Crear equipo**; por ejemplo, `Los del barrio`.
4. Abrir el equipo y pulsar **Añadir jugador**.
5. Usar `Ana`, `Prueba`, `0001234567`, `3000000000` como datos ficticios.
6. Repetir el documento: debe aparecer un mensaje, sin duplicar el jugador.
7. Cerrar sesión y volver a entrar: el equipo y su plantilla siguen guardados.
8. Entrar con otro cliente: no debe ver los equipos de la primera cuenta.

## Diseño

Identidad verde deportiva, fondos neutros, tarjetas redondeadas, mejor jerarquía de
títulos y formularios cómodos. El login, catálogo y módulo de equipos reciben un
tratamiento visual nuevo sin depender de fotos remotas ni fuentes descargadas.

## Próximos pasos

1. Editar y retirar jugadores, con confirmación y política de datos.
2. Escudo del equipo y responsables/invitaciones.
3. Torneo, categorías, inscripción y revisión de plantillas.
4. Calendario de partidos vinculado a disponibilidad/reservas.
5. Resultados, tabla de posiciones y reglas de desempate.

## Corrección de arranque entre computadores

Alembic y Flask resuelven `sqlite:///goaltime.db` en `backend/instance/`, sin depender
del directorio de ejecución. Una prueba de regresión verifica que Flask ve las tablas
migradas. Las rutas absolutas y PostgreSQL conservan su configuración.

El comando `flask --app app preparar-demo` aplica Alembic y carga datos idempotentes;
es explícito y exclusivo para desarrollo. No se crean cuentas de demo automáticamente
en producción ni se sustituye Alembic por `create_all()`.

Desde la raíz, `backend\.venv\Scripts\python.exe tool\iniciar_demo.py` (Windows) o
`backend/.venv/bin/python tool/iniciar_demo.py` (Linux/macOS) prepara **y arranca**.
En otro equipo hay que instalar las dependencias y copiar **todos los archivos de
`backend/migrations/versions/`**, incluida la revisión previa `086fbc434d9a_.py`.

## Verificación realizada

Comprobado en Windows el 9 de octubre de 2026:

- `flutter analyze`: sin incidencias.
- `flutter test`: **113 pruebas pasan**, 10 pruebas de contrato real omitidas por no
  definir `GOALTIME_API_URL`.
- `backend/.venv/Scripts/python.exe -m pytest -q`: **351 pruebas pasan** sobre SQLite.
- Pruebas de equipos: creación, persistencia, validaciones, documento duplicado,
  aislamiento por cuenta, rol, cuenta desactivada, errores/reintento, navegación,
  formulario en celular estrecho y limpieza al cambiar de sesión.
- Preparación de una base temporal desde cero y repetición del comando sin duplicar
  datos; login posterior correcto.
- API local: login correcto y `GET /api/equipos` responde 200 con JWT.
- APK debug compilado e instalado en el emulador Android; nuevo login revisado
  visualmente. La creación de plantillas se verifica automáticamente en tests.

No se ejecutó esta versión en Linux, macOS, iOS ni PostgreSQL localmente; las
instrucciones de arranque para esas plataformas no sustituyen una prueba allí.

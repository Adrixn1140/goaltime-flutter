# Árbitros, equipos y asistente — contrato del avance

## Alcance (30 de octubre de 2026)

- Equipos: crear, consultar, renombrar y eliminar; añadir, editar y retirar jugadores.
- No hay límite de tres equipos, ni por cuenta ni por documento (decisión del usuario).
- El mismo documento no se repite dentro de una plantilla; sí puede estar en otras.
- Árbitros: registro de cuenta, perfil privado editable y publicación voluntaria en un
  directorio para usuarios autenticados. Sin contratación, agenda ni pagos.
- Asistente: orientación sobre estas funciones y consulta de información real, sin
  crear, eliminar, reservar ni contratar en nombre del usuario.

## API

JWT de cuenta activa en todas las rutas salvo registro/login.

| Método | Ruta | Permiso / resultado |
|---|---|---|
| PATCH | `/api/equipos/{id}` | Cliente creador, `{nombre}`, 200 |
| DELETE | `/api/equipos/{id}` | Cliente creador, elimina plantilla y jugadores, 204 |
| PATCH | `/api/equipos/{id}/jugadores/{jugador_id}` | Cliente creador, campos parciales, 200 |
| DELETE | `/api/equipos/{id}/jugadores/{jugador_id}` | Cliente creador, 204 |
| POST | `/api/register` | `tipo_cuenta: cliente` (predeterminado) o `arbitro` |
| GET | `/api/arbitros` | Cualquier cuenta activa, solo perfiles publicados y cuentas activas con rol árbitro |
| GET | `/api/arbitros/mi-perfil` | Solo árbitro, perfil propio o `null` |
| PUT | `/api/arbitros/mi-perfil` | Solo árbitro, crea/actualiza perfil propio, 200 |

Los campos `rol`/`role` del registro no conceden privilegios. Dueños y administradores
siguen siendo asignados por administración. Un equipo/jugador ajeno devuelve 404.

Perfil: `ciudad` (2–100), `celular` (10–15 dígitos), `experiencia` (años, entero 0–60),
`biografia` (0–500), `tarifa` (COP por partido, >0 y hasta 10.000.000, máximo dos decimales),
`disponible` y `publicado` (booleanos obligatorios). El nombre viene de la cuenta.
`PUT` requiere todos los campos; no publica automáticamente. El directorio admite
`q` (nombre/ciudad, hasta 100 caracteres) y `disponible=true|false`, y se ordena por tarifa.

Publicar autoriza mostrar nombre, ciudad, experiencia, biografía, celular y tarifa a
otras cuentas de la app. Ocultar retira el perfil del directorio. Disponible es una
declaración general, no garantía de agenda, certificación ni reserva. Precio por partido
orientativo, sin comisión ni cobro integrado. Usar datos ficticios durante la demo.

## Equipos y privacidad

Se mantienen las validaciones de `EQUIPOS.md`. Edición valida en servidor; colisiones de
documento devuelven 409 y no pierden datos. Eliminaciones piden confirmación en la app;
no afectan reservas, pues las plantillas todavía no se vinculan a ellas. No existe
verificación de identidad ni invitaciones de jugadores como cuentas de usuario.

## Asistente

La guía local funciona incluso sin proveedor IA: explica equipos/jugadores, publicación,
precios y límites reales. Puede resumir equipos propios sin revelar documentos/celulares
y consultar perfiles publicados. Devuelve accesos a las pantallas correspondientes.
La búsqueda de canchas conserva los proveedores mock/Ollama/Gemini. No envía plantillas
privadas al modelo ni inventa árbitros o tarifas. No es una conversación con memoria de
turnos: cada consulta debe indicar su tema.

## Recorrido de demostración

1. Cliente → Equipos → crear → añadir jugador → editar datos → retirar con confirmación.
2. Editar nombre del equipo; crear más de tres para comprobar que no hay límite.
3. Salir → Regístrate → seleccionar Árbitro → crear cuenta.
4. Mi perfil arbitral → completar ciudad, celular, años, tarifa y presentación → guardar.
5. Activar Publicar perfil y guardar: aparece en el directorio; desactivar disponible no
   lo oculta, pero lo excluye del filtro Solo disponibles.
6. Buscar por nombre/ciudad; consultar tarifas y contacto. Ocultar el perfil y verificar
   que desaparece. Cuentas desactivadas tampoco se muestran.
7. Cliente → Asistente → preguntar cómo añadir jugadores o buscar árbitros disponibles.

## Fuera de alcance

Torneos completos, contratación, pagos de árbitros, valoraciones, validación de títulos,
agenda por fecha/hora, escudos, invitaciones y pertenencia de jugadores autenticados.

## Implementación y uso (30 de octubre de 2026)

- **Cliente:** Equipos → crear → añadir jugadores. Desde la plantilla se puede editar
  el nombre, corregir los cuatro campos de un jugador o retirarlo. Eliminar equipo
  elimina también sus jugadores; ambas eliminaciones requieren confirmación y, si falla
  la API, mantienen el diálogo abierto con un error y posibilidad de reintento.
- **Directorio:** Canchas → icono Árbitros, o Perfil → Árbitros (también disponible para
  dueño/admin desde su perfil). Buscar por nombre/ciudad, aplicar Solo disponibles o
  limpiar filtros. Solo se muestran perfiles que sus titulares publicaron, con contacto
  y tarifa COP por partido. No se crean árbitros falsos ni perfiles públicos en el seed.
- **Árbitro:** elegir Árbitro en el registro, completar Mi perfil arbitral y guardar.
  El perfil comienza privado. Activar Publicar perfil implica autorizar la exposición de
  los campos indicados; cambiar el interruptor no basta: hay que **guardar**. Ocultar
  retira el perfil sin perder los datos propios. Un error conserva el formulario.
- **Administración:** reconoce el nuevo rol. Cambiar un árbitro a otro rol despublica su
  perfil. Tampoco se permite dejar canchas activas sin gestión al convertir un dueño en
  árbitro. Desactivar una cuenta bloquea inmediatamente las rutas protegidas.
- **Asistente del cliente:** chips de ejemplos, botón de limpiar conversación y accesos
  a equipos/directorio. La guía de estas funciones es local y determinista (`guia-local`),
  funciona sin Gemini/Ollama y consulta la misma base que el directorio. No es una nueva
  integración generativa: la disponibilidad mantiene los motores ya existentes. El chat
  se limpia al abandonar la sección y al cambiar de sesión, y descarta respuestas tardías
  de una sesión anterior. El backend limita cada mensaje a 1000 caracteres.

### Actualizar la instalación sin perder equipos

Desde la raíz del proyecto, en Windows:

```powershell
backend\.venv\Scripts\python.exe tool\iniciar_demo.py
```

En Linux/macOS: `backend/.venv/bin/python tool/iniciar_demo.py`.
Este comando aplica Alembic y prepara la demo antes de arrancar. La migración
`0003_arbitros.py` añade la tabla y el rol en instalaciones existentes, sin borrar
cuentas, equipos ni jugadores. No requiere cambiar la URL de la app ni reinstalar Python.
En producción usa `alembic upgrade head` y tu servidor habitual, no las cuentas de demo.

### Android físico por USB (sin depender de Wi-Fi)

Con el servidor anterior encendido, depuración USB autorizada y Android SDK instalado:

```powershell
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
& $adb devices
$idAndroid = 'ID_DEL_CELULAR'  # reemplazar por el identificador de la lista
& $adb -s $idAndroid reverse tcp:5000 tcp:5000
flutter run -d $idAndroid --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

Mantén USB y servidor conectados; repite `reverse` después de reconectar/reiniciar.
El APK debug generado en este avance usa `http://127.0.0.1:5000` para esta modalidad,
no es un APK autónomo con API pública. Ubicación:
`build/app/outputs/flutter-apk/app-debug.apk`.

Para emulador, `flutter run` conserva la dirección predeterminada `10.0.2.2:5000`.
Para distribución real hace falta desplegar la API con HTTPS y recompilar con su URL.

### Pruebas del avance

- API: registro permitido solo para cliente/árbitro; publicación/ocultación, filtros,
  límites y precisión monetaria; aislamiento de perfiles y equipos; duplicados al editar
  jugadores sin perder los valores anteriores; eliminación en cascada; ausencia de
  límite de tres equipos; inventario de todas las rutas protegidas.
- Migraciones: base nueva y actualización de una base con equipos/jugadores existentes,
  preservando documentos y habilitando registro de árbitros sin repetir el seed.
- Flutter: flujos de registro, directorio, publicación/ocultación, edición y eliminación
  con confirmación, errores sin pérdida del formulario, navegación desde el asistente y
  rechazo de destinos de navegación desconocidos.
- No se ha probado este avance en PostgreSQL, iOS, Linux ni macOS localmente.
  La disponibilidad de un árbitro y su experiencia no se verifican con terceros.

### Resultado de la verificación local

En Windows, 30 de octubre de 2026:

| Comando | Resultado |
|---|---|
| `.venv/Scripts/python.exe -m pytest -q` (desde `backend/`) | 404 pruebas pasan sobre SQLite |
| `flutter test` | 123 pasan; 10 de contrato HTTP real omitidas por no definir `GOALTIME_API_URL` |
| `flutter analyze` | Sin incidencias |
| `flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:5000` | APK generado correctamente |
| `python -m alembic upgrade head` (entorno virtual del backend) | Migración aplicada a la base SQLite local |

El APK no se instaló en un dispositivo en esta ejecución: `flutter devices` no
detectó teléfonos ni emuladores conectados. Las pruebas de UI usan la app y sus
repositorios con un adaptador HTTP falso; las de API usan Flask y bases de prueba.
No sustituyen una prueba manual en el teléfono ni contra proveedores IA externos.

# Arranque local actualizado

Para evitar el error de inicio de sesión por una base sin preparar, desde la raíz
`goaltime-flutter` ejecuta en Windows:

```powershell
backend\.venv\Scripts\python.exe tool\iniciar_demo.py
```

En Linux/macOS: `backend/.venv/bin/python tool/iniciar_demo.py`.
Necesitas haber creado el entorno virtual e instalado `backend/requirements.txt`.
Este comando migra, carga las cuentas de demo sin duplicarlas y arranca el backend.
Solo para desarrollo; no copies `.venv` de un computador a otro.

En otra terminal: `flutter pub get` y `flutter run` con el emulador encendido.
Nuevo avance: entra como cliente → **Equipos** → crea un equipo → añade jugadores.
Usa datos ficticios. Documentación completa: [docs/EQUIPOS.md](docs/EQUIPOS.md).

## Instrucciones manuales originales

el emulador debe estar encendido (Android Studio → Device Manager → ▶).
iniciar:
Terminal 1: backend
powershell
cd C:\Users\lemus\OneDrive\Documentos\GoalTime-Flutter\goaltime-flutter\backend
.venv\Scripts\Activate.ps1
flask --app app run --host=0.0.0.0 --port=5000

Si es la primera vez en esta máquina, o si el login falla, antes de arrancar el servidor ejecuta:

powershell
alembic upgrade head
flask seed-catalogo
flask seed

Terminal 2: la app
powershell
cd C:\Users\lemus\OneDrive\Documentos\GoalTime-Flutter\goaltime-flutter
flutter pub get
flutter devices
flutter run

Iniciar sesión
Cliente: cliente@goaltime.test
Dueño: dueno1@goaltime.test
Admin: admin@goaltime.test
Contraseña de todos: Goaltime123!

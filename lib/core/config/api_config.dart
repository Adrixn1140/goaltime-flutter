/// Configuración global de la app.
///
/// `API_BASE_URL` se puede sobreescribir en build con
/// `--dart-define=API_BASE_URL=https://...`.
///
/// El valor por defecto apunta al backend en el emulador de Android: `10.0.2.2` es el
/// alias que usa el emulador para alcanzar `localhost` de la máquina anfitriona. En un
/// dispositivo físico hay que pasar la IP de la máquina en el LAN
/// (`--dart-define=API_BASE_URL=http://192.168.0.10:5000`).
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
}

/// Claves del almacenamiento seguro (`flutter_secure_storage`).
const String tokenStorageKeyToken = 'access_token';
const String tokenStorageKeyRol = 'rol';
const String tokenStorageKeyNombre = 'nombre';
const String tokenStorageKeyEmail = 'email';

/// Configuración global de la app.
///
/// `API_BASE_URL` se puede sobreescribir en build con
/// `--dart-define=API_BASE_URL=https://...`.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://goaltime-app.onrender.com',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
}

/// Almacenamiento seguro del token y el rol (flutter_secure_storage).
const String tokenStorageKeyToken = 'access_token';
const String tokenStorageKeyRol = 'rol';
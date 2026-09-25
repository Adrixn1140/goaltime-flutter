import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';

/// Almacenamiento clave-valor detrás de [TokenStorage].
///
/// Existe como interfaz y no como llamada directa a `flutter_secure_storage` porque ese
/// plugin habla con un método nativo: en un test unitario responde
/// `MissingPluginException` y ninguna prueba de sesión podría arrancar. Los tests
/// inyectan [MemoriaSegura] y prueban de verdad la lógica de sesión.
abstract interface class SecureStore {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String valor);
  Future<void> borrarTodo();
}

/// Implementación real sobre el almacenamiento seguro del sistema.
class SecureStorePlataforma implements SecureStore {
  const SecureStorePlataforma();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> leer(String clave) => _storage.read(key: clave);

  @override
  Future<void> escribir(String clave, String valor) => _storage.write(key: clave, value: valor);

  @override
  Future<void> borrarTodo() => _storage.deleteAll();
}

/// Almacenamiento en memoria. Sólo para tests.
class MemoriaSegura implements SecureStore {
  MemoriaSegura([Map<String, String>? inicial])
    : _valores = {...?inicial};

  final Map<String, String> _valores;

  @override
  Future<String?> leer(String clave) async => _valores[clave];

  @override
  Future<void> escribir(String clave, String valor) async => _valores[clave] = valor;

  @override
  Future<void> borrarTodo() async => _valores.clear();
}

/// Sesión del usuario: token, rol y los datos que el backend aún no expone por perfil.
class TokenStorage {
  const TokenStorage([this._store = const SecureStorePlataforma()]);

  final SecureStore _store;

  Future<String?> get accessToken => _store.leer(tokenStorageKeyToken);

  Future<String?> get rol => _store.leer(tokenStorageKeyRol);

  Future<String?> get nombre => _store.leer(tokenStorageKeyNombre);

  Future<String?> get email => _store.leer(tokenStorageKeyEmail);

  Future<void> saveSession({
    required String token,
    required String rol,
    String? nombre,
    String? email,
  }) async {
    await _store.escribir(tokenStorageKeyToken, token);
    await _store.escribir(tokenStorageKeyRol, rol);
    if (nombre != null) await _store.escribir(tokenStorageKeyNombre, nombre);
    if (email != null) await _store.escribir(tokenStorageKeyEmail, email);
  }

  /// Borra **toda** la sesión guardada, no sólo el token: dejar el rol o el correo de la
  /// cuenta anterior haría que el perfil mostrara datos de alguien que ya cerró sesión.
  Future<void> clear() => _store.borrarTodo();
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper sobre [FlutterSecureStorage] para token y rol de sesión.
class TokenStorage {
  const TokenStorage();

  static const String _keyToken = 'access_token';
  static const String _keyRol = 'rol';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<String?> get accessToken => _storage.read(key: _keyToken);

  Future<String?> get rol => _storage.read(key: _keyRol);

  Future<void> saveSession({required String token, required String rol}) async {
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyRol, value: rol);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyRol);
  }
}
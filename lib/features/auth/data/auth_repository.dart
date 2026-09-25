import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';

/// Usuario devuelto por `POST /api/login` y `POST /api/register`.
///
/// [id] es nulo cuando la sesión se restaura desde el almacenamiento local: el backend
/// aún no expone un endpoint de "mi perfil", así que se conservan el nombre y el correo
/// que llegaron en el login en vez de inventar un dato.
class Usuario {
  const Usuario({this.id, required this.nombre, required this.email, required this.rol});

  factory Usuario.fromJson(Map<String, dynamic> json) => Usuario(
    id: (json['id'] as num?)?.toInt(),
    nombre: json['nombre']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    rol: json['rol']?.toString() ?? 'cliente',
  );

  final int? id;
  final String nombre;
  final String email;
  final String rol;
}

/// Sesión iniciada: token, rol y datos del usuario.
class Sesion {
  const Sesion({required this.token, required this.rol, required this.usuario});

  final String token;
  final String rol;
  final Usuario usuario;
}

/// Llamadas de autenticación contra la API (`spec.md 3.1`).
class AuthRepository {
  const AuthRepository(this._dio, this._storage);

  final Dio _dio;
  final TokenStorage _storage;

  Future<Sesion> login({required String email, required String password}) {
    return _autenticar('/api/login', data: {'email': email, 'password': password});
  }

  /// El registro siempre crea rol `cliente`: el rol no viaja en el cuerpo.
  Future<Sesion> register({
    required String nombre,
    required String email,
    required String password,
  }) {
    return _autenticar(
      '/api/register',
      data: {'name': nombre, 'email': email, 'password': password},
    );
  }

  /// Cierre de sesión: se avisa al backend y se borra el token local.
  ///
  /// El `POST /api/logout` es un no-op (el JWT es stateless), pero se llama para seguir
  /// el contrato de la API; si falla, el cierre local se completa igual, porque dejar al
  /// usuario "dentro" en su propio teléfono sería el peor resultado (HEUR-3).
  Future<void> logout() async {
    try {
      await _dio.post<void>('/api/logout');
    } on DioException {
      // El token puede estar vencido: cerrar sesión local sigue siendo lo correcto.
    }
    await _storage.clear();
  }

  /// Recupera la sesión guardada al abrir la app (el token sigue siendo válido 12 h).
  Future<Sesion?> restaurar() async {
    final token = await _storage.accessToken;
    if (token == null || token.isEmpty) return null;
    final nombre = await _storage.nombre;
    final email = await _storage.email;
    if (nombre == null || email == null) return null;
    return Sesion(
      token: token,
      rol: await _storage.rol ?? 'cliente',
      usuario: Usuario(nombre: nombre, email: email, rol: await _storage.rol ?? 'cliente'),
    );
  }

  Future<Sesion> _autenticar(String ruta, {required Map<String, dynamic> data}) async {
    late final Map<String, dynamic> cuerpo;
    try {
      final respuesta = await _dio.post<Map<String, dynamic>>(ruta, data: data);
      cuerpo = respuesta.data ?? const {};
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }

    final token = cuerpo['access_token']?.toString() ?? '';
    final rol = cuerpo['rol']?.toString() ?? 'cliente';
    if (token.isEmpty) {
      throw ApiException(500, 'La sesión no pudo iniciarse.');
    }

    final usuarioJson = cuerpo['usuario'];
    final usuario = usuarioJson is Map
        ? Usuario.fromJson(Map<String, dynamic>.from(usuarioJson))
        : Usuario(nombre: '', email: '', rol: rol);

    await _storage.saveSession(
      token: token,
      rol: rol,
      nombre: usuario.nombre,
      email: usuario.email,
    );
    return Sesion(token: token, rol: rol, usuario: usuario);
  }
}

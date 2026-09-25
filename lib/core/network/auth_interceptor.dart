import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// Adjunta el token JWT en cada request (Authorization: Bearer) y avisa cuando el token
/// ya no sirve.
///
/// Un `401` en una petición **que llevaba token** significa que la sesión venció (12 h) o
/// que la cuenta se desactivó: la app cierra la sesión local y vuelve al login en vez de
/// dejar al usuario en una pantalla que no va a responder. Un `401` en el login o el
/// registro no dispara nada, porque ahí el `401` es "credenciales incorrectas" y la
/// respuesta correcta es mostrar el error, no cerrar sesión.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage, {required this.onSesionExpirada});

  final TokenStorage _storage;
  final void Function() onSesionExpirada;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (sesionExpirada(err)) onSesionExpirada();
    handler.next(err);
  }
}

/// ¿Este error significa que la sesión del usuario ya no vale?
///
/// Sólo el `401` de una petición que **llevaba token** cuenta. Un `401` en el login o el
/// registro son credenciales incorrectas —ahí la respuesta correcta es mostrar el error, no
/// cerrar sesión— y un `403` es una falta de permisos, que no se arregla relogueando.
bool sesionExpirada(DioException err) {
  final llevabaToken = err.requestOptions.headers['Authorization'] != null;
  return err.response?.statusCode == 401 && llevabaToken;
}

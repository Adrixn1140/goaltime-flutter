import 'dart:convert';

import 'package:dio/dio.dart';

/// Error de negocio que devuelve la API, ya traducido a la forma que la app muestra.
///
/// La API tiene un único formato de error (`spec.md 4`):
///
///     {"error": {"codigo": 409, "mensaje": "Ese horario ya está reservado"}}
///
/// [mensaje] viene redactado en español y apto para el usuario (HEUR-2, HEUR-9), así que
/// la app lo muestra tal cual en vez de inventar su propio texto por código. Lo que sí
/// aporta la app es la *siguiente acción*: [accionSugerida] convierte el código en una
/// recomendación (reintentar, refrescar la disponibilidad, volver a iniciar sesión).
class ApiException implements Exception {
  ApiException(this.codigo, this.mensaje, {this.accionSugerida});

  /// Construye la excepción desde el cuerpo JSON de la API.
  ///
  /// Si el cuerpo no trae la forma esperada se cae al mensaje genérico de [status], para
  /// que un error inesperado (HTML de un proxy, por ejemplo) nunca se muestre crudo.
  factory ApiException.fromResponse(int? status, Object? cuerpo) {
    if (cuerpo is Map && cuerpo['error'] is Map) {
      final error = cuerpo['error'] as Map;
      final codigo = (error['codigo'] as num?)?.toInt() ?? status ?? 0;
      final mensaje = error['mensaje']?.toString().trim();
      return ApiException(
        codigo,
        (mensaje == null || mensaje.isEmpty) ? _generico(status) : mensaje,
        accionSugerida: _accion(codigo),
      );
    }
    return ApiException(status ?? 0, _generico(status), accionSugerida: _accion(status));
  }

  /// Traduce cualquier fallo de [dio] al error que la pantalla debe mostrar.
  ///
  /// Un corte de red no es un error de negocio: se distingue del resto para poder
  /// ofrecer "reintentar" en lugar de culpar al usuario (HEUR-9).
  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    if (response != null) {
      final cuerpo = response.data is String
          ? _intentarParsear(response.data as String)
          : response.data;
      return ApiException.fromResponse(response.statusCode, cuerpo);
    }

    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => ApiException(
        0,
        'El servidor tardó demasiado en responder.',
        accionSugerida: 'Revisa tu conexión e inténtalo de nuevo.',
      ),
      DioExceptionType.connectionError => ApiException(
        0,
        'No pudimos conectar con el servidor.',
        accionSugerida: 'Verifica que estés en la misma red e inténtalo de nuevo.',
      ),
      DioExceptionType.cancel => ApiException(0, 'La operación se canceló.'),
      _ => ApiException(
        0,
        'Ocurrió un problema inesperado.',
        accionSugerida: 'Inténtalo de nuevo.',
      ),
    };
  }

  final int codigo;
  final String mensaje;
  final String? accionSugerida;

  /// `true` si el error es de sesión: la app debe volver al login.
  bool get esSesion => codigo == 401;

  /// `true` si el slot se llenó mientras el usuario decidía (HEUR-5: el 409 se explica).
  bool get esConflicto => codigo == 409;

  /// `true` si el backend rechazó la regla de negocio (fecha pasada, día sin horario…).
  bool get esReglaNegocio => codigo == 422;

  /// `true` si vale la pena reintentar sin cambiar nada.
  bool get esReintentable => codigo >= 500 || (codigo == 0 && accionSugerida != null);

  /// Texto completo para un `SnackBar`: mensaje + siguiente paso cuando existe.
  String get texto => accionSugerida == null ? mensaje : '$mensaje $accionSugerida';

  @override
  String toString() => 'ApiException($codigo): $mensaje';

  static Object? _intentarParsear(String cuerpo) {
    try {
      return jsonDecode(cuerpo);
    } on FormatException {
      return null;
    }
  }

  static String _generico(int? status) => switch (status) {
    400 => 'La solicitud no es válida.',
    401 => 'Tu sesión no es válida.',
    403 => 'No tienes permisos para esta operación.',
    404 => 'El recurso solicitado no existe.',
    409 => 'La operación entra en conflicto con el estado actual.',
    413 => 'El contenido enviado supera el tamaño permitido.',
    422 => 'Los datos enviados no son válidos.',
    500 => 'El servidor tuvo un problema.',
    _ => 'No pudimos completar la operación.',
  };

  static String? _accion(int? codigo) => switch (codigo) {
    401 => 'Vuelve a iniciar sesión.',
    403 => 'Si crees que es un error, habla con el administrador.',
    404 => 'Actualiza la lista para ver los datos actuales.',
    409 => 'Actualiza la disponibilidad y elige otro horario.',
    422 => 'Elige otra fecha u horario.',
    _ => null,
  };
}

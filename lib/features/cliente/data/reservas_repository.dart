import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import 'models.dart';

/// Reservas y pagos del cliente (`spec.md 3.2` y `3.3`).
///
/// El monto nunca se envía: lo calcula el backend desde `horario.tarifa`. Aquí sólo
/// viajan los identificadores que el usuario eligió, y el precio mostrado antes de
/// confirmar es el mismo que la API va a cobrar.
class ReservasRepository {
  const ReservasRepository(this._dio);

  final Dio _dio;

  /// Reserva el slot. Devuelve la reserva `pendiente_pago` con su pago pendiente.
  ///
  /// Puede lanzar [ApiException] con `409` si el slot se llenó mientras el usuario
  /// decidía, o `422` si la fecha ya pasó o la cancha no atiende ese día.
  Future<ReservaCreada> reservar({
    required int canchaId,
    required int horarioId,
    required String fecha,
  }) async {
    final cuerpo = await _post<Map<String, dynamic>>(
      '/api/reservas',
      data: {'cancha_id': canchaId, 'horario_id': horarioId, 'fecha': fecha},
    );
    return ReservaCreada.fromJson(cuerpo);
  }

  /// Historial del cliente. El filtro por usuario lo aplica el backend a partir del
  /// token: la app nunca envía un id de cliente.
  Future<List<Reserva>> misReservas() async {
    final cuerpo = await _get<List<dynamic>>('/api/mis-reservas');
    return cuerpo
        .map((item) => Reserva.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  /// Abre la sesión de pago en la pasarela y devuelve la URL a la que ir.
  Future<Checkout> abrirCheckout({required int reservaId}) async {
    final cuerpo = await _post<Map<String, dynamic>>(
      '/api/pagos/checkout',
      data: {'reserva_id': reservaId},
    );
    return Checkout.fromJson(cuerpo);
  }

  /// Estado actual del pago: la app lo consulta tras volver del checkout, porque la
  /// confirmación llega por webhook y puede tardar un momento.
  Future<Pago> consultarPago(int pagoId) async {
    final cuerpo = await _get<Map<String, dynamic>>('/api/pagos/$pagoId');
    return Pago.fromJson(cuerpo);
  }

  /// Cierra el pago sin pasarela externa. Sólo existe con `PAGADORA=mock`; con Stripe el
  /// backend responde `403`, y por eso la app sólo ofrece la acción cuando el pago es
  /// simulado ([Pago.esSimulado]).
  Future<ResultadoPago> simularPago({required int pagoId, required bool aprobado}) async {
    final cuerpo = await _post<Map<String, dynamic>>(
      '/api/pagos/$pagoId/simular',
      data: {'resultado': aprobado ? 'aprobado' : 'rechazado'},
    );
    return ResultadoPago.fromJson(cuerpo);
  }

  Future<T> _get<T>(String ruta) => _enviar(() => _dio.get<T>(ruta));

  Future<T> _post<T>(String ruta, {required Object data}) =>
      _enviar(() => _dio.post<T>(ruta, data: data));

  Future<T> _enviar<T>(Future<Response<T>> Function() peticion) async {
    try {
      final respuesta = await peticion();
      return respuesta.data as T;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import 'models.dart';

/// Asistente de reserva por lenguaje natural (`spec.md 3.6`).
///
/// Una llamada que recibe una frase y devuelve el texto del asistente más las
/// sugerencias con `horario_id` real. El asistente no reserva ni cobra: sugerir y
/// confirmar son dos pasos distintos, y la confirmación vive en [ReservasRepository].
class AsistenteRepository {
  const AsistenteRepository(this._dio);

  final Dio _dio;

  Future<RespuestaAsistente> consultar({required String mensaje}) async {
    final cuerpo = await _post<Map<String, dynamic>>(
      '/api/asistente',
      data: {'mensaje': mensaje},
    );
    return RespuestaAsistente.fromJson(cuerpo);
  }

  Future<T> _post<T>(String ruta, {required Object data}) async {
    try {
      final respuesta = await _dio.post<T>(ruta, data: data);
      return respuesta.data as T;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
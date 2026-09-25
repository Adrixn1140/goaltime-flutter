import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import 'models.dart';

/// Catálogo de canchas y disponibilidad de slots (`spec.md 3.2`).
///
/// Ambas consultas son públicas: el cliente las puede pedir sin token, y la
/// disponibilidad devuelve 6 días desde [fechaInicio] con el `motivo` de cada slot no
/// disponible, para que la app deshabilite la opción en vez de dejar que el usuario
/// descubra el `409` al reservar (HEUR-5).
class CanchasRepository {
  const CanchasRepository(this._dio);

  final Dio _dio;

  Future<List<Cancha>> listar() async {
    final cuerpo = await _get<List<dynamic>>('/api/canchas');
    return cuerpo
        .map((item) => Cancha.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<Slot>> disponibilidad({required int canchaId, required String fechaInicio}) async {
    final cuerpo = await _get<List<dynamic>>(
      '/api/disponibilidad',
      query: {'cancha_id': '$canchaId', 'fecha_inicio': fechaInicio},
    );
    return cuerpo
        .map((item) => Slot.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<T> _get<T>(String ruta, {Map<String, dynamic>? query}) async {
    try {
      final respuesta = await _dio.get<T>(ruta, queryParameters: query);
      return respuesta.data as T;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';

class PerfilArbitro {
  const PerfilArbitro({
    required this.id,
    required this.nombre,
    required this.ciudad,
    required this.celular,
    required this.experiencia,
    required this.biografia,
    required this.tarifa,
    required this.disponible,
    required this.publicado,
  });
  final int id, experiencia;
  final String nombre, ciudad, celular, biografia;
  final double tarifa;
  final bool disponible, publicado;

  factory PerfilArbitro.fromJson(Map<String, dynamic> json) => PerfilArbitro(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    ciudad: json['ciudad'] as String,
    celular: json['celular'] as String,
    experiencia: (json['experiencia'] as num).toInt(),
    biografia: json['biografia'] as String,
    tarifa: (json['tarifa'] as num).toDouble(),
    disponible: json['disponible'] as bool,
    publicado: json['publicado'] as bool,
  );
}

class ArbitrosRepository {
  const ArbitrosRepository(this._dio);
  final Dio _dio;

  Future<List<PerfilArbitro>> listar({
    String q = '',
    bool soloDisponibles = false,
  }) async {
    final data = await _solicitar(
      'GET',
      '/api/arbitros',
      query: {
        if (q.isNotEmpty) 'q': q,
        if (soloDisponibles) 'disponible': 'true',
      },
    ) as List;
    return data
        .map((p) => PerfilArbitro.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
  }

  Future<PerfilArbitro?> miPerfil() async {
    final data = await _solicitar('GET', '/api/arbitros/mi-perfil');
    return data == null
        ? null
        : PerfilArbitro.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<PerfilArbitro> guardar(Map<String, dynamic> datos) async =>
      PerfilArbitro.fromJson(
        Map<String, dynamic>.from(
          await _solicitar('PUT', '/api/arbitros/mi-perfil', datos: datos)
              as Map,
        ),
      );

  Future<dynamic> _solicitar(
    String method,
    String ruta, {
    Map<String, dynamic>? datos,
    Map<String, dynamic>? query,
  }) async {
    try {
      final respuesta = await _dio.request<dynamic>(
        ruta,
        data: datos,
        queryParameters: query,
        options: Options(method: method),
      );
      return respuesta.data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';

class Jugador {
  const Jugador({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.documento,
    required this.celular,
  });

  final int id;
  final String nombre, apellido, documento, celular;
  String get nombreCompleto => '$nombre $apellido';
  String get documentoOculto =>
      '••••${documento.substring(documento.length - 4)}';

  factory Jugador.fromJson(Map<String, dynamic> json) => Jugador(
    id: json['id'] as int,
    nombre: json['nombre'] as String,
    apellido: json['apellido'] as String,
    documento: json['documento'] as String,
    celular: json['celular'] as String,
  );
}

class Equipo {
  const Equipo({
    required this.id,
    required this.nombre,
    required this.jugadores,
  });
  final int id;
  final String nombre;
  final List<Jugador> jugadores;

  factory Equipo.fromJson(Map<String, dynamic> json) => Equipo(
    id: json['id'] as int,
    nombre: json['nombre'] as String,
    jugadores: (json['jugadores'] as List)
        .map((j) => Jugador.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList(growable: false),
  );
}

class EquiposRepository {
  const EquiposRepository(this._dio);
  final Dio _dio;

  Future<List<Equipo>> listar() async {
    final data = await _solicitar('GET', '/api/equipos') as List;
    return data
        .map((e) => Equipo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Equipo> detalle(int id) async => Equipo.fromJson(
    Map<String, dynamic>.from(
      await _solicitar('GET', '/api/equipos/$id') as Map,
    ),
  );

  Future<Equipo> crear(String nombre) async => Equipo.fromJson(
    Map<String, dynamic>.from(
      await _solicitar('POST', '/api/equipos', {'nombre': nombre}) as Map,
    ),
  );

  Future<void> agregarJugador(int id, Map<String, String> datos) async {
    await _solicitar('POST', '/api/equipos/$id/jugadores', datos);
  }

  Future<dynamic> _solicitar(
    String metodo,
    String ruta, [
    Map<String, String>? datos,
  ]) async {
    try {
      final respuesta = await _dio.request<dynamic>(
        ruta,
        data: datos,
        options: Options(method: metodo),
      );
      return respuesta.data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

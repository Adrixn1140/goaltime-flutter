import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import 'models.dart';

/// Gestión del dueño sobre sus canchas (`spec.md 3.4`).
///
/// Vive en `/api/gestion/*` y no sobre `/api/canchas` porque el catálogo público no
/// cambia de forma según quién pregunte. Aquí, en cambio, casi todo puede fallar con un
/// `4xx` que vale la pena ver: la cancha de otro dueño es `404`, un horario que se solapa
/// es `422`, uno que ya existe es `409`, y borrar algo con historial es `409`. Los
/// mensajes del backend ya están redactados para el usuario, así que la app los muestra
/// tal cual en vez de inventar su propio texto (HEUR-9).
class GestionRepository {
  const GestionRepository(this._dio);

  final Dio _dio;

  Future<List<CanchaGestion>> listarCanchas() async {
    final cuerpo = await _get<List<dynamic>>('/api/gestion/canchas');
    return _lista(cuerpo, CanchaGestion.fromJson);
  }

  Future<CanchaGestion> crearCancha({required String nombre, required String ubicacion}) async {
    final cuerpo = await _post<Map<String, dynamic>>(
      '/api/gestion/canchas',
      data: {'nombre': nombre, 'ubicacion': ubicacion},
    );
    return CanchaGestion.fromJson(cuerpo);
  }

  /// Envía sólo los campos que se editaron: el backend aplica un `PATCH` parcial, así que
  /// mandarle un campo que no cambió lo pisaría con un valor vacío.
  Future<CanchaGestion> actualizarCancha(
    int canchaId, {
    String? nombre,
    String? ubicacion,
    bool? activo,
  }) async {
    final data = <String, dynamic>{};
    if (nombre != null) data['nombre'] = nombre;
    if (ubicacion != null) data['ubicacion'] = ubicacion;
    if (activo != null) data['activo'] = activo;
    final cuerpo = await _patch<Map<String, dynamic>>('/api/gestion/canchas/$canchaId', data: data);
    return CanchaGestion.fromJson(cuerpo);
  }

  /// Baja lógica: el backend responde `204` y la cancha sigue existiendo.
  Future<void> bajarCancha(int canchaId) => _delete('/api/gestion/canchas/$canchaId');

  Future<List<HorarioCancha>> listarHorarios(int canchaId) async {
    final cuerpo = await _get<List<dynamic>>('/api/gestion/canchas/$canchaId/horarios');
    return _lista(cuerpo, HorarioCancha.fromJson);
  }

  Future<HorarioCancha> crearHorario(
    int canchaId, {
    required int dia,
    required String horaInicio,
    required String horaFin,
    required double tarifa,
  }) async {
    final cuerpo = await _post<Map<String, dynamic>>(
      '/api/gestion/canchas/$canchaId/horarios',
      data: {
        'dia': dia,
        'hora_inicio': horaInicio,
        'hora_fin': horaFin,
        'tarifa': tarifa,
      },
    );
    return HorarioCancha.fromJson(cuerpo);
  }

  Future<HorarioCancha> actualizarHorario(
    int canchaId,
    int horarioId, {
    int? dia,
    String? horaInicio,
    String? horaFin,
    double? tarifa,
  }) async {
    final data = <String, dynamic>{};
    if (dia != null) data['dia'] = dia;
    if (horaInicio != null) data['hora_inicio'] = horaInicio;
    if (horaFin != null) data['hora_fin'] = horaFin;
    if (tarifa != null) data['tarifa'] = tarifa;
    final cuerpo = await _patch<Map<String, dynamic>>(
      '/api/gestion/canchas/$canchaId/horarios/$horarioId',
      data: data,
    );
    return HorarioCancha.fromJson(cuerpo);
  }

  Future<void> borrarHorario(int canchaId, int horarioId) =>
      _delete('/api/gestion/canchas/$canchaId/horarios/$horarioId');

  Future<List<ReservaGestion>> listarReservas(int canchaId) async {
    final cuerpo = await _get<List<dynamic>>('/api/gestion/canchas/$canchaId/reservas');
    return _lista(cuerpo, ReservaGestion.fromJson);
  }

  /// Confirma o cancela. `accion` viaja tal cual la entiende el servidor (`confirmar`,
  /// `cancelar`); un `422` aquí significa que la reserva ya no está en el estado que
  /// permite la acción, y la app refresca para mostrar el estado real.
  Future<ReservaGestion> cambiarEstadoReserva(int reservaId, String accion) async {
    final cuerpo = await _patch<Map<String, dynamic>>(
      '/api/gestion/reservas/$reservaId',
      data: {'accion': accion},
    );
    return ReservaGestion.fromJson(cuerpo);
  }

  List<T> _lista<T>(List<dynamic> cuerpo, T Function(Map<String, dynamic>) construir) =>
      cuerpo.map((item) => construir(Map<String, dynamic>.from(item as Map))).toList(growable: false);

  Future<T> _get<T>(String ruta) => _enviar(() => _dio.get<T>(ruta));

  Future<T> _post<T>(String ruta, {required Object data}) =>
      _enviar(() => _dio.post<T>(ruta, data: data));

  Future<T> _patch<T>(String ruta, {required Object data}) =>
      _enviar(() => _dio.patch<T>(ruta, data: data));

  Future<void> _delete(String ruta) => _enviar(() async => _dio.delete<void>(ruta));

  Future<T> _enviar<T>(Future<Response<T>> Function() peticion) async {
    try {
      final respuesta = await peticion();
      return respuesta.data as T;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

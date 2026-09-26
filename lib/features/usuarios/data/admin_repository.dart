import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import 'models.dart';

/// Panel de admin (`spec.md 3.5`).
///
/// A diferencia de la gestión del dueño, aquí casi todo puede terminar en un `422` con
/// un mensaje que el admin necesita leer entero: "no puedes cambiarte el rol a ti
/// mismo", "baja primero sus 2 canchas activas". La app los muestra tal cual, sin
/// traducirlos, porque cualquier traducción perdería el número o el quién (HEUR-9).
class AdminRepository {
  const AdminRepository(this._dio);

  final Dio _dio;

  Future<List<UsuarioAdmin>> listarUsuarios() async {
    final cuerpo = await _get<Map<String, dynamic>>('/api/usuarios');
    final usuarios = cuerpo['usuarios'];
    if (usuarios is! List) return const [];
    return usuarios
        .whereType<Map>()
        .map((item) => UsuarioAdmin.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  /// Cambia el rol, el estado activo, o los dos. Los campos que no se mandan no se tocan:
  /// el backend aplica un `PATCH` parcial, así que mandar `rol: null` cuando sólo se quería
  /// activar la cuenta acabaría quitándole el rol.
  Future<UsuarioAdmin> cambiarRol(int usuarioId, {RolUsuario? rol, bool? activo}) async {
    final data = <String, dynamic>{};
    if (rol != null) data['rol'] = rol.codigo;
    if (activo != null) data['activo'] = activo;
    final cuerpo = await _patch<Map<String, dynamic>>('/api/usuarios/$usuarioId/rol', data: data);
    return UsuarioAdmin.fromJson(cuerpo);
  }

  Future<ReporteAdmin> reporte() async {
    final cuerpo = await _get<Map<String, dynamic>>('/api/reporte');
    return ReporteAdmin.fromJson(cuerpo);
  }

  Future<T> _get<T>(String ruta) => _enviar(() => _dio.get<T>(ruta));

  Future<T> _patch<T>(String ruta, {required Object data}) =>
      _enviar(() => _dio.patch<T>(ruta, data: data));

  Future<T> _enviar<T>(Future<Response<T>> Function() peticion) async {
    try {
      final respuesta = await peticion();
      return respuesta.data as T;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goaltime_flutter/core/app.dart';
import 'package:goaltime_flutter/core/network/api_client.dart';
import 'package:goaltime_flutter/core/storage/token_storage.dart';

/// La app completa, montada contra la [FakeApi] en vez de la red.
///
/// Se apoya en `crearApiClient` —el mismo constructor que usa producción— y sólo cambia
/// el adaptador HTTP. Así los tests atraviesan el interceptor de token de verdad; si cada
/// test se armara su propio `Dio` pelado, esa pieza quedaría sin probar justo en los
/// flujos donde importa, que son todos los que llevan sesión.
Widget appDePrueba(FakeApi api, {TokenStorage? storage}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWith((ref) {
        final dio = crearApiClient(
          storage: ref.watch(tokenStorageProvider),
          onSesionExpirada: () => ref.read(sesionExpiradaProvider.notifier).notificar(),
        );
        dio.httpClientAdapter = FakeAdapter(api);
        return dio;
      }),
      tokenStorageProvider.overrideWithValue(storage ?? sesuraDePrueba()),
    ],
    child: const App(),
  );
}

/// Un [Dio] que responde desde una tabla de rutas, sin tocar la red.
///
/// Los tests de UI necesitan el backend de verdad (los mismos repositorios y providers);
/// lo que no pueden es abrir un socket. Este adaptador implementa justo el contrato que
/// el código exercises: rutas, cuerpos, errores con el formato del backend y el token.
class FakeApi {
  FakeApi();

  final Map<String, _Respuesta> _rutas = {};

  /// Peticiones registradas, para afirmar el orden y el cuerpo de lo que se envió.
  final List<String> peticiones = [];

  /// Fallo programado para la próxima petición a una ruta. Al consumirse se borra solo:
  /// la respuesta normal de la ruta vuelve a estar vigente.
  final Map<String, _Respuesta> _fallanLaProxima = {};

  /// Acciones que se disparan al recibir una petición. Sirven para encadenar estados que
  /// en el backend son consecuencia uno de otro: al confirmar el pago, la lista de
  /// reservas vuelve con la reserva ya confirmada.
  final List<({String clave, void Function(FakeApi api) accion})> _alRecibir = [];

  void alRecibir(String metodo, String ruta, void Function(FakeApi api) accion) {
    _alRecibir.add((clave: '${metodo.toUpperCase()} $ruta', accion: accion));
  }

  void responder(String metodo, String ruta, Object cuerpo, {int status = 200}) {
    _rutas['${metodo.toUpperCase()} $ruta'] = _Respuesta(cuerpo, status);
  }

  /// Error con el formato único de la API: `codigo` es el status HTTP y `mensaje` va
  /// redactado para el usuario final (`errors.py`).
  void error(String metodo, String ruta, int status, String mensaje) {
    _rutas['${metodo.toUpperCase()} $ruta'] = _errorFalso(status, mensaje);
  }

  /// Programa un fallo para la **siguiente** petición, sin tocar la respuesta normal.
  ///
  /// Hace falta así porque Riverpod reintenta solo los providers que fallan: si la ruta
  /// quedara en 503 para siempre, el "reintentar" del usuario no se podría distinguir de
  /// un backend caído de verdad.
  void fallarLaProxima(String metodo, String ruta, int status, String mensaje) {
    _fallanLaProxima['${metodo.toUpperCase()} $ruta'] = _errorFalso(status, mensaje);
  }

  /// Adaptador de red falso listo para asignar a un `Dio` ya configurado.
  ///
  /// Preferible a [construir]: si el test arma su propio `Dio` se queda sin el
  /// interceptor de token, que es justo lo que hay que comprobar en un flujo autenticado.
  HttpClientAdapter get adaptador => FakeAdapter(this);

  Dio construir() {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    dio.httpClientAdapter = adaptador;
    return dio;
  }

  Future<ResponseBody> _responder(RequestOptions options) async {
    final clave = '${options.method} ${options.path}';
    peticiones.add(
      options.data == null ? clave : '$clave ${jsonEncode(options.data)}',
    );

    for (final regla in [..._alRecibir]) {
      if (regla.clave == clave) regla.accion(this);
    }

    final fallo = _fallanLaProxima.remove(clave);
    final respuesta = fallo ?? _rutas[clave];
    if (respuesta == null) {
      return ResponseBody.fromString(
        jsonEncode({
          'error': {'codigo': 404, 'mensaje': 'Sin respuesta para $clave'},
        }),
        404,
        headers: _json,
      );
    }

    return ResponseBody.fromString(
      jsonEncode(respuesta.cuerpo),
      respuesta.status,
      headers: _json,
    );
  }

  static _Respuesta _errorFalso(int status, String mensaje) => _Respuesta(
    {
      'error': {'codigo': status, 'mensaje': mensaje},
    },
    status,
  );

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };
}

class _Respuesta {
  const _Respuesta(this.cuerpo, this.status);

  final Object cuerpo;
  final int status;
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._api);

  final FakeApi _api;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _api._responder(options);
}

/// TokenStorage en memoria con la sesión ya iniciada, para las pantallas que requieren
/// estar dentro de la app.
TokenStorage sesuraDePrueba({String rol = 'cliente', String nombre = 'Ana Cliente', String email = 'ana@correo.com'}) {
  return TokenStorage(
    MemoriaSegura({
      'access_token': 'token-de-prueba',
      'rol': rol,
      'nombre': nombre,
      'email': email,
    }),
  );
}

/// Catálogo mínimo que usan casi todos los tests de cliente.
void canchasDePrueba(FakeApi api) {
  api.responder('GET', '/api/canchas', [
    {
      'id': 1,
      'nombre': 'Cancha El Retiro',
      'ubicacion': 'Cra 45 # 12-30',
      'foto': '',
      'tarifa_base': 60000.0,
    },
    {
      'id': 2,
      'nombre': 'Cancha Laquina',
      'ubicacion': 'Av 6 # 78-10',
      'foto': '',
      'tarifa_base': 45000.0,
    },
  ]);
}

/// Disponibilidad de la cancha 1: un slot libre, uno ocupado y uno ya pasado.
void disponibilidadDePrueba(FakeApi api) {
  api.responder('GET', '/api/disponibilidad', [
    {
      'horario_id': 10,
      'fecha': _hoy(),
      'hora_inicio': '08:00',
      'hora_fin': '10:00',
      'tarifa': 60000.0,
      'disponible': false,
      'motivo': 'transcurrido',
    },
    {
      'horario_id': 11,
      'fecha': _hoy(),
      'hora_inicio': '14:00',
      'hora_fin': '16:00',
      'tarifa': 60000.0,
      'disponible': true,
      'motivo': null,
    },
    {
      'horario_id': 12,
      'fecha': _manana(),
      'hora_inicio': '08:00',
      'hora_fin': '10:00',
      'tarifa': 65000.0,
      'disponible': true,
      'motivo': null,
    },
  ]);
}

String _hoy() {
  final hoy = DateTime.now();
  return '${hoy.year.toString().padLeft(4, '0')}-'
      '${hoy.month.toString().padLeft(2, '0')}-'
      '${hoy.day.toString().padLeft(2, '0')}';
}

String _manana() {
  final manana = DateTime.now().add(const Duration(days: 1));
  return '${manana.year.toString().padLeft(4, '0')}-'
      '${manana.month.toString().padLeft(2, '0')}-'
      '${manana.day.toString().padLeft(2, '0')}';
}

/// Reserva pendiente de pago de la cancha 1.
Map<String, Object> reservaDePrueba({String estado = 'pendiente_pago', String pago = 'pendiente'}) {
  return {
    'reserva_id': 7,
    'cancha': {'id': 1, 'nombre': 'Cancha El Retiro', 'ubicacion': 'Cra 45 # 12-30'},
    'horario': {'id': 11, 'hora_inicio': '14:00', 'hora_fin': '16:00', 'tarifa': 60000.0},
    'fecha': _hoy(),
    'estado': estado,
    'pago': {'id': 9, 'reserva_id': 7, 'monto': 60000.0, 'metodo': 'mock', 'estado': pago},
  };
}

// --- Datos de la gestión del dueño ---------------------------------------------

/// Canchas del dueño, como las devuelve `GET /api/gestion/canchas`.
void canchasDeGestion(FakeApi api) {
  api.responder('GET', '/api/gestion/canchas', [
    _canchaGestion(1, 'Cancha El Retiro', horarios: 2, tarifa: 45000.0),
    _canchaGestion(2, 'Cancha Laquina', horarios: 0, activa: false),
  ]);
}

Map<String, Object> _canchaGestion(
  int id,
  String nombre, {
  int horarios = 1,
  double? tarifa = 60000.0,
  bool activa = true,
}) {
  return {
    'id': id,
    'nombre': nombre,
    'ubicacion': 'Cra 45 # 12-30',
    'foto': '',
    'activo': activa,
    'dueno_id': 5,
    'total_horarios': horarios,
    'tarifa_base': tarifa ?? 0.0,
  };
}

/// Horarios de la cancha 1, uno de lunes y otro de miércoles.
void horariosDePrueba(FakeApi api) {
  api.responder('GET', '/api/gestion/canchas/1/horarios', [
    {'id': 10, 'cancha_id': 1, 'dia': 0, 'hora_inicio': '08:00', 'hora_fin': '10:00', 'tarifa': 60000.0},
    {'id': 11, 'cancha_id': 1, 'dia': 2, 'hora_inicio': '16:00', 'hora_fin': '18:00', 'tarifa': 55000.0},
  ]);
}

/// Reservas de la cancha 1: una pagada por confirmar, otra sin pagar y otra cancelada.
void reservasDeGestion(FakeApi api) {
  api.responder('GET', '/api/gestion/canchas/1/reservas', [
    _reservaGestion(id: 21, cliente: 'Carla Cliente', estado: 'pendiente_pago', pago: 'aprobado'),
    _reservaGestion(id: 22, cliente: 'Julián Pérez', estado: 'pendiente_pago', pago: 'pendiente'),
    _reservaGestion(id: 23, cliente: 'Ana Ruiz', estado: 'cancelada', pago: 'rechazado'),
  ]);
}

Map<String, Object> _reservaGestion({
  required int id,
  required String cliente,
  required String estado,
  required String pago,
}) {
  return {
    'reserva_id': id,
    'cancha': {'id': 1, 'nombre': 'Cancha El Retiro', 'ubicacion': 'Cra 45 # 12-30', 'activo': true},
    'horario': {'id': 10, 'hora_inicio': '08:00', 'hora_fin': '10:00', 'tarifa': 60000.0},
    'cliente': {'id': id * 3, 'nombre': cliente},
    'fecha': _manana(),
    'estado': estado,
    'pago': {'id': id * 2, 'reserva_id': id, 'monto': 60000.0, 'metodo': 'mock', 'estado': pago},
  };
}

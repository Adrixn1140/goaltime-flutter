/// Modelos del asistente de reserva por lenguaje natural (`spec.md 3.6`).
///
/// La respuesta de `POST /api/asistente` es texto más una lista de sugerencias. Las
/// sugerencias llegan con su `horario_id` real (salido de una consulta a la base, nunca
/// de una inferencia del modelo) y son justo lo que la app ofrece como botón: confirmar
/// es pasárselas a `POST /api/reservas`, que es el único camino que reserva.
library;

/// Una opción de reserva que devolvió el asistente.
///
/// Todos los campos son reales y libres en el momento de la respuesta; el `horario_id`
/// es el que la confirmación tiene que mandar. `tarifa` está en pesos colombianos.
class SugerenciaAsistente {
  const SugerenciaAsistente({
    required this.canchaId,
    required this.cancha,
    required this.fecha,
    required this.horarioId,
    required this.horaInicio,
    required this.horaFin,
    required this.tarifa,
  });

  factory SugerenciaAsistente.fromJson(Map<String, dynamic> json) => SugerenciaAsistente(
    canchaId: (json['cancha_id'] as num).toInt(),
    cancha: json['cancha']?.toString() ?? '',
    fecha: json['fecha']?.toString() ?? '',
    horarioId: (json['horario_id'] as num).toInt(),
    horaInicio: json['hora_inicio']?.toString() ?? '',
    horaFin: json['hora_fin']?.toString() ?? '',
    tarifa: (json['tarifa'] as num?)?.toDouble() ?? 0,
  );

  final int canchaId;
  final String cancha;
  final String fecha;
  final int horarioId;
  final String horaInicio;
  final String horaFin;
  final double tarifa;

  String get rango => '$horaInicio – $horaFin';
}

/// Respuesta completa de `POST /api/asistente`.
///
/// `sugerencias` vacías **no** son un error: el asistente pudo responder un saludo, o no
/// haber encontrado la cancha que pidieron. La capa de presentación decide qué mostrar
/// según la cantidad de opciones, no según un código.
class RespuestaAsistente {
  const RespuestaAsistente({
    required this.respuesta,
    required this.sugerencias,
    required this.motor,
  });

  factory RespuestaAsistente.fromJson(Map<String, dynamic> json) {
    final lista = json['sugerencias'];
    return RespuestaAsistente(
      respuesta: json['respuesta']?.toString() ?? '',
      sugerencias: lista is List
          ? lista
              .whereType<Map>()
              .map((item) => SugerenciaAsistente.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
      motor: json['motor']?.toString() ?? '',
    );
  }

  final String respuesta;
  final List<SugerenciaAsistente> sugerencias;

  /// `mock`, `ollama` o `gemini` (spec.md 3.6).
  final String motor;
}
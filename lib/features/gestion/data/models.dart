/// Modelos de la gestión del dueño (`spec.md 3.4`).
///
/// Son distintos de los del cliente a propósito: aquí la cancha trae `activo`,
/// `dueno_id` y `total_horarios`, y la reserva trae **quién** reservó. Reutilizar el
/// modelo público obligaría a la app a adivinar qué campos vienen y cuáles no, y un
/// `null` silencioso en un campo de gestión es un dato que el dueño no ve.
library;

import '../../cliente/data/models.dart' show EstadoPago, EstadoReserva;

/// Cancha en la gestión del dueño (`GET /api/gestion/canchas`).
class CanchaGestion {
  const CanchaGestion({
    required this.id,
    required this.nombre,
    required this.ubicacion,
    required this.activo,
    required this.totalHorarios,
    this.foto = '',
    this.tarifaBase,
  });

  factory CanchaGestion.fromJson(Map<String, dynamic> json) => CanchaGestion(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre']?.toString() ?? '',
    ubicacion: json['ubicacion']?.toString() ?? '',
    foto: json['foto']?.toString() ?? '',
    activo: json['activo'] != false,
    totalHorarios: (json['total_horarios'] as num?)?.toInt() ?? 0,
    tarifaBase: (json['tarifa_base'] as num?)?.toDouble(),
  );

  final int id;
  final String nombre;
  final String ubicacion;
  final String foto;

  /// `false` en una cancha dada de baja: sigue existiendo con su historial, pero ya no
  /// aparece en el catálogo público.
  final bool activo;

  /// Cuántos horarios tiene definidos. `0` es la señal de que la cancha aún no está
  /// lista para recibir reservas, y por eso la tarjeta lo dice en vez de dejar que el
  /// dueño lo descubra cuando un cliente pregunta.
  final int totalHorarios;

  /// Precio "desde": el mínimo entre sus horarios. `null` si no tiene ninguno.
  final double? tarifaBase;
}

/// Horario de una cancha (`GET /api/gestion/canchas/{id}/horarios`).
class HorarioCancha {
  const HorarioCancha({
    required this.id,
    required this.dia,
    required this.horaInicio,
    required this.horaFin,
    required this.tarifa,
  });

  factory HorarioCancha.fromJson(Map<String, dynamic> json) => HorarioCancha(
    id: (json['id'] as num).toInt(),
    dia: (json['dia'] as num?)?.toInt() ?? 0,
    horaInicio: json['hora_inicio']?.toString() ?? '',
    horaFin: json['hora_fin']?.toString() ?? '',
    tarifa: (json['tarifa'] as num?)?.toDouble() ?? 0,
  );

  final int id;

  /// `0` lunes … `6` domingo, el mismo convenio del backend.
  final int dia;
  final String horaInicio;
  final String horaFin;
  final double tarifa;

  String get rango => '$horaInicio – $horaFin';
}

/// Reserva de una cancha vista por el dueño
/// (`GET /api/gestion/canchas/{id}/reservas`).
class ReservaGestion {
  const ReservaGestion({
    required this.id,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.tarifa,
    required this.estado,
    required this.nombreCliente,
    this.estadoPago,
  });

  factory ReservaGestion.fromJson(Map<String, dynamic> json) {
    final horarioJson = Map<String, dynamic>.from((json['horario'] as Map?) ?? const {});
    final clienteJson = Map<String, dynamic>.from((json['cliente'] as Map?) ?? const {});
    final pagoJson = json['pago'];
    return ReservaGestion(
      id: (json['reserva_id'] as num).toInt(),
      fecha: json['fecha']?.toString() ?? '',
      horaInicio: horarioJson['hora_inicio']?.toString() ?? '',
      horaFin: horarioJson['hora_fin']?.toString() ?? '',
      tarifa: (horarioJson['tarifa'] as num?)?.toDouble() ?? 0,
      estado: _estadoReserva(json['estado']?.toString()),
      nombreCliente: clienteJson['nombre']?.toString() ?? 'Cliente',
      estadoPago: pagoJson is Map ? _estadoPago(pagoJson['estado']?.toString()) : null,
    );
  }

  final int id;
  final String fecha;
  final String horaInicio;
  final String horaFin;
  final double tarifa;
  final EstadoReserva estado;
  final String nombreCliente;
  final EstadoPago? estadoPago;

  String get rango => '$horaInicio – $horaFin';

  /// El backend exige pago aprobado para confirmar. La app calcula lo mismo para no
  /// ofrecer un botón que el servidor va a rechazar: el motivo del rechazo se muestra en
  /// la tarjeta, no se descubre tras un intento fallido (HEUR-5, HEUR-9).
  bool get puedeConfirmar => estado == EstadoReserva.pendientePago && estadoPago == EstadoPago.aprobado;

  /// Cancelar deja de tener sentido en cuanto la reserva está cancelada: el botón
  /// desaparece en vez de dejar que el backend responda `422`.
  bool get puedeCancelar => estado != EstadoReserva.cancelada;

  /// Por qué no se puede confirmar, en una frase. `null` cuando sí se puede.
  String? get motivoSinConfirmar {
    if (puedeConfirmar) return null;
    if (estado == EstadoReserva.pendientePago) return 'El pago no está aprobado todavía';
    return null;
  }
}

EstadoReserva _estadoReserva(String? codigo) => switch (codigo) {
  'confirmada' => EstadoReserva.confirmada,
  'cancelada' => EstadoReserva.cancelada,
  _ => EstadoReserva.pendientePago,
};

EstadoPago _estadoPago(String? codigo) => switch (codigo) {
  'aprobado' => EstadoPago.aprobado,
  'rechazado' => EstadoPago.rechazado,
  _ => EstadoPago.pendiente,
};

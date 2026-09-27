/// Modelos del dominio que consume el cliente.
///
/// Son inmutables y se construyen desde el JSON de la API con factorías `fromJson`: la
/// capa de presentación nunca ve un `Map`. Los enums usan el mismo vocabulario que los
/// catálogos del backend (`spec.md 2`), y un valor desconocido cae en un caso explícito
/// en vez de romper la pantalla.
library;

// --- Catálogos ---------------------------------------------------------------

enum EstadoReserva { pendientePago, confirmada, cancelada }

enum EstadoPago { pendiente, aprobado, rechazado }

/// Motivos por los que un slot no es seleccionable (`spec.md 3.2`).
enum MotivoSlot { ocupado, transcurrido }

extension EstadoReservaX on EstadoReserva {
  String get codigo => switch (this) {
    EstadoReserva.pendientePago => 'pendiente_pago',
    EstadoReserva.confirmada => 'confirmada',
    EstadoReserva.cancelada => 'cancelada',
  };

  String get etiqueta => switch (this) {
    EstadoReserva.pendientePago => 'Pendiente de pago',
    EstadoReserva.confirmada => 'Confirmada',
    EstadoReserva.cancelada => 'Cancelada',
  };
}

extension EstadoPagoX on EstadoPago {
  String get codigo => switch (this) {
    EstadoPago.pendiente => 'pendiente',
    EstadoPago.aprobado => 'aprobado',
    EstadoPago.rechazado => 'rechazado',
  };

  String get etiqueta => switch (this) {
    EstadoPago.pendiente => 'Pendiente',
    EstadoPago.aprobado => 'Aprobado',
    EstadoPago.rechazado => 'Rechazado',
  };
}

extension MotivoSlotX on MotivoSlot {
  String get etiqueta => switch (this) {
    MotivoSlot.ocupado => 'Ocupado',
    MotivoSlot.transcurrido => 'Ya pasó',
  };
}

T _catalogo<T>(Map<String, T> porCodigo, String? codigo, T porDefecto) =>
    porCodigo[codigo] ?? porDefecto;

const Map<String, EstadoReserva> _estadosReserva = {
  'pendiente_pago': EstadoReserva.pendientePago,
  'confirmada': EstadoReserva.confirmada,
  'cancelada': EstadoReserva.cancelada,
};

const Map<String, EstadoPago> _estadosPago = {
  'pendiente': EstadoPago.pendiente,
  'aprobado': EstadoPago.aprobado,
  'rechazado': EstadoPago.rechazado,
};

const Map<String, MotivoSlot> _motivosSlot = {
  'ocupado': MotivoSlot.ocupado,
  'transcurrido': MotivoSlot.transcurrido,
};

// --- Entidades ---------------------------------------------------------------

/// Cancha del catálogo público (`GET /api/canchas`).
class Cancha {
  const Cancha({
    required this.id,
    required this.nombre,
    required this.ubicacion,
    required this.foto,
    this.tarifaBase,
  });

  factory Cancha.fromJson(Map<String, dynamic> json) => Cancha(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre']?.toString() ?? '',
    ubicacion: json['ubicacion']?.toString() ?? '',
    foto: json['foto']?.toString() ?? '',
    tarifaBase: (json['tarifa_base'] as num?)?.toDouble(),
  );

  final int id;
  final String nombre;
  final String ubicacion;
  final String foto;

  /// Precio "desde": el mínimo entre los horarios. `null` si la cancha no tiene
  /// horarios cargados todavía.
  final double? tarifaBase;

  bool get tieneFoto => foto.trim().isNotEmpty;
}

/// Slot de un día (`GET /api/disponibilidad`).
class Slot {
  const Slot({
    required this.horarioId,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.tarifa,
    required this.disponible,
    this.motivo,
  });

  factory Slot.fromJson(Map<String, dynamic> json) => Slot(
    horarioId: (json['horario_id'] as num).toInt(),
    fecha: json['fecha']?.toString() ?? '',
    horaInicio: json['hora_inicio']?.toString() ?? '',
    horaFin: json['hora_fin']?.toString() ?? '',
    tarifa: (json['tarifa'] as num?)?.toDouble() ?? 0,
    disponible: json['disponible'] == true,
    motivo: json['motivo'] == null
        ? null
        : _catalogo<MotivoSlot>(_motivosSlot, json['motivo']!.toString(), MotivoSlot.ocupado),
  );

  final int horarioId;
  final String fecha;
  final String horaInicio;
  final String horaFin;
  final double tarifa;
  final bool disponible;

  /// Por qué no se puede elegir. `null` cuando el slot está disponible.
  final MotivoSlot? motivo;

  String get rango => '$horaInicio – $horaFin';
}

/// Pago de una reserva.
class Pago {
  const Pago({
    required this.id,
    required this.reservaId,
    required this.monto,
    required this.metodo,
    required this.estado,
  });

  factory Pago.fromJson(Map<String, dynamic> json) => Pago(
    id: (json['id'] as num).toInt(),
    reservaId: (json['reserva_id'] as num?)?.toInt() ?? 0,
    monto: (json['monto'] as num?)?.toDouble() ?? 0,
    metodo: json['metodo']?.toString() ?? 'mock',
    estado: _catalogo<EstadoPago>(_estadosPago, json['estado']?.toString(), EstadoPago.pendiente),
  );

  final int id;
  final int reservaId;
  final double monto;
  final String metodo;
  final EstadoPago estado;

  /// `true` cuando el pago se hizo con la pasarela simulada: sólo entonces la app
  /// ofrece el atajo de "simular pago" (`POST /api/pagos/{id}/simular`).
  bool get esSimulado => metodo == 'mock';
}

/// Reserva del cliente (`GET /api/mis-reservas`).
class Reserva {
  const Reserva({
    required this.id,
    required this.cancha,
    required this.horarioId,
    required this.horaInicio,
    required this.horaFin,
    required this.tarifa,
    required this.fecha,
    required this.estado,
    this.pago,
  });

  factory Reserva.fromJson(Map<String, dynamic> json) {
    final canchaJson = Map<String, dynamic>.from((json['cancha'] as Map?) ?? const {});
    final horarioJson = Map<String, dynamic>.from((json['horario'] as Map?) ?? const {});
    final pagoJson = json['pago'];
    return Reserva(
      id: (json['reserva_id'] as num).toInt(),
      cancha: Cancha.fromJson({...canchaJson, 'tarifa_base': null}),
      horarioId: (horarioJson['id'] as num?)?.toInt() ?? 0,
      horaInicio: horarioJson['hora_inicio']?.toString() ?? '',
      horaFin: horarioJson['hora_fin']?.toString() ?? '',
      tarifa: (horarioJson['tarifa'] as num?)?.toDouble() ?? 0,
      fecha: json['fecha']?.toString() ?? '',
      estado: _catalogo<EstadoReserva>(
        _estadosReserva,
        json['estado']?.toString(),
        EstadoReserva.pendientePago,
      ),
      pago: pagoJson is Map ? Pago.fromJson(Map<String, dynamic>.from(pagoJson)) : null,
    );
  }

  final int id;
  final Cancha cancha;
  final int horarioId;
  final String horaInicio;
  final String horaFin;
  final double tarifa;
  final String fecha;
  final EstadoReserva estado;
  final Pago? pago;

  /// `true` si la reserva espera un pago: hay que pagar o reintentar el pago.
  bool get pendienteDePago => estado == EstadoReserva.pendientePago;

  /// `true` si el pago fue rechazado y la reserva volvió a quedar pagable.
  bool get pagoFallido => pago?.estado == EstadoPago.rechazado;

  String get rango => '$horaInicio – $horaFin';
}

/// Resultado de `POST /api/reservas`: la reserva recién creada con su pago pendiente.
class ReservaCreada {
  const ReservaCreada({required this.reservaId, required this.estado, required this.pago});

  factory ReservaCreada.fromJson(Map<String, dynamic> json) {
    final pagoJson = Map<String, dynamic>.from((json['pago'] as Map?) ?? const {});
    return ReservaCreada(
      reservaId: (json['reserva_id'] as num).toInt(),
      estado: _catalogo<EstadoReserva>(
        _estadosReserva,
        json['estado']?.toString(),
        EstadoReserva.pendientePago,
      ),
      pago: Pago.fromJson({...pagoJson, 'reserva_id': json['reserva_id']}),
    );
  }

  final int reservaId;
  final EstadoReserva estado;
  final Pago pago;
}

/// Sesión de pago abierta por la pasarela (`POST /api/pagos/checkout`).
class Checkout {
  const Checkout({required this.pagoId, required this.checkoutUrl});

  factory Checkout.fromJson(Map<String, dynamic> json) => Checkout(
    pagoId: (json['pago_id'] as num).toInt(),
    checkoutUrl: json['checkout_url']?.toString() ?? '',
  );

  final int pagoId;
  final String checkoutUrl;

  /// En modo `mock` la URL es ilustrativa y no lleva a ninguna parte: no tiene sentido
  /// abrirla en el navegador, la app cierra el pago con `/simular`.
  bool get esIlustrativa => checkoutUrl.contains('/checkout/simulado/');
}

/// Respuesta de confirmar o rechazar el pago (webhook o `/simular`).
///
/// [aplicado] en `false` significa que el pago ya no estaba pendiente: el evento llegó
/// repetido o fuera de orden y la app debe limitarse a mostrar el estado actual.
class ResultadoPago {
  const ResultadoPago({required this.aplicado, required this.pago, this.estadoReserva});

  factory ResultadoPago.fromJson(Map<String, dynamic> json) {
    final pagoJson = Map<String, dynamic>.from((json['pago'] as Map?) ?? const {});
    return ResultadoPago(
      aplicado: json['aplicado'] == true,
      pago: Pago.fromJson(pagoJson),
      estadoReserva: json['estado_reserva'] == null
          ? null
          : _catalogo<EstadoReserva>(
              _estadosReserva,
              json['estado_reserva']!.toString(),
              EstadoReserva.pendientePago,
            ),
    );
  }

  final bool aplicado;
  final Pago pago;
  final EstadoReserva? estadoReserva;
}

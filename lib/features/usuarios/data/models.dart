/// Modelos del panel de admin (`spec.md 3.5`).
///
/// El admin es el único rol que ve datos de otros, así que los modelos llevan a la
/// vista lo que el backend calcula y la app no debe recalcular: los conteos de canchas y
/// reservas por usuario vienen porque son la información que permite decidir un cambio
/// de rol sin abrir tres pantallas, y el reporte llega agregado para no traer todas las
/// reservas a sumar en el teléfono.
library;

import '../../cliente/data/models.dart' show EstadoReserva, EstadoReservaX;

/// Fila de `GET /api/usuarios`.
class UsuarioAdmin {
  const UsuarioAdmin({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.activo,
    required this.canchas,
    required this.reservas,
  });

  factory UsuarioAdmin.fromJson(Map<String, dynamic> json) => UsuarioAdmin(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    // Un rol desconocido se trata como cliente, que es el de menor permiso: ante la
    // duda, la app no muestra herramientas de administración a nadie.
    rol: _rolDesdeCodigo(json['rol']?.toString()),
    activo: json['activo'] != false,
    canchas: (json['canchas'] as num?)?.toInt() ?? 0,
    reservas: (json['reservas'] as num?)?.toInt() ?? 0,
  );

  final int id;
  final String nombre;
  final String email;
  final RolUsuario rol;
  final bool activo;
  final int canchas;
  final int reservas;

  String get etiquetaRol => switch (rol) {
    RolUsuario.admin => 'Administrador',
    RolUsuario.dueno => 'Dueño',
    RolUsuario.cliente => 'Cliente',
  };

  /// `true` si el backend puede devolverle `422` por tener canchas activas: la app avisa
  /// antes de que el usuario lo descubra en un error, pero la decisión sigue siendo del
  /// backend (HEUR-5).
  bool get tieneCanchasActivas => canchas > 0;
}

enum RolUsuario {
  cliente('cliente', 'Cliente'),
  dueno('dueno', 'Dueño de cancha'),
  admin('admin', 'Administrador');

  const RolUsuario(this.codigo, this.etiqueta);

  final String codigo;
  final String etiqueta;

}

/// Un rol desconocido se degrada a `cliente`, que es el de menor permiso: ante la duda,
/// la app no le muestra herramientas de administración a nadie.
RolUsuario _rolDesdeCodigo(String? codigo) => RolUsuario.values.firstWhere(
  (r) => r.codigo == codigo,
  orElse: () => RolUsuario.cliente,
);

/// Una barra del desglose de ingresos por cancha.
class IngresoCancha {
  const IngresoCancha({
    required this.canchaId,
    required this.nombre,
    required this.monto,
    required this.reservas,
  });

  factory IngresoCancha.fromJson(Map<String, dynamic> json) => IngresoCancha(
    canchaId: (json['cancha_id'] as num).toInt(),
    nombre: json['nombre']?.toString() ?? '',
    monto: (json['monto'] as num?)?.toDouble() ?? 0,
    reservas: (json['reservas'] as num?)?.toInt() ?? 0,
  );

  final int canchaId;
  final String nombre;
  final double monto;
  final int reservas;
}

/// Una barra de ingresos por día de reserva.
class IngresoDia {
  const IngresoDia({required this.fecha, required this.monto, required this.reservas});

  factory IngresoDia.fromJson(Map<String, dynamic> json) => IngresoDia(
    fecha: fechaTexto(json['fecha']?.toString()),
    monto: (json['monto'] as num?)?.toDouble() ?? 0,
    reservas: (json['reservas'] as num?)?.toInt() ?? 0,
  );

  /// `2026-09-20` sin la hora, para etiquetar la gráfica por día.
  final String fecha;
  final double monto;
  final int reservas;
}

/// Conteo de reservas de una cancha (sin monto: es el volumen, no el dinero).
class CanchaConReservas {
  const CanchaConReservas({required this.canchaId, required this.nombre, required this.reservas});

  factory CanchaConReservas.fromJson(Map<String, dynamic> json) => CanchaConReservas(
    canchaId: (json['cancha_id'] as num).toInt(),
    nombre: json['nombre']?.toString() ?? '',
    reservas: (json['reservas'] as num?)?.toInt() ?? 0,
  );

  final int canchaId;
  final String nombre;
  final int reservas;
}

/// `GET /api/reporte` completo.
class ReporteAdmin {
  const ReporteAdmin({
    required this.generadoEn,
    required this.ingresosTotal,
    required this.ingresosPorCancha,
    required this.ingresosPorDia,
    required this.reservasTotal,
    required this.reservasPorEstado,
    required this.reservasPorCancha,
    required this.usuariosTotal,
    required this.usuariosPorRol,
    required this.usuariosInactivos,
  });

  factory ReporteAdmin.fromJson(Map<String, dynamic> json) {
    final ingresos = (json['ingresos'] as Map?)?.cast<String, dynamic>() ?? const {};
    final reservas = (json['reservas'] as Map?)?.cast<String, dynamic>() ?? const {};
    final usuarios = (json['usuarios'] as Map?)?.cast<String, dynamic>() ?? const {};

    return ReporteAdmin(
      generadoEn: fechaTexto(json['generado_en']?.toString()),
      ingresosTotal: (ingresos['total'] as num?)?.toDouble() ?? 0,
      ingresosPorCancha: _lista(ingresos['por_cancha'], IngresoCancha.fromJson),
      ingresosPorDia: _lista(ingresos['por_dia'], IngresoDia.fromJson),
      reservasTotal: (reservas['total'] as num?)?.toInt() ?? 0,
      reservasPorEstado: _mapaEnteros(reservas['por_estado']),
      reservasPorCancha: _lista(reservas['por_cancha'], CanchaConReservas.fromJson),
      usuariosTotal: (usuarios['total'] as num?)?.toInt() ?? 0,
      usuariosPorRol: _mapaEnteros(usuarios['por_rol']),
      usuariosInactivos: (usuarios['inactivos'] as num?)?.toInt() ?? 0,
    );
  }

  final String generadoEn;
  final double ingresosTotal;
  final List<IngresoCancha> ingresosPorCancha;
  final List<IngresoDia> ingresosPorDia;
  final int reservasTotal;
  final Map<String, int> reservasPorEstado;
  final List<CanchaConReservas> reservasPorCancha;
  final int usuariosTotal;
  final Map<String, int> usuariosPorRol;
  final int usuariosInactivos;

  /// El desglose siempre suma el total (lo fija un test del backend): si no cuadrara, la
  /// gráfica estaría mintiendo y la app lo muestra como error de datos.
  bool get desgloseCuadra {
    final suma = ingresosPorCancha.fold<double>(0, (total, c) => total + c.monto);
    return (suma - ingresosTotal).abs() < 0.01;
  }

  /// Estados con al menos una reserva, en el orden del catálogo y no en el que llegue
  /// el JSON: una gráfica cuyas barras cambian de orden entre recargas no se puede leer.
  List<EstadoReserva> get estadosPresentes => const [
    EstadoReserva.pendientePago,
    EstadoReserva.confirmada,
    EstadoReserva.cancelada,
  ].where((estado) => (reservasPorEstado[estado.codigo] ?? 0) > 0).toList(growable: false);

  int reservasDe(EstadoReserva estado) => reservasPorEstado[estado.codigo] ?? 0;
}

List<T> _lista<T>(Object? crudo, T Function(Map<String, dynamic>) construir) {
  if (crudo is! List) return const [];
  return crudo
      .whereType<Map>()
      .map((item) => construir(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

Map<String, int> _mapaEnteros(Object? crudo) {
  if (crudo is! Map) return const {};
  return {
    for (final entrada in crudo.entries)
      entrada.key.toString(): (entrada.value as num?)?.toInt() ?? 0,
  };
}

/// Quita la parte de la hora que traen los `server_default` de la base (`2026-09-20
/// 00:00:00+00:00`) para poder pintar sólo el día.
String fechaTexto(String? iso) {
  if (iso == null) return '';
  return iso.split(' ').first.split('T').first;
}

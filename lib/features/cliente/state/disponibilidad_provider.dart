import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import 'canchas_provider.dart';
import '../../../core/state/retry.dart';

/// Disponibilidad de una cancha: los 6 días desde hoy, agrupados por fecha.
///
/// Un `FutureProvider.family` porque la respuesta ya trae los 6 días: cambiar de día es
/// filtrar en memoria, sin volver a pedir nada. Se invalida (no se recarga a ciegas)
/// cuando una reserva falla con `409`, que es cuando el slot mostrado puede estar viejo.
final disponibilidadProvider = FutureProvider.family<List<Slot>, int>(
  (ref, canchaId) => ref.watch(canchasRepositoryProvider).disponibilidad(
    canchaId: canchaId,
    fechaInicio: hoyIso(),
  ),
  retry: sinReintento,
);

/// Fecha de hoy en `YYYY-MM-DD`, el formato que espera la API.
///
/// Se calcula con la hora local del teléfono: la disponibilidad del backend también usa
/// la hora del servidor, así que un dispositivo con el reloj desajustado puede ver una
/// diferencia de un día; es el mismo criterio que ya usa `/api/disponibilidad`.
String hoyIso({DateTime? ahora}) {
  final fecha = ahora ?? DateTime.now();
  return '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}

/// Días que ofrece la disponibilidad, en orden.
List<String> diasDe(List<Slot> slots) {
  final fechas = <String>[];
  for (final slot in slots) {
    if (!fechas.contains(slot.fecha)) fechas.add(slot.fecha);
  }
  return fechas;
}

/// Slots de un día, ordenados por hora de inicio.
List<Slot> slotsDeDia(List<Slot> slots, String fecha) {
  final delDia = slots.where((slot) => slot.fecha == fecha).toList()
    ..sort((a, b) => a.horaInicio.compareTo(b.horaInicio));
  return delDia;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/features/cliente/data/models.dart';
import 'package:goaltime_flutter/features/cliente/state/disponibilidad_provider.dart';
import 'package:goaltime_flutter/shared/format.dart';

void main() {
  group('formatoMonto', () {
    test('agrupa los miles con punto', () {
      expect(formatoMonto(60000), r'$ 60.000');
      expect(formatoMonto(45000.5), r'$ 45.001');
      expect(formatoMonto(999), r'$ 999');
      expect(formatoMonto(1000), r'$ 1.000');
    });

    test(r'un monto ausente se muestra como guion, no como $ 0', () {
      expect(formatoMonto(null), '—');
    });
  });

  group('fechas', () {
    test('parseFechaIso devuelve la fecha local', () {
      final fecha = parseFechaIso('2026-09-25');
      expect(fecha, DateTime(2026, 9, 25));
    });

    test('una fecha mal formada no revienta la pantalla', () {
      expect(parseFechaIso('25/09/2026'), isNull);
      expect(parseFechaIso(null), isNull);
    });

    test('hoy y mañana se nombran, el resto se muestra corto', () {
      final hoy = DateTime.now();
      final manana = hoy.add(const Duration(days: 1));
      expect(etiquetaFecha(_iso(hoy)), 'Hoy');
      expect(etiquetaFecha(_iso(manana)), 'Mañana');
      expect(etiquetaFecha('2020-01-05'), 'dom 5 ene');
    });
  });

  group('días de la disponibilidad', () {
    final slots = [
      _slot(10, '2026-09-25', '08:00'),
      _slot(11, '2026-09-25', '14:00'),
      _slot(12, '2026-09-26', '08:00'),
    ];

    test('diasDe agrupa sin repetir y en el orden que llega la respuesta', () {
      expect(diasDe(slots), ['2026-09-25', '2026-09-26']);
    });

    test('slotsDeDia ordena por hora de inicio', () {
      final delDia = slotsDeDia(slots, '2026-09-25');
      expect(delDia.map((s) => s.horaInicio), ['08:00', '14:00']);
    });

    test('un día sin horarios devuelve una lista vacía', () {
      expect(slotsDeDia(slots, '2026-09-27'), isEmpty);
    });
  });

  group('hoyIso', () {
    test('devuelve el formato que espera la API', () {
      expect(hoyIso(ahora: DateTime(2026, 9, 5)), '2026-09-05');
      expect(hoyIso(ahora: DateTime(2026, 12, 25)), '2026-12-25');
    });
  });
}

String _iso(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

Slot _slot(int id, String fecha, String hora) => Slot(
  horarioId: id,
  fecha: fecha,
  horaInicio: hora,
  horaFin: '10:00',
  tarifa: 60000,
  disponible: true,
);

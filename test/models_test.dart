import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/features/cliente/data/models.dart';

void main() {
  group('Catálogos', () {
    test('un estado desconocido no rompe el modelo', () {
      final pago = Pago.fromJson({'id': 1, 'estado': 'liquidado'});
      expect(pago.estado, EstadoPago.pendiente);
    });

    test('los códigos del backend se traducen a los enums de la app', () {
      expect(EstadoReserva.pendientePago.codigo, 'pendiente_pago');
      expect(EstadoPago.aprobado.codigo, 'aprobado');
      expect(MotivoSlot.ocupado.etiqueta, 'Ocupado');
    });
  });

  group('Cancha', () {
    test('lee el precio mínimo del catálogo', () {
      final cancha = Cancha.fromJson({
        'id': 1,
        'nombre': 'El Retiro',
        'ubicacion': 'Cra 45',
        'foto': '',
        'tarifa_base': 60000.0,
      });
      expect(cancha.tarifaBase, 60000.0);
      expect(cancha.tieneFoto, isFalse);
    });

    test('una foto vacía no se intenta cargar', () {
      final cancha = Cancha.fromJson({
        'id': 1,
        'nombre': 'El Retiro',
        'ubicacion': 'Cra 45',
        'foto': '   ',
      });
      expect(cancha.tieneFoto, isFalse);
    });
  });

  group('Slot', () {
    test('un slot disponible no tiene motivo', () {
      final slot = Slot.fromJson({
        'horario_id': 11,
        'fecha': '2026-09-25',
        'hora_inicio': '14:00',
        'hora_fin': '16:00',
        'tarifa': 60000.0,
        'disponible': true,
        'motivo': null,
      });
      expect(slot.disponible, isTrue);
      expect(slot.motivo, isNull);
      expect(slot.rango, '14:00 – 16:00');
    });

    test('un motivo desconocido se lee como ocupado, nunca como disponible', () {
      final slot = Slot.fromJson({
        'horario_id': 11,
        'fecha': '2026-09-25',
        'hora_inicio': '14:00',
        'hora_fin': '16:00',
        'tarifa': 60000.0,
        'disponible': false,
        'motivo': 'mantenimiento',
      });
      expect(slot.disponible, isFalse);
      expect(slot.motivo, MotivoSlot.ocupado);
    });
  });

  group('Reserva', () {
    test('lee la reserva con su pago anidado', () {
      final reserva = Reserva.fromJson({
        'reserva_id': 7,
        'cancha': {'id': 1, 'nombre': 'El Retiro', 'ubicacion': 'Cra 45'},
        'horario': {'id': 11, 'hora_inicio': '14:00', 'hora_fin': '16:00', 'tarifa': 60000.0},
        'fecha': '2026-09-25',
        'estado': 'pendiente_pago',
        'pago': {'id': 9, 'reserva_id': 7, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'pendiente'},
      });

      expect(reserva.id, 7);
      expect(reserva.cancha.nombre, 'El Retiro');
      // La cancha anidada no trae `tarifa_base`: el precio que importa es el del horario.
      expect(reserva.cancha.tarifaBase, isNull);
      expect(reserva.tarifa, 60000.0);
      expect(reserva.estado, EstadoReserva.pendientePago);
      expect(reserva.pago!.esSimulado, isTrue);
      expect(reserva.pagoFallido, isFalse);
    });

    test('un pago rechazado deja la reserva pagable otra vez', () {
      final reserva = Reserva.fromJson({
        'reserva_id': 7,
        'cancha': {'id': 1, 'nombre': 'El Retiro', 'ubicacion': 'Cra 45'},
        'horario': {'id': 11, 'hora_inicio': '14:00', 'hora_fin': '16:00', 'tarifa': 60000.0},
        'fecha': '2026-09-25',
        'estado': 'pendiente_pago',
        'pago': {'id': 9, 'reserva_id': 7, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'rechazado'},
      });

      expect(reserva.pagoFallido, isTrue);
      expect(reserva.estado, EstadoReserva.pendientePago);
    });
  });

  group('ReservaCreada', () {
    test('el pago devuelto sin `reserva_id` se completa con el de la reserva', () {
      final creada = ReservaCreada.fromJson({
        'reserva_id': 12,
        'estado': 'pendiente_pago',
        'pago': {'id': 13, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'pendiente'},
      });

      expect(creada.reservaId, 12);
      expect(creada.pago.id, 13);
      expect(creada.pago.reservaId, 12);
    });
  });

  group('Checkout', () {
    test('la URL simulada se reconoce como ilustrativa', () {
      final checkout = Checkout.fromJson({
        'pago_id': 9,
        'checkout_url': 'https://goaltime.test/checkout/simulado/9',
      });
      expect(checkout.esIlustrativa, isTrue);
    });

    test('la URL de Stripe no es ilustrativa', () {
      final checkout = Checkout.fromJson({
        'pago_id': 9,
        'checkout_url': 'https://checkout.stripe.com/c/pay/cs_test_123',
      });
      expect(checkout.esIlustrativa, isFalse);
    });
  });

  group('ResultadoPago', () {
    test('un evento repetido se marca como no aplicado pero trae el estado actual', () {
      final resultado = ResultadoPago.fromJson({
        'aplicado': false,
        'pago': {'id': 9, 'reserva_id': 7, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'aprobado'},
      });

      expect(resultado.aplicado, isFalse);
      expect(resultado.pago.estado, EstadoPago.aprobado);
      expect(resultado.estadoReserva, isNull);
    });

    test('una aprobación trae también el estado de la reserva', () {
      final resultado = ResultadoPago.fromJson({
        'aplicado': true,
        'pago': {'id': 9, 'reserva_id': 7, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'aprobado'},
        'estado_reserva': 'confirmada',
      });

      expect(resultado.estadoReserva, EstadoReserva.confirmada);
    });
  });
}

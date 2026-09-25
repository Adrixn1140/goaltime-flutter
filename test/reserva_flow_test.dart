import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/features/cliente/presentation/widgets/slot_tile.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('el catálogo ofrece las canchas y entra a la disponibilidad', (tester) async {
    final api = _api();

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    expect(find.text('Cancha El Retiro'), findsOneWidget);
    expect(find.text(r'$ 60.000'), findsOneWidget);

    await tester.tap(find.text('Cancha El Retiro'));
    await tester.pumpAndSettle();

    // El día de hoy muestra el slot ya pasado y el libre; el ocupado viene deshabilitado.
    expect(find.text('08:00 – 10:00'), findsOneWidget);
    expect(find.text('Ya pasó'), findsOneWidget);
    expect(find.text('14:00 – 16:00'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Elige un horario'), findsOneWidget);
  });

  testWidgets('un error al cargar muestra el aviso y reintenta', (tester) async {
    final api = _api();
    api.fallarLaProxima('GET', '/api/canchas', 503, 'No se pudo conectar');

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos cargar las canchas'), findsOneWidget);
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Cancha El Retiro'), findsOneWidget);
  });

  testWidgets('un catálogo vacío explica qué va a pasar después', (tester) async {
    final api = _api();
    api.responder('GET', '/api/canchas', <Object>[]);

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    expect(find.text('Todavía no hay canchas'), findsOneWidget);
  });

  testWidgets('reservar pide confirmación, cobra lo que dice el backend y abre el pago', (
    tester,
  ) async {
    final api = _api();

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancha El Retiro'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('14:00 – 16:00'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Reservar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reservar'));
    await tester.pumpAndSettle();

    // Diálogo de ticket: la reserva existe pero falta el pago.
    expect(find.text('Reserva creada'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(r'$ 60.000')),
      findsOneWidget,
    );
    // No se envió el monto: el backend lo calcula desde el horario.
    expect(
      api.peticiones.any((p) => p.contains('POST /api/reservas') && !p.contains('60000')),
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Pagar ahora'));
    await tester.pumpAndSettle();

    // Hoja de pago en modo simulado.
    expect(find.text('Pago de la reserva'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Simular pago aprobado'), findsOneWidget);
  });

  testWidgets('el 409 al reservar se explica y refresca la disponibilidad', (tester) async {
    final api = _api();
    api.error('POST', '/api/reservas', 409, 'Ese horario ya está reservado para esa fecha');

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancha El Retiro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14:00 – 16:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reservar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ese horario ya está reservado'), findsOneWidget);
    // El backend vuelve a pedirse: el slot que se vio ya no era libre.
    expect(
      api.peticiones.where((p) => p.startsWith('GET /api/disponibilidad')).length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('un slot no disponible se muestra deshabilitado con su motivo', (tester) async {
    final api = _api();

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancha El Retiro'));
    await tester.pumpAndSettle();

    final slot = tester.widget<SlotTile>(find.widgetWithText(SlotTile, '08:00 – 10:00'));
    expect(slot.slot.disponible, isFalse);
    expect(slot.slot.motivo, isNotNull);
  });
}

FakeApi _api() {
  final api = FakeApi();
  canchasDePrueba(api);
  disponibilidadDePrueba(api);
  api.responder('POST', '/api/reservas', {
    'reserva_id': 7,
    'estado': 'pendiente_pago',
    'pago': {'id': 9, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'pendiente'},
  }, status: 201);
  api.responder('GET', '/api/pagos/9', {
    'id': 9,
    'reserva_id': 7,
    'monto': 60000.0,
    'metodo': 'mock',
    'estado': 'pendiente',
  });
  api.responder('POST', '/api/pagos/checkout', {
    'pago_id': 9,
    'checkout_url': 'https://goaltime.test/checkout/simulado/9',
  }, status: 201);
  api.responder('GET', '/api/mis-reservas', [reservaDePrueba()]);
  return api;
}


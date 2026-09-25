import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('mis reservas lista la historial y ofrece pagar la pendiente', (tester) async {
    final api = _api();

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await _irAMisReservas(tester);

    expect(find.text('Cancha El Retiro'), findsOneWidget);
    expect(find.text('Pendiente de pago'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pagar'), findsOneWidget);
  });

  testWidgets('un pago rechazado muestra el reintento en la tarjeta', (tester) async {
    final api = _api();
    api.responder('GET', '/api/mis-reservas', [
      reservaDePrueba(pago: 'rechazado'),
    ]);

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await _irAMisReservas(tester);

    expect(find.text('El pago fue rechazado. La reserva sigue apartada.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reintentar el pago'), findsOneWidget);
  });

  testWidgets('sin reservas se explica qué hacer a continuación', (tester) async {
    final api = _api();
    api.responder('GET', '/api/mis-reservas', <Object>[]);

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await _irAMisReservas(tester);

    expect(find.textContaining('Todavía no tienes reservas'), findsOneWidget);
  });

  testWidgets('simular el pago aprobado deja la reserva confirmada', (tester) async {
    final api = _api();

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await _irAMisReservas(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Pagar'));
    await tester.pumpAndSettle();
    expect(find.text('Pago de la reserva'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Simular pago aprobado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // El estado del pago cambió y la tarjeta lo refleja al recargar.
    expect(find.text('Confirmada'), findsWidgets);
    expect(find.textContaining('Pago aprobado'), findsOneWidget);
    expect(
      api.peticiones.any((p) => p.contains('POST /api/pagos/9/simular') && p.contains('aprobado')),
      isTrue,
    );
  });

  testWidgets('un pago rechazado deja la reserva pagable otra vez', (tester) async {
    final api = _api();
    // El backend responde según el `resultado` que le enviaron.
    api.alRecibir('POST', '/api/pagos/9/simular', (api) {
      final aprobado = api.peticiones.last.contains('"resultado":"aprobado"');
      api.responder('POST', '/api/pagos/9/simular', {
        'aplicado': true,
        'pago': {
          'id': 9,
          'reserva_id': 7,
          'monto': 60000.0,
          'metodo': 'mock',
          'estado': aprobado ? 'aprobado' : 'rechazado',
        },
        // Un rechazo devuelve la reserva a `pendiente_pago` para que se pueda reintentar.
        'estado_reserva': aprobado ? 'confirmada' : 'pendiente_pago',
      });
      api.responder('GET', '/api/pagos/9', {
        'id': 9,
        'reserva_id': 7,
        'monto': 60000.0,
        'metodo': 'mock',
        'estado': aprobado ? 'aprobado' : 'rechazado',
      });
    });

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await _irAMisReservas(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Pagar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Simular pago rechazado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // HEUR-9: tras el rechazo la hoja ofrece el reintento, no un callejón sin salida.
    expect(find.widgetWithText(FilledButton, 'Reintentar el pago'), findsOneWidget);
    expect(find.textContaining('sigue reservada para ti'), findsOneWidget);
  });

  testWidgets('con Stripe la app ofrece pagar con tarjeta, no simular', (tester) async {
    final api = _api();
    api.responder('GET', '/api/mis-reservas', [
      _reservaConPagoStripe(),
    ]);
    api.responder('GET', '/api/pagos/9', {
      'id': 9,
      'reserva_id': 7,
      'monto': 60000.0,
      'metodo': 'stripe',
      'estado': 'pendiente',
    });

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await _irAMisReservas(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Pagar'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Pagar con tarjeta'), findsOneWidget);
    expect(find.text('Simular pago aprobado'), findsNothing);
  });
}

Future<void> _irAMisReservas(WidgetTester tester) async {
  await tester.tap(find.text('Mis reservas'));
  await tester.pumpAndSettle();
}

Map<String, Object> _reservaConPagoStripe() {
  final reserva = reservaDePrueba();
  (reserva['pago']! as Map)['metodo'] = 'stripe';
  return reserva;
}

FakeApi _api() {
  final api = FakeApi();
  canchasDePrueba(api);
  api.responder('GET', '/api/mis-reservas', [reservaDePrueba()]);
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
  api.responder('POST', '/api/pagos/9/simular', {
    'aplicado': true,
    'pago': {'id': 9, 'reserva_id': 7, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'aprobado'},
    'estado_reserva': 'confirmada',
  });
  // Aprobar el pago cambia también lo que devuelve la lista, igual que en el backend.
  api.alRecibir('POST', '/api/pagos/9/simular', (api) {
    if (api.peticiones.any((p) => p.contains('"resultado":"aprobado"'))) {
      api.responder('GET', '/api/pagos/9', {
        'id': 9,
        'reserva_id': 7,
        'monto': 60000.0,
        'metodo': 'mock',
        'estado': 'aprobado',
      });
      api.responder('GET', '/api/mis-reservas', [
        reservaDePrueba(estado: 'confirmada', pago: 'aprobado'),
      ]);
    }
  });
  return api;
}


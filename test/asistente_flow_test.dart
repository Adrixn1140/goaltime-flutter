import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

/// Flujo del asistente (spec.md 3.6): la persona pide en lenguaje natural, recibe la
/// respuesta con opciones, y cada opción lleva a la reserva con la fecha y el horario ya
/// preseleccionados. El asistente no reserva ni cobra: presenta y confirma la persona en
/// la pantalla de reserva, y por eso la sugerencia navega ahí en vez de abrir un diálogo.
void main() {
  testWidgets('el asistente responde y ofrece la sugerencia como tarjeta', (tester) async {
    final api = _api();

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistente'));
    await tester.pumpAndSettle();

    // Antes de mandar nada, la pantalla explica qué se puede pedir.
    expect(find.textContaining('Cuéntame cuándo quieres jugar'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Quiero jugar mañana');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
    await tester.pumpAndSettle();

    // El mensaje real fue un POST /api/asistente con lo escrito, sin inventarse cuerpo.
    expect(
      api.peticiones.any(
        (p) => p.startsWith('POST /api/asistente') && p.contains('Quiero jugar mañana'),
      ),
      isTrue,
    );

    expect(
      find.text('Mañana hay un horario libre en Cancha El Retiro.'),
      findsOneWidget,
    );
    expect(find.text('Cancha El Retiro'), findsOneWidget);
    expect(find.text(r'$ 65.000'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reservar'), findsOneWidget);
  });

  testWidgets('una sugerencia abre la reserva con la fecha y el horario ya elegidos', (
    tester,
  ) async {
    final api = _api();

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Quiero jugar mañana');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Reservar'));
    await tester.pumpAndSettle();

    // Cayó en la pantalla de reserva de la cancha sugerida, sin tocar catálogo, y el
    // horario de la sugerencia ya viene preseleccionado: el botón dice "Reservar" y no
    // "Elige un horario".
    expect(find.text('08:00 – 10:00'), findsOneWidget);
    expect(find.text('Elige un horario'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Reservar'), findsOneWidget);

    // Y desde ahí se puede confirmar el pago como en el flujo normal de reserva.
    await tester.tap(find.widgetWithText(FilledButton, 'Reservar'));
    await tester.pumpAndSettle();
    expect(find.text('Reserva creada'), findsOneWidget);
  });

  testWidgets('un saludo no dispara la búsqueda y no ofrece sugerencias', (tester) async {
    final api = _api(sugerencias: false);

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(
      find.text('Hola. Dime qué quieres reservar y te busco canchas libres.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Reservar'), findsNothing);
  });

  testWidgets('una caída del proveedor se explica como mensaje y se puede reintentar', (
    tester,
  ) async {
    final api = _api();
    api.fallarLaProxima('POST', '/api/asistente', 502, 'El proveedor no respondió');

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Quiero jugar mañana');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
    await tester.pumpAndSettle();

    // El fallo aparece dentro de la conversación, no tapando la pantalla, y sin pijos del
    // proveedor: `mensajeDeError` mostró el texto redactado del backend.
    expect(find.text('El proveedor no respondió'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reservar'), findsNothing);

    // La conversación sigue viva: se pregunta de nuevo y esta vez la respuesta llega.
    await tester.enterText(find.byType(TextField), 'Quiero jugar mañana');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(
      find.text('Mañana hay un horario libre en Cancha El Retiro.'),
      findsOneWidget,
    );
  });
}

FakeApi _api({bool sugerencias = true}) {
  final api = FakeApi();
  canchasDePrueba(api);
  disponibilidadDePrueba(api);
  // Reserva mínima para el final del flujo "elegir → confirmar".
  api.responder('POST', '/api/reservas', {
    'reserva_id': 7,
    'estado': 'pendiente_pago',
    'pago': {'id': 9, 'monto': 65000.0, 'metodo': 'mock', 'estado': 'pendiente'},
  }, status: 201);
  // Al confirmar la reserva la app refresca la lista; sin la ruta el log llenaría de 404.
  api.responder('GET', '/api/mis-reservas', [reservaDePrueba()]);
  if (sugerencias) {
    asistenteDePrueba(api);
  } else {
    asistenteSaludo(api);
  }
  return api;
}
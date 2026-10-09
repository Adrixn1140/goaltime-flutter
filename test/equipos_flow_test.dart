import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/features/equipos/data/equipos_repository.dart';

import 'support/fake_api.dart';

Map<String, Object> _equipo({bool conJugador = false}) => {
  'id': 1,
  'nombre': 'Los del barrio',
  'jugadores': conJugador
      ? [
          {
            'id': 2,
            'nombre': 'Ana',
            'apellido': 'Prueba',
            'documento': '0001234567',
            'celular': '3000000000',
          },
        ]
      : <Object>[],
};

Future<void> _entrar(WidgetTester tester, FakeApi api) async {
  canchasDePrueba(api);
  await tester.pumpWidget(appDePrueba(api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Equipos'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String texto) async {
  await tester.ensureVisible(find.text(texto));
  await tester.tap(find.text(texto));
  await tester.pumpAndSettle();
}

void main() {
  test('el modelo conserva ceros iniciales y oculta el documento', () {
    final equipo = Equipo.fromJson(_equipo(conJugador: true));
    expect(equipo.jugadores.single.documento, '0001234567');
    expect(equipo.jugadores.single.documentoOculto, '••••4567');
  });

  testWidgets('crear equipo lleva a su plantilla vacía', (tester) async {
    final api = FakeApi()
      ..responder('GET', '/api/equipos', <Object>[])
      ..responder('POST', '/api/equipos', _equipo(), status: 201)
      ..responder('GET', '/api/equipos/1', _equipo());
    await _entrar(tester, api);
    expect(find.text('Aquí comienza tu equipo'), findsOneWidget);
    await _tap(tester, 'Crear equipo');
    await tester.enterText(find.byType(TextFormField), 'Los del barrio');
    await _tap(tester, 'Guardar equipo');
    expect(find.text('Los del barrio'), findsOneWidget);
    expect(find.text('Falta el primer fichaje'), findsOneWidget);
    expect(
      api.peticiones,
      contains('POST /api/equipos {"nombre":"Los del barrio"}'),
    );
  });

  testWidgets('añadir jugador envía los cuatro campos y actualiza plantilla', (
    tester,
  ) async {
    final api = FakeApi()
      ..responder('GET', '/api/equipos', [_equipo()])
      ..responder('GET', '/api/equipos/1', _equipo())
      ..responder('POST', '/api/equipos/1/jugadores', {'id': 2}, status: 201);
    api.alRecibir('POST', '/api/equipos/1/jugadores', (api) {
      api.responder('GET', '/api/equipos/1', _equipo(conJugador: true));
      api.responder('GET', '/api/equipos', [_equipo(conJugador: true)]);
    });
    await _entrar(tester, api);
    await _tap(tester, 'Los del barrio');
    await _tap(tester, 'Añadir jugador');
    for (final (index, valor) in [
      (0, 'Ana'),
      (1, 'Prueba'),
      (2, '0001234567'),
      (3, '3000000000'),
    ]) {
      await tester.enterText(find.byType(TextFormField).at(index), valor);
    }
    await _tap(tester, 'Guardar jugador');
    await tester.ensureVisible(find.text('Ana Prueba'));
    expect(find.text('Ana Prueba'), findsOneWidget);
    expect(find.textContaining('••••4567'), findsOneWidget);
    expect(find.text('0001234567'), findsNothing);
    expect(
      api.peticiones.any(
        (p) =>
            p.contains('POST /api/equipos/1/jugadores') &&
            p.contains('"documento":"0001234567"') &&
            p.contains('"celular":"3000000000"'),
      ),
      isTrue,
    );
  });

  testWidgets(
    'un documento duplicado conserva el formulario y permite corregir',
    (tester) async {
      final api = FakeApi()
        ..responder('GET', '/api/equipos', [_equipo()])
        ..responder('GET', '/api/equipos/1', _equipo())
        ..error(
          'POST',
          '/api/equipos/1/jugadores',
          409,
          'Ese documento ya está registrado en este equipo',
        );
      await _entrar(tester, api);
      await _tap(tester, 'Los del barrio');
      await _tap(tester, 'Añadir jugador');
      for (final (index, valor) in [
        (0, 'Ana'),
        (1, 'Prueba'),
        (2, '0001234567'),
        (3, '3000000000'),
      ]) {
        await tester.enterText(find.byType(TextFormField).at(index), valor);
      }
      await _tap(tester, 'Guardar jugador');
      expect(
        find.textContaining('Ese documento ya está registrado'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Ana',
      );
      expect(find.text('Guardar jugador'), findsOneWidget);
    },
  );

  testWidgets('valida nombre antes de crear y cancelar no hace un POST', (
    tester,
  ) async {
    final api = FakeApi()..responder('GET', '/api/equipos', <Object>[]);
    await _entrar(tester, api);
    await _tap(tester, 'Crear equipo');
    await tester.enterText(find.byType(TextFormField), 'ab');
    await _tap(tester, 'Guardar equipo');
    expect(find.text('Escribe entre 3 y 80 caracteres'), findsOneWidget);
    expect(
      api.peticiones.any((p) => p.startsWith('POST /api/equipos')),
      isFalse,
    );
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo equipo'), findsNothing);
  });

  testWidgets('un fallo de carga permite reintentar', (tester) async {
    final api = FakeApi()
      ..responder('GET', '/api/equipos', <Object>[])
      ..fallarLaProxima('GET', '/api/equipos', 503, 'No disponible');
    await _entrar(tester, api);
    await _tap(tester, 'Reintentar');
    expect(find.text('Aquí comienza tu equipo'), findsOneWidget);
    expect(api.peticiones.where((p) => p == 'GET /api/equipos').length, 2);
  });

  testWidgets('equipos se adapta a un celular estrecho', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi()..responder('GET', '/api/equipos', <Object>[]);
    await _entrar(tester, api);
    await _tap(tester, 'Crear equipo');
    await tester.enterText(find.byType(TextFormField), 'Los del barrio');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cerrar sesión no conserva equipos para la siguiente cuenta', (
    tester,
  ) async {
    final api = FakeApi()
      ..responder('GET', '/api/equipos', [_equipo()])
      ..responder('POST', '/api/logout', <String, Object>{}, status: 204)
      ..responder('POST', '/api/login', {
        'access_token': 'token-otro',
        'rol': 'cliente',
        'usuario': {
          'id': 99,
          'nombre': 'Otro Cliente',
          'email': 'otro@test.co',
          'rol': 'cliente',
        },
      });
    await _entrar(tester, api);
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Cerrar sesión');
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión').last);
    await tester.pumpAndSettle();
    api.responder('GET', '/api/equipos', <Object>[]);
    await tester.enterText(find.byType(TextFormField).first, 'otro@test.co');
    await tester.enterText(find.byType(TextFormField).at(1), 'Goaltime123!');
    await _tap(tester, 'Iniciar sesión');
    await tester.tap(find.text('Equipos'));
    await tester.pumpAndSettle();
    expect(find.text('Los del barrio'), findsNothing);
    expect(find.text('Aquí comienza tu equipo'), findsOneWidget);
  });
}

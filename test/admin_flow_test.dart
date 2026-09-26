import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

/// Panel de admin: usuarios, roles y reporte (`spec.md 3.5`).
///
/// Lo que se comprueba aquí es que el admin pueda hacer su trabajo sin adivinar: ver qué
/// tiene cada cuenta, cambiar roles y desactivar, entender el `422` que el backend
/// devuelve cuando el dueño todavía tiene canchas, y leer el reporte sin tener que sumar
/// nada a mano.
void main() {
  group('usuarios', () {
    testWidgets('lista cada cuenta con su rol y lo que tiene encima', (tester) async {
      await _entrarComoAdmin(tester, _api());

      expect(find.text('Ana Cliente'), findsOneWidget);
      expect(find.text('diego@correo.com'), findsOneWidget);
      expect(find.text('Dueño de cancha'), findsNWidgets(2));
      expect(find.text('Administrador'), findsOneWidget);
      // El conteo se muestra con su unidad: un "2" suelto no dice de qué son las dos.
      expect(find.textContaining('2 canchas'), findsOneWidget);
      expect(find.textContaining('3 reservas'), findsOneWidget);
      expect(find.text('0 canchas · 3 reservas'), findsOneWidget);
      expect(find.text('0 canchas · 0 reservas'), findsOneWidget);
    });

    testWidgets('sin usuarios se explica, sin romper la pantalla', (tester) async {
      final api = _api()..responder('GET', '/api/usuarios', {'usuarios': <Object>[]});

      await _entrarComoAdmin(tester, api);

      expect(find.text('No hay usuarios registrados.'), findsOneWidget);
    });

    testWidgets('si la lista falla se muestra el mensaje y un reintento', (tester) async {
      final api = _api()
        ..fallarLaProxima('GET', '/api/usuarios', 500, 'El servidor tuvo un problema.');

      await _entrarComoAdmin(tester, api);

      expect(find.textContaining('El servidor tuvo un problema.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
    });
  });

  group('cambio de rol', () {
    testWidgets('promover a dueño manda el rol y refresca la lista', (tester) async {
      final api = _api();
      await _entrarComoAdmin(tester, api);

      await _abrirAccionesDe(tester, 'Ana Cliente');
      await tester.tap(find.text('Cambiar rol'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dueño de cancha').last);
      await tester.pumpAndSettle();

      expect(
        api.peticiones.contains(
          'PATCH /api/usuarios/1/rol {"rol":"dueno"}',
        ),
        isTrue,
      );
    });

    testWidgets('el rol que ya tiene el usuario aparece marcado y no se puede elegir', (
      tester,
    ) async {
      await _entrarComoAdmin(tester, _api());

      await _abrirAccionesDe(tester, 'Diego Dueño');
      await tester.tap(find.text('Cambiar rol'));
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Dueño de cancha'));
      expect(tile.enabled, isFalse);
      expect(find.descendant(of: find.byType(ListTile), matching: find.byIcon(Icons.check)), findsOneWidget);
    });

    testWidgets('un 422 por canchas activas se muestra tal cual lo dice el backend', (
      tester,
    ) async {
      final api = _api()
        ..error(
          'PATCH',
          '/api/usuarios/2/rol',
          422,
          'Baja primero sus 2 canchas activas: si le quitas el rol de dueño quedarían sin nadie que las gestione',
        );
      await _entrarComoAdmin(tester, api);

      await _abrirAccionesDe(tester, 'Diego Dueño');
      await tester.tap(find.text('Cambiar rol'));
      await tester.pumpAndSettle();
      // "Cliente" está también en el chip de la tarjeta, así que se toca el de la hoja.
      await tester.tap(find.widgetWithText(ListTile, 'Cliente'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Baja primero sus 2 canchas activas'), findsOneWidget);
      // El aviso es transitorio y con acción: el siguiente paso está a un toque.
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('activar y desactivar', () {
    testWidgets('desactivar pide confirmación y avisa qué se conserva', (tester) async {
      final api = _api();
      await _entrarComoAdmin(tester, api);

      await _abrirAccionesDe(tester, 'Sara Dueña');
      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();

      expect(find.text('¿Desactivar la cuenta?'), findsOneWidget);
      expect(find.textContaining('Sus reservas y su historial se conservan.'), findsOneWidget);
      expect(api.peticiones.any((p) => p.contains('PATCH /api/usuarios/3/rol')), isFalse);

      await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
      await tester.pumpAndSettle();

      expect(api.peticiones.contains('PATCH /api/usuarios/3/rol {"activo":false}'), isTrue);
    });

    testWidgets('cancelar la confirmación no manda nada al backend', (tester) async {
      final api = _api();
      await _entrarComoAdmin(tester, api);

      await _abrirAccionesDe(tester, 'Sara Dueña');
      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(api.peticiones.any((p) => p.contains('PATCH /api/usuarios')), isFalse);
    });

    testWidgets('una cuenta desactivada lo dice en la tarjeta y se puede activar', (tester) async {
      final api = _api();
      api.responder('GET', '/api/usuarios', {
        'usuarios': [
          {
            'id': 3,
            'nombre': 'Sara Dueña',
            'email': 'sara@correo.com',
            'rol': 'dueno',
            'activo': false,
            'canchas': 1,
            'reservas': 0,
          },
        ],
      });
      await _entrarComoAdmin(tester, api);

      expect(find.text('Cuenta desactivada: no puede iniciar sesión'), findsOneWidget);

      await _abrirAccionesDe(tester, 'Sara Dueña');
      expect(find.text('Activar cuenta'), findsOneWidget);
      await tester.tap(find.text('Activar cuenta'));
      await tester.pumpAndSettle();

      // Activar no pide confirmación: no es una acción destructiva.
      expect(find.text('¿Desactivar la cuenta?'), findsNothing);
      expect(api.peticiones.contains('PATCH /api/usuarios/3/rol {"activo":true}'), isTrue);
    });
  });

  group('reporte', () {
    testWidgets('muestra los tres totales y el desglose por cancha', (tester) async {
      await _entrarComoAdmin(tester, _api(), irA: _irAReporte);

      expect(find.text(r'Ingresos cobrados'), findsOneWidget);
      expect(find.text(r'$ 115.000'), findsOneWidget);
      expect(find.text('Reservas'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('Usuarios')),
        findsOneWidget,
      );
      expect(find.text('4'), findsOneWidget);

      // Las dos gráficas comparten el widget de barras pero no sus cifras: si los
      // importes por día fueran los mismos por cancha, la app no mostraría en qué
      // serie está cada uno.
      expect(find.text('Cancha El Retiro'), findsOneWidget);
      expect(find.text(r'$ 75.000 · 2 res.'), findsOneWidget);
      expect(find.text(r'$ 40.000 · 1 res.'), findsOneWidget);
      expect(find.text(r'$ 90.000 · 3 res.'), findsOneWidget);
      expect(find.text(r'$ 25.000 · 1 res.'), findsOneWidget);
    });

    testWidgets('los estados salen con su nombre, no sólo como número', (tester) async {
      await _entrarComoAdmin(tester, _api(), irA: _irAReporte);

      expect(find.text('Pendiente de pago: 2'), findsOneWidget);
      expect(find.text('Confirmada: 2'), findsOneWidget);
      expect(find.text('Cancelada: 1'), findsOneWidget);
    });

    testWidgets('sin reservas el reporte lo explica en vez de mostrar ceros solos', (tester) async {
      final api = _api();
      api.responder('GET', '/api/reporte', {
        'generado_en': '2026-09-20T10:00:00+00:00',
        'ingresos': {'total': 0, 'por_cancha': <Object>[], 'por_dia': <Object>[]},
        'reservas': {'total': 0, 'por_estado': <String, Object>{}, 'por_cancha': <Object>[]},
        'usuarios': {'total': 2, 'por_rol': {'cliente': 1, 'admin': 1}, 'inactivos': 0},
      });

      await _entrarComoAdmin(tester, api, irA: _irAReporte);

      expect(find.textContaining('Todavía no hay reservas cobradas.'), findsOneWidget);
      expect(find.text('Ingresos por cancha'), findsNothing);
    });

    testWidgets('si el reporte falla se muestra el mensaje y un reintento', (tester) async {
      final api = _api()
        ..fallarLaProxima('GET', '/api/reporte', 500, 'El servidor tuvo un problema.');

      await _entrarComoAdmin(tester, api, irA: _irAReporte);

      expect(find.textContaining('El servidor tuvo un problema.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
    });
  });

  group('salir del panel', () {
    testWidgets('cerrar sesión limpia usuarios y reporte', (tester) async {
      await _entrarComoAdmin(tester, _api());

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Cerrar sesión'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
    });
  });
}

Future<void> _entrarComoAdmin(
  WidgetTester tester,
  FakeApi api, {
  Future<void> Function(WidgetTester)? irA,
}) async {
  await tester.pumpWidget(
    appDePrueba(api, storage: sesuraDePrueba(rol: 'admin', nombre: 'Admin GoalTime')),
  );
  await tester.pumpAndSettle();
  if (irA != null) await irA(tester);
}

Future<void> _irAReporte(WidgetTester tester) async {
  await tester.tap(find.text('Reporte'));
  await tester.pumpAndSettle();
}

Future<void> _abrirAccionesDe(WidgetTester tester, String nombre) async {
  await tester.tap(find.text(nombre));
  await tester.pumpAndSettle();
}

FakeApi _api() {
  final api = FakeApi();
  adminDePrueba(api);
  return api;
}

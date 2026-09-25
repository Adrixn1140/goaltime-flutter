import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/core/storage/token_storage.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('sin sesión guardada la app arranca en el login', (tester) async {
    final api = FakeApi();

    await tester.pumpWidget(
      appDePrueba(api, storage: TokenStorage(MemoriaSegura())),
    );
    await tester.pumpAndSettle();

    expect(find.text('GoalTime'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
  });

  testWidgets('con sesión guardada entra directo a las canchas', (tester) async {
    final api = FakeApi();
    canchasDePrueba(api);

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsNothing);
    expect(find.text('Cancha El Retiro'), findsOneWidget);
    expect(find.text('Cancha Laquina'), findsOneWidget);
  });

  testWidgets('el formulario valida antes de llamar al backend', (tester) async {
    final api = FakeApi();

    await tester.pumpWidget(appDePrueba(api, storage: TokenStorage(MemoriaSegura())));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'no-es-correo');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Ese correo no parece válido'), findsOneWidget);
    expect(api.peticiones, isEmpty);
  });

  testWidgets('una contraseña corta de registro se explica antes de enviar', (tester) async {
    final api = FakeApi();

    await tester.pumpWidget(appDePrueba(api, storage: TokenStorage(MemoriaSegura())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Ana Cliente');
    await tester.enterText(find.byType(TextFormField).at(1), 'ana@correo.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'corta');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('La contraseña necesita al menos 8 caracteres'), findsOneWidget);
    expect(api.peticiones, isEmpty);
  });

  testWidgets('un login correcto guarda la sesión y entra a las canchas', (tester) async {
    final api = FakeApi();
    canchasDePrueba(api);
    api.responder('POST', '/api/login', {
      'access_token': 'jwt-de-prueba',
      'rol': 'cliente',
      'usuario': {'id': 1, 'nombre': 'Ana Cliente', 'email': 'ana@correo.com', 'rol': 'cliente'},
    });

    await tester.pumpWidget(appDePrueba(api, storage: TokenStorage(MemoriaSegura())));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'ana@correo.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secreto123');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Cancha El Retiro'), findsOneWidget);
    expect(api.peticiones.first, contains('POST /api/login'));
  });

  testWidgets('credenciales incorrectas se muestran con el mensaje del backend', (tester) async {
    final api = FakeApi();
    api.error('POST', '/api/login', 401, 'Credenciales inválidas');

    await tester.pumpWidget(appDePrueba(api, storage: TokenStorage(MemoriaSegura())));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'ana@correo.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'mala');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    // `pumpAndSettle` avanzaría el reloj lo suficiente para que el `SnackBar` se cerrara
    // solo: aquí interesa verlo en pantalla, no esperar a que desaparezca.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Credenciales inválidas'), findsOneWidget);
    // Sigue en el login: no se entra a la app con una sesión inválida.
    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
  });

  testWidgets('registro crea la cuenta y entra con el rol cliente', (tester) async {
    final api = FakeApi();
    canchasDePrueba(api);
    api.responder('POST', '/api/register', {
      'access_token': 'jwt-nuevo',
      'rol': 'cliente',
      'usuario': {'id': 2, 'nombre': 'Nuevo Cliente', 'email': 'nuevo@correo.com', 'rol': 'cliente'},
    });

    await tester.pumpWidget(appDePrueba(api, storage: TokenStorage(MemoriaSegura())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Nuevo Cliente');
    await tester.enterText(find.byType(TextFormField).at(1), 'nuevo@correo.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'secreto123');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('Cancha El Retiro'), findsOneWidget);
    expect(api.peticiones.first, contains('POST /api/register'));
  });

  testWidgets('cerrar sesión borra la sesión y vuelve al login', (tester) async {
    final api = FakeApi();
    canchasDePrueba(api);
    api.responder('GET', '/api/mis-reservas', <Object>[]);

    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Cliente'), findsOneWidget);
    expect(find.text('ana@correo.com'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();

    // El diálogo pide confirmación: sin ella, un toque de más cerraría la sesión.
    expect(find.text('¿Cerrar sesión?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Cerrar sesión'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
  });
}

/// App con el backend falso inyectado en los dos providers de infraestructura.

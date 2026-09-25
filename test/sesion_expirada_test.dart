import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/core/network/auth_interceptor.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('un 401 con token cierra la sesión y devuelve al login', (tester) async {
    final api = FakeApi();
    canchasDePrueba(api);
    api.responder('GET', '/api/mis-reservas', [reservaDePrueba()]);
    // El token sigue en el almacenamiento pero ya no vale: el backend responde 401.
    api.error('GET', '/api/mis-reservas', 401, 'La sesión no es válida');

    final storage = sesuraDePrueba();
    await tester.pumpWidget(appDePrueba(api, storage: storage));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mis reservas'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
    expect(await storage.accessToken, isNull);
  });

  group('sesión expirada', () {
    DioException errorDe(int status, {required bool conToken}) {
      return DioException(
        requestOptions: RequestOptions(
          path: '/api/mis-reservas',
          headers: conToken ? {'Authorization': 'Bearer token'} : {},
        ),
        response: Response<dynamic>(requestOptions: RequestOptions(path: ''), statusCode: status),
      );
    }

    test('un 401 en una petición con token cierra la sesión', () {
      expect(sesionExpirada(errorDe(401, conToken: true)), isTrue);
    });

    test('un 401 en el login no cierra sesión: son credenciales incorrectas', () {
      // El login nunca lleva Authorization; si cerrara sesión, el mensaje de error
      // desaparecería y el usuario vería el formulario vacío sin explicación.
      expect(sesionExpirada(errorDe(401, conToken: false)), isFalse);
    });

    test('un 403 no cierra sesión: es una falta de permisos, no una sesión muerta', () {
      expect(sesionExpirada(errorDe(403, conToken: true)), isFalse);
    });

    test('un error de red no cierra sesión: no sabemos nada del token', () {
      final sinRespuesta = DioException(
        requestOptions: RequestOptions(
          path: '/api/mis-reservas',
          headers: {'Authorization': 'Bearer token'},
        ),
      );
      expect(sesionExpirada(sinRespuesta), isFalse);
    });
  });
}


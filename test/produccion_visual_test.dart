import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/core/network/api_client.dart';
import 'package:goaltime_flutter/core/network/api_exception.dart';
import 'package:goaltime_flutter/core/theme/app_theme.dart';
import 'package:goaltime_flutter/features/cliente/presentation/canchas_screen.dart';

import 'support/fake_api.dart';

void _celularConTextoGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  testWidgets('catálogo admite nombre largo y tarifa con texto al 200%', (
    tester,
  ) async {
    _celularConTextoGrande(tester);
    final api = FakeApi()
      ..responder('GET', '/api/canchas', [
        {
          'id': 1,
          'nombre': 'Cancha deportiva de nombre largo en Riohacha',
          'ubicacion': 'Carrera 100 número 200, barrio de ubicación extensa',
          'foto': '',
          'tarifa_base': 10000000.0,
        },
      ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api.construir())],
        child: MaterialApp(theme: AppTheme.light, home: const CanchasScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(r'$ 10.000.000'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(r'$ 10.000.000'), findsOneWidget);
  });

  testWidgets('precio y botón del asistente se acomodan sin desbordarse', (
    tester,
  ) async {
    _celularConTextoGrande(tester);
    final fecha = DateTime.now()
        .add(const Duration(days: 1))
        .toIso8601String()
        .split('T')
        .first;
    final api = FakeApi()
      ..responder('POST', '/api/asistente', {
        'respuesta': 'Encontré un horario disponible.',
        'motor': 'mock',
        'sugerencias': [
          {
            'cancha_id': 1,
            'cancha': 'Cancha con nombre largo para probar la pantalla',
            'fecha': fecha,
            'horario_id': 1,
            'hora_inicio': '16:00',
            'hora_fin': '18:00',
            'tarifa': 10000000.0,
          },
        ],
      });
    canchasDePrueba(api);
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Quiero jugar mañana');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Reservar'), findsOneWidget);
  });

  test('certificado inválido no sugiere desactivar la seguridad', () {
    final error = ApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/api/login'),
        type: DioExceptionType.badCertificate,
      ),
    );
    expect(error.texto, contains('conexión segura'));
    expect(error.texto, contains('No omitas'));
  });

  test('servicio temporalmente caído explica que se puede reintentar', () {
    final error = ApiException.fromResponse(503, null);
    expect(error.esReintentable, isTrue);
    expect(error.texto, contains('Espera un momento'));
  });
}

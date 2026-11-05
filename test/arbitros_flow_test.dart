import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/core/storage/token_storage.dart';
import 'package:goaltime_flutter/features/arbitros/data/arbitros_repository.dart';
import 'package:goaltime_flutter/features/asistente_ia/data/models.dart';

import 'support/fake_api.dart';

Map<String, Object> perfil({bool publicado = false}) => {
  'id': 1,
  'nombre': 'Ana Árbitra',
  'ciudad': 'Riohacha',
  'celular': '3000000000',
  'experiencia': 3,
  'biografia': 'Fútbol aficionado',
  'tarifa': 55000.5,
  'disponible': true,
  'publicado': publicado,
};

Future<void> tapTexto(WidgetTester tester, String texto) async {
  await tester.ensureVisible(find.text(texto));
  await tester.pumpAndSettle();
  await tester.tap(find.text(texto));
  await tester.pumpAndSettle();
}

Future<void> campo(WidgetTester tester, String etiqueta, String valor) async {
  final finder = find.widgetWithText(TextFormField, etiqueta);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, valor);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'perfil parsea tarifa y acciones del chat descartan destinos desconocidos',
    () {
      expect(PerfilArbitro.fromJson(perfil()).tarifa, 55000.5);
      final respuesta = RespuestaAsistente.fromJson({
        'acciones': [
          {'destino': 'https://malicioso.test', 'etiqueta': 'No abrir'},
          {'destino': 'arbitros', 'etiqueta': 'Ver árbitros'},
        ],
      });
      expect(respuesta.acciones.single.destino, 'arbitros');
    },
  );

  testWidgets('cliente abre directorio, filtra por ciudad y solo disponibles', (
    tester,
  ) async {
    final api = FakeApi()
      ..responder('GET', '/api/arbitros', [perfil(publicado: true)]);
    canchasDePrueba(api);
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Árbitros'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ana Árbitra'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ana Árbitra'), findsOneWidget);
    expect(find.textContaining('55.000,50'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Riohacha');
    await tester.tap(find.byTooltip('Buscar árbitros'));
    await tester.pumpAndSettle();
    await tapTexto(tester, 'Solo disponibles');
    expect(api.parametrosConsulta.last, {
      'q': 'Riohacha',
      'disponible': 'true',
    });
  });

  testWidgets('registro permite elegir árbitro y abre su perfil', (
    tester,
  ) async {
    final api = FakeApi()
      ..responder('POST', '/api/register', {
        'access_token': 'token-arbitro',
        'rol': 'arbitro',
        'usuario': {
          'id': 22,
          'nombre': 'Ana Árbitra',
          'email': 'ana@test.co',
          'rol': 'arbitro',
        },
      })
      ..responder('GET', '/api/arbitros/mi-perfil', null);
    await tester.pumpWidget(
      appDePrueba(api, storage: TokenStorage(MemoriaSegura())),
    );
    await tester.pumpAndSettle();
    await tapTexto(tester, '¿No tienes cuenta? Regístrate');
    await tapTexto(tester, 'Árbitro');
    await tester.enterText(find.byType(TextFormField).at(0), 'Ana Árbitra');
    await tester.enterText(find.byType(TextFormField).at(1), 'ana@test.co');
    await tester.enterText(find.byType(TextFormField).at(2), 'Goaltime123!');
    await tapTexto(tester, 'Crear cuenta');
    expect(find.text('Mi perfil arbitral'), findsWidgets);
    expect(
      api.peticiones.any(
        (p) =>
            p.contains('POST /api/register') &&
            p.contains('"tipo_cuenta":"arbitro"'),
      ),
      isTrue,
    );
    expect(api.peticiones, isNot(contains('GET /api/equipos')));
  });

  testWidgets('árbitro publica perfil y ve confirmación al guardar', (
    tester,
  ) async {
    final api = FakeApi()
      ..responder('GET', '/api/arbitros/mi-perfil', null)
      ..responder('PUT', '/api/arbitros/mi-perfil', perfil(publicado: true));
    api.alRecibir(
      'PUT',
      '/api/arbitros/mi-perfil',
      (a) => a.responder(
        'GET',
        '/api/arbitros/mi-perfil',
        perfil(publicado: true),
      ),
    );
    await tester.pumpWidget(
      appDePrueba(api, storage: sesuraDePrueba(rol: 'arbitro')),
    );
    await tester.pumpAndSettle();
    await campo(tester, 'Ciudad', 'Riohacha');
    await campo(tester, 'Celular de contacto', '3000000000');
    await campo(tester, 'Años de experiencia', '3');
    await campo(tester, 'Tarifa por partido (COP)', '55000,50');
    await tester.scrollUntilVisible(
      find.text('Publicar perfil'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapTexto(tester, 'Publicar perfil');
    await tester.scrollUntilVisible(
      find.text('Guardar perfil'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapTexto(tester, 'Guardar perfil');
    expect(
      api.peticiones.any(
        (p) =>
            p.startsWith('PUT /api/arbitros/mi-perfil') &&
            p.contains('"publicado":true') &&
            p.contains('"tarifa":"55000.50"'),
      ),
      isTrue,
    );
    expect(
      find.text('Perfil guardado y publicado en el directorio.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'ocultar un perfil publicado envía false y mantiene el formulario si falla',
    (tester) async {
      final api = FakeApi()
        ..responder('GET', '/api/arbitros/mi-perfil', perfil(publicado: true))
        ..error(
          'PUT',
          '/api/arbitros/mi-perfil',
          503,
          'Servidor no disponible',
        );
      await tester.pumpWidget(
        appDePrueba(api, storage: sesuraDePrueba(rol: 'arbitro')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Publicar perfil'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapTexto(tester, 'Publicar perfil');
      await tester.scrollUntilVisible(
        find.text('Guardar perfil'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapTexto(tester, 'Guardar perfil');
      expect(
        api.peticiones.any(
          (p) => p.startsWith('PUT ') && p.contains('"publicado":false'),
        ),
        isTrue,
      );
      expect(find.textContaining('Servidor'), findsWidgets);
      expect(find.text('Guardar perfil'), findsOneWidget);
    },
  );

  testWidgets('directorio vacío y error permiten reintentar', (tester) async {
    final api = FakeApi()
      ..responder('GET', '/api/arbitros', <Object>[])
      ..fallarLaProxima('GET', '/api/arbitros', 503, 'No disponible');
    canchasDePrueba(api);
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Árbitros'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Reintentar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapTexto(tester, 'Reintentar');
    expect(find.textContaining('No hay árbitros publicados'), findsOneWidget);
  });

  testWidgets('asistente ofrece acceso a directorio sin reservar', (
    tester,
  ) async {
    final api = FakeApi()
      ..responder('POST', '/api/asistente', {
        'respuesta': 'Consulta los perfiles publicados.',
        'sugerencias': <Object>[],
        'motor': 'guia-local',
        'acciones': [
          {'destino': 'arbitros', 'etiqueta': 'Ver árbitros'},
        ],
      })
      ..responder('GET', '/api/arbitros', <Object>[]);
    canchasDePrueba(api);
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asistente'));
    await tester.pumpAndSettle();
    await tapTexto(tester, 'Árbitros disponibles');
    await tapTexto(tester, 'Ver árbitros');
    expect(find.text('Nombre o ciudad'), findsOneWidget);
    expect(
      api.peticiones.any((p) => p.startsWith('POST /api/reservas')),
      isFalse,
    );
  });
}

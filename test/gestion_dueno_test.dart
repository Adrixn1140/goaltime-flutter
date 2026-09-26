import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

/// Gestión del dueño: canchas, horarios y reservas (`spec.md 3.4`).
///
/// Lo que se comprueba aquí no es que la pantalla se pinte, sino las tres reglas que el
/// dueño necesita que se cumplan sin que él las conozca: lo que no se puede confirmar
/// explica por qué, lo que el backend rechaza muestra su frase, y cada acción que
/// cambia algo en el servidor manda lo que el contrato dice.
void main() {
  group('canchas', () {
    testWidgets('lista las canchas con sus horarios y su tarifa', (tester) async {
      await _entrarComoDueno(tester, _api());

      expect(find.text('Cancha El Retiro'), findsOneWidget);
      expect(find.text('2 horarios'), findsOneWidget);
      expect(find.text(r'desde $ 45.000'), findsOneWidget);
    });

    testWidgets('una cancha sin horarios avisa de que no puede reservarse', (tester) async {
      await _entrarComoDueno(tester, _api());

      expect(
        find.text('Agrega horarios para que los clientes puedan reservar.'),
        findsOneWidget,
      );
    });

    testWidgets('una cancha dada de baja se distingue de la activa', (tester) async {
      await _entrarComoDueno(tester, _api());

      expect(find.text('Inactiva'), findsOneWidget);
    });

    testWidgets('sin canchas se explica el siguiente paso', (tester) async {
      final api = _api();
      api.responder('GET', '/api/gestion/canchas', <Object>[]);

      await _entrarComoDueno(tester, api);

      expect(find.textContaining('Todavía no tienes canchas'), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'Nueva cancha'), findsOneWidget);
    });

    testWidgets('si la lista falla se muestra el mensaje y un reintento', (tester) async {
      final api = _api();
      api.fallarLaProxima('GET', '/api/gestion/canchas', 500, 'El servidor tuvo un problema.');

      await _entrarComoDueno(tester, api);

      expect(find.textContaining('El servidor tuvo un problema.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
    });
  });

  group('alta y edición de cancha', () {
    testWidgets('crear una cancha manda lo que se escribió', (tester) async {
      final api = _api();
      api.responder('POST', '/api/gestion/canchas', {
        'id': 3,
        'nombre': 'Cancha Nueva',
        'ubicacion': 'Av 80 # 10-20',
        'foto': '',
        'activo': true,
        'dueno_id': 5,
        'total_horarios': 0,
        'tarifa_base': null,
      }, status: 201);

      await _entrarComoDueno(tester, api);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nueva cancha'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Cancha Nueva');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dirección'),
        'Av 80 # 10-20',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cancha'));
      await tester.pumpAndSettle();

      expect(
        api.peticiones.any(
          (p) => p == 'POST /api/gestion/canchas {"nombre":"Cancha Nueva",'
              '"ubicacion":"Av 80 # 10-20"}',
        ),
        isTrue,
        reason: 'el POST debe llevar sólo lo que se escribió, sin dueno_id',
      );
      expect(find.text('Cancha creada'), findsOneWidget);
    });

    testWidgets('sin nombre el formulario no llama al backend', (tester) async {
      final api = _api();
      await _entrarComoDueno(tester, api);
      final peticionesAntes = api.peticiones.length;

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nueva cancha'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Dirección'), 'Cra 1 # 2-3');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cancha'));
      await tester.pumpAndSettle();

      expect(find.text('El nombre es obligatoria'), findsOneWidget);
      expect(api.peticiones.length, peticionesAntes);
    });

    testWidgets('un 400 del backend se muestra sin cerrar el formulario', (tester) async {
      final api = _api();
      api.error('POST', '/api/gestion/canchas', 400, 'nombre no puede superar 120 caracteres');

      await _entrarComoDueno(tester, api);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nueva cancha'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Cancha');
      await tester.enterText(find.widgetWithText(TextFormField, 'Dirección'), 'Cra 1');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cancha'));
      await tester.pumpAndSettle();

      expect(find.textContaining('nombre no puede superar 120 caracteres'), findsOneWidget);
      // El formulario sigue abierto: se puede corregir y reintentar sin escribirlo todo otra vez.
      expect(find.widgetWithText(TextFormField, 'Nombre'), findsOneWidget);
    });

    testWidgets('editar carga los datos actuales y manda el PATCH', (tester) async {
      final api = _api();
      api.responder('PATCH', '/api/gestion/canchas/1', {
        'id': 1,
        'nombre': 'Cancha El Retiro Sur',
        'ubicacion': 'Cra 45 # 12-30',
        'foto': '',
        'activo': true,
        'dueno_id': 5,
        'total_horarios': 2,
        'tarifa_base': 45000.0,
      });

      await _entrarComoDueno(tester, api);
      await _abrirAccionesDe(tester, 'Cancha El Retiro');
      await tester.tap(find.text('Editar datos'));
      await tester.pumpAndSettle();

      expect(find.text('Editar cancha'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Nombre')).controller!.text,
        'Cancha El Retiro',
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Cancha El Retiro Sur',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar cambios'));
      await tester.pumpAndSettle();

      // El formulario manda los dos campos que el dueño ve; el PATCH parcial del
      // repositorio se comprueba en la reactivación, que sólo envía `activo`.
      expect(
        api.peticiones.any(
          (p) => p == 'PATCH /api/gestion/canchas/1 {"nombre":"Cancha El Retiro Sur",'
              '"ubicacion":"Cra 45 # 12-30"}',
        ),
        isTrue,
      );
    });

    testWidgets('dar de baja pide confirmación y usa DELETE', (tester) async {
      final api = _api();
      api.responder('DELETE', '/api/gestion/canchas/1', '', status: 204);
      api.alRecibir('DELETE', '/api/gestion/canchas/1', (api) {
        api.responder('GET', '/api/gestion/canchas', [
          {'id': 1, 'nombre': 'Cancha El Retiro', 'ubicacion': 'Cra 45 # 12-30', 'foto': '',
           'activo': false, 'dueno_id': 5, 'total_horarios': 2, 'tarifa_base': 45000.0},
        ]);
      });

      await _entrarComoDueno(tester, api);
      await _abrirAccionesDe(tester, 'Cancha El Retiro');
      // La hoja es desplazable y en una pantalla de 600 px la última fila queda fuera:
      // el dueño la baja deslizando, y el test hace lo mismo.
      await tester.ensureVisible(find.text('Dar de baja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dar de baja'));
      await tester.pumpAndSettle();

      // Nada ocurre hasta que el dueño confirma: la baja esconde la cancha del catálogo.
      expect(find.text('¿Dar de baja la cancha?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Dar de baja'));
      await tester.pumpAndSettle();

      expect(api.peticiones.any((p) => p == 'DELETE /api/gestion/canchas/1'), isTrue);
      expect(find.text('Cancha dada de baja'), findsOneWidget);
    });

    testWidgets('reactivar una cancha inactiva usa PATCH con activo true', (tester) async {
      final api = _api();
      api.responder('PATCH', '/api/gestion/canchas/2', {
        'id': 2, 'nombre': 'Cancha Laquina', 'ubicacion': 'Cra 45 # 12-30', 'foto': '',
        'activo': true, 'dueno_id': 5, 'total_horarios': 0, 'tarifa_base': null,
      });

      await _entrarComoDueno(tester, api);
      await _abrirAccionesDe(tester, 'Cancha Laquina');
      await tester.ensureVisible(find.text('Reactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reactivar'));
      await tester.pumpAndSettle();

      expect(
        api.peticiones.any((p) => p == 'PATCH /api/gestion/canchas/2 {"activo":true}'),
        isTrue,
      );
    });
  });

  group('horarios', () {
    testWidgets('se listan agrupados por día con el nombre del día', (tester) async {
      await _entrarComoDueno(tester, _api(), irA: _irAHorarios);

      expect(find.text('Lunes'), findsOneWidget);
      expect(find.text('Miércoles'), findsOneWidget);
      expect(find.text('08:00 – 10:00'), findsOneWidget);
      expect(find.text(r'$ 55.000'), findsOneWidget);
    });

    testWidgets('crear un horario manda día, horas y tarifa', (tester) async {
      final api = _api();
      api.responder('POST', '/api/gestion/canchas/1/horarios', {
        'id': 12, 'cancha_id': 1, 'dia': 0, 'hora_inicio': '19:00', 'hora_fin': '21:00',
        'tarifa': 70000.0,
      }, status: 201);

      await _entrarComoDueno(tester, api, irA: _irAHorarios);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nuevo horario'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Tarifa'), '70000');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear horario'));
      await tester.pumpAndSettle();

      // El día por defecto es el de hoy, que es el que el dueño quiere abrir primero; y
      // las horas por defecto son 08:00-10:00. Se comparan contra lo que el formulario
      // realmente tiene, no contra un día fijo: el test debe pasar también los domingos.
      final diaDeHoy = DateTime.now().weekday - 1;
      expect(
        api.peticiones.any(
          (p) => p == 'POST /api/gestion/canchas/1/horarios {"dia":$diaDeHoy,'
              '"hora_inicio":"08:00","hora_fin":"10:00","tarifa":70000.0}',
        ),
        isTrue,
        reason: 'las horas y el día por defecto del formulario deben viajar tal cual',
      );
      expect(find.text('Horario creado'), findsOneWidget);
    });

    testWidgets('una tarifa en cero se frena en el formulario', (tester) async {
      final api = _api();
      await _entrarComoDueno(tester, api, irA: _irAHorarios);
      final antes = api.peticiones.length;

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nuevo horario'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Tarifa'), '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear horario'));
      await tester.pumpAndSettle();

      expect(find.text('La tarifa debe ser mayor que cero'), findsOneWidget);
      expect(api.peticiones.length, antes);
    });

    testWidgets('un 422 por solape muestra lo que dice el backend', (tester) async {
      final api = _api();
      api.error(
        'POST',
        '/api/gestion/canchas/1/horarios',
        422,
        'Ese horario se solapa con otro de la misma cancha en ese día',
      );

      await _entrarComoDueno(tester, api, irA: _irAHorarios);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nuevo horario'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Tarifa'), '70000');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear horario'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Ese horario se solapa con otro de la misma cancha'),
        findsOneWidget,
      );
    });

    testWidgets('borrar un horario pide confirmación y usa DELETE', (tester) async {
      final api = _api();
      api.responder('DELETE', '/api/gestion/canchas/1/horarios/10', '', status: 204);

      await _entrarComoDueno(tester, api, irA: _irAHorarios);
      await tester.tap(find.byTooltip('Eliminar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(
        api.peticiones.any((p) => p == 'DELETE /api/gestion/canchas/1/horarios/10'),
        isTrue,
      );
    });

    testWidgets('un horario con reservas explica que no se puede eliminar', (tester) async {
      final api = _api();
      api.error(
        'DELETE',
        '/api/gestion/canchas/1/horarios/10',
        409,
        'El horario tiene reservas y no se puede eliminar',
      );

      await _entrarComoDueno(tester, api, irA: _irAHorarios);
      await tester.tap(find.byTooltip('Eliminar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('El horario tiene reservas y no se puede eliminar'),
        findsOneWidget,
      );
    });
  });

  group('reservas', () {
    testWidgets('lista las reservas con quién reservó', (tester) async {
      await _entrarComoDueno(tester, _api(), irA: _irAReservas);

      expect(find.text('Carla Cliente'), findsOneWidget);
      expect(find.text('Julián Pérez'), findsOneWidget);
      expect(find.text('Pendiente de pago'), findsNWidgets(2));
      expect(find.text('Cancelada'), findsOneWidget);
    });

    testWidgets('confirmar sólo se ofrece con el pago aprobado', (tester) async {
      await _entrarComoDueno(tester, _api(), irA: _irAReservas);

      // La reserva de Carla (pago aprobado) trae el botón; la de Julián (pago pendiente),
      // no, y en su lugar dice por qué.
      expect(find.widgetWithText(FilledButton, 'Confirmar'), findsOneWidget);
      expect(find.text('El pago no está aprobado todavía'), findsOneWidget);
    });

    testWidgets('confirmar manda la acción y refresca la lista', (tester) async {
      final api = _api();
      api.responder('PATCH', '/api/gestion/reservas/21', {
        'reserva_id': 21,
        'cancha': {'id': 1, 'nombre': 'Cancha El Retiro', 'ubicacion': 'Cra 45 # 12-30', 'activo': true},
        'horario': {'id': 10, 'hora_inicio': '08:00', 'hora_fin': '10:00', 'tarifa': 60000.0},
        'cliente': {'id': 63, 'nombre': 'Carla Cliente'},
        'fecha': _mananaIso(),
        'estado': 'confirmada',
        'pago': {'id': 42, 'reserva_id': 21, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'aprobado'},
      });
      api.alRecibir('PATCH', '/api/gestion/reservas/21', (api) {
        api.responder('GET', '/api/gestion/canchas/1/reservas', [
          _reservaConfirmada(),
        ]);
      });

      await _entrarComoDueno(tester, api, irA: _irAReservas);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(
        api.peticiones.any((p) => p == 'PATCH /api/gestion/reservas/21 {"accion":"confirmar"}'),
        isTrue,
      );
      expect(find.text('Reserva confirmada'), findsOneWidget);
      // El estado nuevo viene de la lista re-preguntada, no de la tarjeta anterior.
      expect(
        api.peticiones.where((p) => p.startsWith('GET /api/gestion/canchas/1/reservas')).length,
        greaterThanOrEqualTo(2),
      );
    });

    testWidgets('un 422 al confirmar muestra el motivo y refresca', (tester) async {
      final api = _api();
      api.error(
        'PATCH',
        '/api/gestion/reservas/21',
        422,
        'No se puede confirmar una reserva sin pago aprobado',
      );

      await _entrarComoDueno(tester, api, irA: _irAReservas);
      final antes = api.peticiones
          .where((p) => p.startsWith('GET /api/gestion/canchas/1/reservas'))
          .length;
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se puede confirmar una reserva sin pago aprobado'),
        findsOneWidget,
      );
      // La tarjeta que se queda mostrando el estado real, no el que el dueño creía.
      expect(
        api.peticiones.where((p) => p.startsWith('GET /api/gestion/canchas/1/reservas')).length,
        greaterThan(antes),
      );
    });

    testWidgets('cancelar pide confirmación antes de anular la reserva', (tester) async {
      final api = _api();
      await _entrarComoDueno(tester, api, irA: _irAReservas);
      final antes = api.peticiones.length;

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar').first);
      await tester.pumpAndSettle();

      expect(find.text('¿Cancelar la reserva?'), findsOneWidget);
      expect(find.textContaining('El pago no se devuelve'), findsOneWidget);
      expect(api.peticiones.length, antes, reason: 'nada se envía hasta confirmar');

      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar reserva'));
      await tester.pumpAndSettle();

      expect(
        api.peticiones.any((p) => p == 'PATCH /api/gestion/reservas/21 {"accion":"cancelar"}'),
        isTrue,
      );
    });

    testWidgets('una reserva cancelada no ofrece ni confirmar ni cancelar', (tester) async {
      await _entrarComoDueno(tester, _api(), irA: _irAReservas);

      // Ana Ruiz es la única cancelada, así que su tarjeta es la única sin acciones.
      expect(find.widgetWithText(OutlinedButton, 'Cancelar'), findsNWidgets(2));
    });

    testWidgets('sin reservas se explica que la cancha está libre', (tester) async {
      final api = _api();
      api.responder('GET', '/api/gestion/canchas/1/reservas', <Object>[]);

      await _entrarComoDueno(tester, api, irA: _irAReservas);

      expect(find.textContaining('Todavía nadie ha reservado'), findsOneWidget);
    });
  });
}

Future<void> _entrarComoDueno(
  WidgetTester tester,
  FakeApi api, {
  Future<void> Function(WidgetTester)? irA,
}) async {
  await tester.pumpWidget(
    appDePrueba(api, storage: sesuraDePrueba(rol: 'dueno', nombre: 'Diego Dueño')),
  );
  await tester.pumpAndSettle();
  if (irA != null) await irA(tester);
}

Future<void> _irAHorarios(WidgetTester tester) async {
  await _abrirAccionesDe(tester, 'Cancha El Retiro');
  await tester.tap(find.text('Horarios'));
  await tester.pumpAndSettle();
}

Future<void> _irAReservas(WidgetTester tester) async {
  await _abrirAccionesDe(tester, 'Cancha El Retiro');
  await tester.tap(find.text('Reservas'));
  await tester.pumpAndSettle();
}

Future<void> _abrirAccionesDe(WidgetTester tester, String cancha) async {
  await tester.tap(find.text(cancha));
  await tester.pumpAndSettle();
}

FakeApi _api() {
  final api = FakeApi();
  canchasDeGestion(api);
  horariosDePrueba(api);
  reservasDeGestion(api);
  return api;
}

Map<String, Object> _reservaConfirmada() => {
  'reserva_id': 21,
  'cancha': {'id': 1, 'nombre': 'Cancha El Retiro', 'ubicacion': 'Cra 45 # 12-30', 'activo': true},
  'horario': {'id': 10, 'hora_inicio': '08:00', 'hora_fin': '10:00', 'tarifa': 60000.0},
  'cliente': {'id': 63, 'nombre': 'Carla Cliente'},
  'fecha': _mananaIso(),
  'estado': 'confirmada',
  'pago': {'id': 42, 'reserva_id': 21, 'monto': 60000.0, 'metodo': 'mock', 'estado': 'aprobado'},
};

String _mananaIso() {
  final manana = DateTime.now().add(const Duration(days: 1));
  return '${manana.year.toString().padLeft(4, '0')}-'
      '${manana.month.toString().padLeft(2, '0')}-'
      '${manana.day.toString().padLeft(2, '0')}';
}

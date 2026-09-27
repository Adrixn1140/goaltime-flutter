/// Contrato de la app contra el backend de verdad (spec.md 7.4).
///
/// `test/support/fake_api.dart` reimplementa a mano el JSON que devuelve Flask. Es cómodo
/// y rápido, pero es una **copia**: si el backend renombra un campo o cambia una regla, los
/// tests de widget siguen en verde y el error aparece en el dispositivo, delante del
/// profesor. Este archivo es el que se da cuenta.
///
/// Corre contra un backend real, así que necesita uno levantado:
///
/// ```sh
/// tool/verificar_integracion.sh          # levanta el compose y corre esto
/// # o, con el backend ya en marcha:
/// GOALTIME_API_URL=http://127.0.0.1:5000 flutter test test/contrato_real_test.dart
/// ```
///
/// Sin `GOALTIME_API_URL` los tests se omiten: la suite por defecto no habla con la red y
/// no depende de Docker. Es la misma política que la de `fake_api.dart` al revés.
///
/// Dos detalles que no son obvios y que costaron un spike:
///
/// - Va en `test/`, no en `integration_test/`: `flutter test integration_test/...` pide un
///   dispositivo conectado, y en un entorno sin emulador no correría.
/// - `HttpOverrides.global = null` es lo que habilita la red. `flutter_test` sustituye
///   `HttpClient` por uno que no habla con nadie, y `HttpOverrides.runZoned` no lo sortea
///   en esta versión. Se restaura al terminar para no afectarle al resto de la suite.
///
/// Y uno que no es del código sino del equipo donde corre: `flutter_tester` necesita
/// memoria para la red real y este equipo tiene 3.7 GB con el swap lleno. Cuando el kernel
/// lo mata, el síntoma es `did not complete` y `Bad state: Cannot close sink while adding
/// stream` —messages de `flutter_tools`, no de este archivo. Con memoria(headroom) esto
/// pasa; sin ella, el sitio donde debe correr es CI, que es donde está en el workflow.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goaltime_flutter/core/network/api_client.dart';
import 'package:goaltime_flutter/core/network/api_exception.dart';
import 'package:goaltime_flutter/core/storage/token_storage.dart';
import 'package:goaltime_flutter/features/auth/data/auth_repository.dart';
import 'package:goaltime_flutter/features/cliente/data/canchas_repository.dart';
import 'package:goaltime_flutter/features/cliente/data/models.dart';
import 'package:goaltime_flutter/features/usuarios/data/admin_repository.dart';
import 'package:goaltime_flutter/features/usuarios/data/models.dart' as admin;

/// Base del backend real. Sin esta variable los tests se omiten.
final String? urlApi = Platform.environment['GOALTIME_API_URL'];

/// Envuelve [accion] con la red habilitada.
///
/// `flutter_test` reemplaza `HttpClient` por un doble que responde a todo, para que un test
/// que se coma la red falle rápido en vez de colgarse. Aquí se quita el doble.
Future<T> conRedReal<T>(Future<T> Function() accion) async {
  final anterior = HttpOverrides.current;
  HttpOverrides.global = null;
  try {
    return await accion();
  } finally {
    HttpOverrides.global = anterior;
  }
}

/// Cliente real: el mismo `crearApiClient` de producción, con su interceptor de token y sus
/// timeouts. Sólo cambian dos cosas, ambas sólo aquí:
///
/// - La URL, que viene del entorno.
/// - El margen de espera, de 20 a 90 segundos. Verificar una contraseña con scrypt cuesta
///   alrededor de un segundo de CPU, y una máquina con dos núcleos saturados —o un runner
///   de CI con tres trabajos en paralelo— puede tardar bastante más. Los 20 segundos de la
///   app están puestos para una red móvil, no para una CPU compartida; cambiarlos en
///   producción para que el test pase en esta máquina sería arreglar el termómetro.
Dio crearDioReal(String baseUrl, {required TokenStorage storage, void Function()? alExpirar}) {
  final dio = crearApiClient(storage: storage, onSesionExpirada: alExpirar ?? () {});
  dio.options.baseUrl = baseUrl;
  dio.options.receiveTimeout = const Duration(seconds: 90);
  dio.options.connectTimeout = const Duration(seconds: 30);
  return dio;
}

void main() {
  final sinBackend = urlApi == null;

  group('contrato con el backend real', () {
    late TokenStorage storage;
    late Dio dio;
    late AuthRepository auth;
    late AdminRepository adminRepo;
    late CanchasRepository canchas;

    setUpAll(() {
      if (sinBackend) return;
      storage = TokenStorage(MemoriaSegura());
      dio = crearDioReal(urlApi!, storage: storage);
      auth = AuthRepository(dio, storage);
      adminRepo = AdminRepository(dio);
      canchas = CanchasRepository(dio);
    });

    setUp(() async {
      if (sinBackend) return;
      // Cada test arranca sin sesión: si uno deja el token guardado, el siguiente lo
      // heredaría y un fallo aparecería donde no es.
      await storage.clear();
    });

    Future<void> entrarComoAdmin() async {
      final sesion = await conRedReal(
        () => auth.login(email: 'admin@goaltime.test', password: 'Goaltime123!'),
      );
      expect(sesion.rol, 'admin');
    }

    test('el login real guarda la sesión como espera el TokenStorage', () async {
      if (sinBackend) return _omitir();

      final sesion = await conRedReal(
        () => auth.login(email: 'admin@goaltime.test', password: 'Goaltime123!'),
      );

      expect(sesion.token, isNotEmpty);
      expect(sesion.rol, 'admin');
      expect(sesion.usuario.email, 'admin@goaltime.test');
      // Lo que la app lee después de un reinicio: si el interceptor no encontrara el token
      // acá, todas las peticiones siguientes irían anónimas.
      expect(await storage.accessToken, sesion.token);
      expect(await storage.rol, 'admin');
    });

    test('el catálogo se parsea con el modelo real de la app', () async {
      if (sinBackend) return _omitir();

      final lista = await conRedReal(() => canchas.listar());

      expect(lista, isNotEmpty, reason: 'el seed deja 3 canchas activas');
      final primera = lista.first;
      expect(primera.nombre, isNotEmpty);
      expect(primera.ubicacion, isNotEmpty);
      // `tarifa_base` viene como número o null según tenga horarios. Lo que importa es que
      // el modelo lo soporte: si el backend lo mandara como texto, esto reventaría.
      final tarifa = primera.tarifaBase;
      expect(tarifa == null || tarifa > 0, isTrue);
    });

    test('la lista de usuarios trae rol, estado y los dos conteos', () async {
      if (sinBackend) return _omitir();
      await entrarComoAdmin();

      final usuarios = await conRedReal(() => adminRepo.listarUsuarios());

      expect(usuarios.length, greaterThanOrEqualTo(4));
      final roles = usuarios.map((u) => u.rol).toSet();
      expect(
        roles,
        containsAll(<admin.RolUsuario>[
          admin.RolUsuario.admin,
          admin.RolUsuario.dueno,
          admin.RolUsuario.cliente,
        ]),
      );
      final usuarioCliente = usuarios.firstWhere((u) => u.email == 'cliente@goaltime.test');
      expect(usuarioCliente.activo, isTrue);
      // Los conteos son la razón de ser de esta pantalla: sin ellos el admin tendría que
      // abrir tres pantallas para decidir.
      for (final usuario in usuarios) {
        expect(usuario.canchas, greaterThanOrEqualTo(0));
        expect(usuario.reservas, greaterThanOrEqualTo(0));
      }
    });

    test('el reporte trae los tres totales y el desglose cuadra', () async {
      if (sinBackend) return _omitir();
      await entrarComoAdmin();

      final reporte = await conRedReal(() => adminRepo.reporte());

      expect(reporte.generadoEn, isNotEmpty);
      expect(reporte.ingresosTotal, greaterThanOrEqualTo(0));
      expect(reporte.reservasTotal, greaterThanOrEqualTo(0));
      expect(reporte.usuariosTotal, greaterThanOrEqualTo(4));
      // El desglose tiene que sumar el total; si no, la gráfica del admin mentiría.
      expect(
        reporte.desgloseCuadra,
        isTrue,
        reason: 'el desglose no suma el total: ${reporte.ingresosPorCancha}',
      );
      // Y los estados llegan por código: la app les pone el nombre del catálogo, y ese
      // nombre tiene que existir o la gráfica mostraría un código suelto.
      for (final estado in reporte.estadosPresentes) {
        expect(estado.etiqueta, isNotEmpty);
      }
    });

    test('el interceptor manda el token y un 401 sin él se explica como sesión', () async {
      if (sinBackend) return _omitir();

      // Sin entrar: la petición va sin Authorization y el backend responde 401.
      final error = await conRedReal(() async {
        try {
          await adminRepo.listarUsuarios();
          return null;
        } on ApiException catch (e) {
          return e;
        }
      });

      expect(error, isNotNull, reason: 'el panel no puede responder sin sesión');
      expect(error!.codigo, 401);
      expect(error.esSesion, isTrue, reason: 'la app cierra sesión sólo con esto');
    });

    test('un 404 del backend llega como ApiException, no como fallo de red', () async {
      if (sinBackend) return _omitir();
      await entrarComoAdmin();

      // Un id que no existe. Importa que sea una llamada de la app y no un `dio.get` a
      // pelo: el mapeo de `DioException` a `ApiException` vive en los repositorios, y es
      // justo lo que este test quiere comprobar. Con un cliente sin convertir, la app
      // distinguiría "no hay esa cancha" de "se cayó la red" y el panel mostraría un error
      // que no sabe explicar.
      final error = await conRedReal(() async {
        try {
          await adminRepo.cambiarRol(999999, rol: admin.RolUsuario.cliente);
          return null;
        } on ApiException catch (e) {
          return e;
        }
      });

      expect(error!.codigo, 404);
      expect(error.mensaje, isNotEmpty);
      expect(
        error.esReintentable,
        isFalse,
        reason: 'un 404 no es un problema de conexión: reintentarlo sería inútil',
      );
    });

    test('el 422 llega con el número de canchas, que es lo que el admin necesita', () async {
      if (sinBackend) return _omitir();
      await entrarComoAdmin();

      // Bajar a cliente a un dueño con canchas activas es el caso que la app muestra tal
      // cual (spec.md 3.5). Si el backend dejara de mandar el número, esta prueba falla.
      final dueno = await conRedReal(() async {
        final usuarios = await adminRepo.listarUsuarios();
        return usuarios.firstWhere(
          (u) => u.rol == admin.RolUsuario.dueno && u.canchas > 0,
        );
      });
      final error = await conRedReal(() async {
        try {
          await adminRepo.cambiarRol(dueno.id, rol: admin.RolUsuario.cliente);
          return null;
        } on ApiException catch (e) {
          return e;
        }
      });

      expect(error!.codigo, 422);
      expect(error.esReglaNegocio, isTrue);
      expect(error.mensaje, contains('${dueno.canchas}'));
    });

    test('el orden de la lista es el de LC_COLLATE=C y no el del locale', () async {
      if (sinBackend) return _omitir();
      await entrarComoAdmin();

      final usuarios = await conRedReal(() => adminRepo.listarUsuarios());
      final nombres = usuarios.map((u) => u.nombre).toList();

      // El backend ordena por byte. Con locale, "Zuleima" saldría después de "ana" y esta
      // lista cambiaría de un servidor a otro (spec.md 7.3).
      final porByte = [...nombres]..sort();
      expect(nombres, porByte);
    });

    test('un texto más largo que su columna es un 400, no un 500', () async {
      if (sinBackend) return _omitir();

      // Lo encontró PostgreSQL: en SQLite el varchar(180) no se aplica y el registro
      // entraba con un 201 (spec.md 7.6).
      final error = await conRedReal(() async {
        try {
          await auth.register(
            nombre: 'Prueba',
            email: '${'a' * 200}@test.co',
            password: 'Goaltime123!',
          );
          return null;
        } on ApiException catch (e) {
          return e;
        }
      });

      expect(error!.codigo, 400);
      expect(error.mensaje, contains('180'));
    });
  });
}

/// Omite el test con un motivo.
///
/// `markTestSkipped` no interrumpe el cuerpo: sólo marca el test para que al terminar lo
/// reporte como salto. Por eso el `return` de quien lo llama es imprescindible — y no
/// puede acompañarse de un `throw`, que convertiría el salto en un fallo.
void _omitir() {
  markTestSkipped(
    'Sin GOALTIME_API_URL: la suite por defecto no habla con la red. '
    'Levantá el backend con tool/verificar_integracion.sh o poné la variable.',
  );
}

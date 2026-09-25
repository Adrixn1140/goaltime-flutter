import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';

/// Proveedor del almacenamiento seguro de sesión.
///
/// Se declara aquí (y no dentro de `token_storage.dart`) para que el backend de
/// almacenamiento sea sustituible en un solo lugar: los tests lo cambian por
/// `MemoriaSegura` y así pueden probar la sesión sin canal de plataforma.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return const TokenStorage();
});

/// Contador de eventos "la sesión ya no vale".
///
/// Es un provider y no un `Stream` porque el interceptor necesita dispararlo desde
/// cualquier request y el `AuthNotifier` necesita escucharlo desde `build`: así los dos
/// quedan conectados sin que la capa de red importe nada de autenticación. El valor es un
/// contador porque a `AuthNotifier` sólo le interesa *que cambió*, no qué pasó.
final sesionExpiradaProvider = NotifierProvider<SesionExpirada, int>(SesionExpirada.new);

class SesionExpirada extends Notifier<int> {
  @override
  int build() => 0;

  void notificar() => state = state + 1;
}

/// Cliente HTTP base (dio) con interceptor de JWT.
final apiClientProvider = Provider<Dio>((ref) {
  return crearApiClient(
    storage: ref.watch(tokenStorageProvider),
    onSesionExpirada: () => ref.read(sesionExpiradaProvider.notifier).notificar(),
  );
});

/// Construye el cliente HTTP con su interceptor.
///
/// Vive fuera del provider para que los tests puedan montar el mismo cliente —con el
/// interceptor de token incluido— y cambiarle sólo el adaptador de red. Si el provider
/// devolviera el `Dio` ya armado, un test que lo sustituye se estaría saltando justo la
/// pieza que hay que probar: qué pasa cuando el token caduca.
Dio crearApiClient({
  required TokenStorage storage,
  required void Function() onSesionExpirada,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      responseType: ResponseType.json,
    ),
  );

  dio.interceptors.add(AuthInterceptor(storage, onSesionExpirada: onSesionExpirada));
  return dio;
}

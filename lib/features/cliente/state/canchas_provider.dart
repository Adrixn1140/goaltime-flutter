import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/canchas_repository.dart';
import '../data/models.dart';
import 'retry.dart';

/// Catálogo de canchas del cliente.
final canchasRepositoryProvider = Provider<CanchasRepository>(
  (ref) => CanchasRepository(ref.watch(apiClientProvider)),
);

/// Canchas activas ordenadas por nombre, como las devuelve la API.
///
/// Un `AsyncNotifier` y no un `FutureProvider` porque la lista se recarga con "deslizar
/// para actualizar" y necesita poder mutar su propio estado sin recrear la pantalla.
///
/// [sinReintento] desactiva el reintento automático de Riverpod: aquí el reintento es una
/// decisión del usuario (botón "Reintentar"), porque lo que se muestra tras un fallo es un
/// mensaje con la siguiente acción, no un spinner que se alarga solo (HEUR-1, HEUR-9).
class CanchasNotifier extends AsyncNotifier<List<Cancha>> {
  @override
  Future<List<Cancha>> build() => ref.watch(canchasRepositoryProvider).listar();

  /// Vuelve a pedir el catálogo (refresh, o reintento tras un error).
  Future<void> recargar() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref.read(canchasRepositoryProvider).listar());
  }
}

final canchasProvider = AsyncNotifierProvider<CanchasNotifier, List<Cancha>>(
  CanchasNotifier.new,
  retry: sinReintento,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/canchas_repository.dart';
import '../data/models.dart';
import '../../../core/state/retry.dart';

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
  Future<void>? _actualizacion;
  int _generacion = 0;

  @override
  Future<List<Cancha>> build() {
    final repo = ref.watch(canchasRepositoryProvider);
    _generacion++;
    _actualizacion = null;
    return repo.listar();
  }

  /// Los refresh simultáneos comparten una petición en lugar de duplicar tráfico.
  Future<void> recargar() {
    final pendiente = _actualizacion;
    if (pendiente != null) return pendiente;

    final generacion = _generacion;
    final repo = ref.read(canchasRepositoryProvider);
    state = const AsyncValue.loading();
    late final Future<void> actualizacion;
    actualizacion = AsyncValue.guard(repo.listar)
        .then((resultado) {
          // Una respuesta antigua no debe actualizar un provider invalidado o cerrado.
          if (ref.mounted && generacion == _generacion) state = resultado;
        })
        .whenComplete(() {
          if (identical(_actualizacion, actualizacion)) _actualizacion = null;
        });
    _actualizacion = actualizacion;
    return actualizacion;
  }
}

final canchasProvider = AsyncNotifierProvider<CanchasNotifier, List<Cancha>>(
  CanchasNotifier.new,
  retry: sinReintento,
);

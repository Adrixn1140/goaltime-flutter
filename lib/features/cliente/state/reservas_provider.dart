import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../data/models.dart';
import '../data/reservas_repository.dart';
import 'retry.dart';

final reservasRepositoryProvider = Provider<ReservasRepository>(
  (ref) => ReservasRepository(ref.watch(apiClientProvider)),
);

/// Reservas del cliente, de la más reciente a la más antigua.
///
/// Se refresca desde fuera cuando una reserva nueva o un pago cambian el estado, para
/// que "Mis reservas" y la reserva recién creada nunca se contradigan.
class MisReservasNotifier extends AsyncNotifier<List<Reserva>> {
  @override
  Future<List<Reserva>> build() => ref.watch(reservasRepositoryProvider).misReservas();

  /// Vuelve a pedir la lista y espera a que termine, para que "deslizar para actualizar"
  /// no quite el indicador antes de tener los datos nuevos.
  Future<void> recargar() async {
    ref.invalidateSelf();
    await future;
  }

  /// Reserva el slot elegido. Lanza [ApiException] para que la pantalla muestre el
  /// mensaje del backend (`409` slot ocupado, `422` fecha o día no válido).
  Future<ReservaCreada> reservar({
    required int canchaId,
    required int horarioId,
    required String fecha,
  }) async {
    final creada = await ref
        .read(reservasRepositoryProvider)
        .reservar(canchaId: canchaId, horarioId: horarioId, fecha: fecha);

    // El refresco va en segundo plano: la reserva ya existe aunque la relectura falle,
    // y un error de red al releer no debe hacer creer al usuario que se perdió.
    unawaited(_recargarEnSegundoPlano());
    return creada;
  }

  /// Recarga sin propagar el fallo: el error ya se mostró en la pantalla que pidió la
  /// reserva, y aquí sólo importa que la lista vuelva a estar al día cuando se pueda.
  Future<void> _recargarEnSegundoPlano() async {
    try {
      await recargar();
    } on Object catch (error) {
      debugPrint('No se pudo refrescar la lista de reservas: $error');
    }
  }
}

final misReservasProvider = AsyncNotifierProvider<MisReservasNotifier, List<Reserva>>(
  MisReservasNotifier.new,
  retry: sinReintento,
);

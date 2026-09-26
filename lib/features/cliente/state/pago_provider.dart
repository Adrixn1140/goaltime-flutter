import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import 'reservas_provider.dart' show reservasRepositoryProvider;
import '../../../core/state/retry.dart';

/// Pago de una reserva mientras se resuelve.
///
/// La confirmación llega por webhook, no por la respuesta del checkout: al volver de la
/// pasarela la app consulta el estado algunas veces. Se encapsula en un `AsyncNotifier`
/// para que la pantalla muestre siempre las tres cosas que importan —el spinner, el error
/// y el estado del pago— sin reinventar la máquina de estados en cada widget.
///
/// El id del pago entra por el constructor porque en Riverpod 3 el `family` se declara
/// como `PagoNotifier.new`: la factoría recibe el argumento y se lo pasa al notifier.
class PagoNotifier extends AsyncNotifier<Pago> {
  PagoNotifier(this.pagoId);

  final int pagoId;

  @override
  Future<Pago> build() => ref.watch(reservasRepositoryProvider).consultarPago(pagoId);

  /// Abre el checkout en la pasarela. El monto no viaja: lo tiene el backend.
  Future<Checkout> abrirCheckout({required int reservaId}) {
    return ref.read(reservasRepositoryProvider).abrirCheckout(reservaId: reservaId);
  }

  /// Cierra el pago con la pasarela simulada (sólo `PAGADORA=mock`).
  Future<ResultadoPago> simular({required bool aprobado}) async {
    final resultado = await ref.read(reservasRepositoryProvider).simularPago(
      pagoId: pagoId,
      aprobado: aprobado,
    );
    state = AsyncValue.data(resultado.pago);
    return resultado;
  }

  /// Consulta el estado del pago hasta que deje de estar `pendiente`.
  ///
  /// El webhook puede tardar, así que se reintenta unas veces con una pausa fija. Se corta
  /// en cuanto el pago ya no está pendiente: seguir preguntando a un pago confirmado sólo
  /// gasta batería y hace parpadear la pantalla (HEUR-1).
  ///
  /// Devuelve el último estado leído, para que la pantalla pueda mostrar el resultado
  /// aunque la espera se agote.
  Future<Pago> esperarConfirmacion({
    int intentos = 5,
    Duration pausa = const Duration(seconds: 2),
  }) async {
    var pago = await _consultar();
    for (var i = 0; i < intentos && pago.estado == EstadoPago.pendiente; i++) {
      await Future<void>.delayed(pausa);
      pago = await _consultar();
    }
    return pago;
  }

  Future<Pago> _consultar() async {
    final pago = await ref.read(reservasRepositoryProvider).consultarPago(pagoId);
    state = AsyncValue.data(pago);
    return pago;
  }
}

final pagoProvider = AsyncNotifierProvider.family<PagoNotifier, Pago, int>(
  PagoNotifier.new,
  retry: sinReintento,
);

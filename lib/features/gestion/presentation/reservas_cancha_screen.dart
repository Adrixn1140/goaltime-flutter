import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/format.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
// El chip de estado y los enums de reserva son el mismo vocabulario que ve el cliente. Se
// reusan en vez de duplicarlos: dos juegos de colores para el mismo estado harían que
// "Confirmada" se viera distinto según la pantalla desde la que se mire (HEUR-4).
import '../../cliente/data/models.dart' show EstadoReserva;
import '../../cliente/presentation/widgets/estado_chip.dart';
import '../data/models.dart';
import '../state/gestion_provider.dart';
import 'horarios_screen.dart' show nombreCancha;
import 'widgets/aviso_gestion.dart';

/// Reservas de una cancha (`GET /api/gestion/canchas/{id}/reservas`).
///
/// Sólo aparece "Confirmar" cuando el pago está aprobado. El backend lo exige, y un botón
/// que el servidor va a rechazar es una forma de gastar el gesto del dueño y su paciencia
/// para aprender la regla (HEUR-5, HEUR-9).
class ReservasCanchaScreen extends ConsumerWidget {
  const ReservasCanchaScreen({super.key, required this.canchaId});

  final int canchaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservas = ref.watch(reservasCanchaProvider(canchaId));

    return Scaffold(
      appBar: AppBar(title: Text('Reservas · ${nombreCancha(ref, canchaId)}')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(reservasCanchaProvider(canchaId).notifier).recargar(),
        child: reservas.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AvisoGestion(
            icono: Icons.cloud_off,
            mensaje: mensajeDeError(error),
            accion: FilledButton.tonal(
              onPressed: () => ref.read(reservasCanchaProvider(canchaId).notifier).recargar(),
              child: const Text('Reintentar'),
            ),
          ),
          data: (lista) => lista.isEmpty
              ? const AvisoGestion(
                  icono: Icons.event_available_outlined,
                  mensaje: 'Todavía nadie ha reservado esta cancha.',
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: lista.length,
                  itemBuilder: (context, index) => _TarjetaReserva(
                    reserva: lista[index],
                    alConfirmar: () => _cambiarEstado(context, ref, lista[index].id, 'confirmar'),
                    alCancelar: () => _cancelar(context, ref, lista[index]),
                  ),
                ),
        ),
      ),
    );
  }

  /// Cancelar sí pide confirmación: la reserva queda anulada y el slot se libera para otro
  /// cliente. Es la única acción de la app que no tiene vuelta atrás, así que se pregunta.
  Future<void> _cancelar(BuildContext context, WidgetRef ref, ReservaGestion reserva) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogoContext) => AlertDialog(
        title: const Text('¿Cancelar la reserva?'),
        content: Text(
          'Se anula la reserva de ${reserva.nombreCliente} y el horario vuelve a quedar libre.\n'
          'El pago no se devuelve: eso se resuelve aparte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogoContext).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogoContext).pop(true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    if (!context.mounted) return;
    await _cambiarEstado(context, ref, reserva.id, 'cancelar');
  }

  Future<void> _cambiarEstado(
    BuildContext context,
    WidgetRef ref,
    int reservaId,
    String accion,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(reservasCanchaProvider(canchaId).notifier).cambiarEstado(reservaId, accion);
      messenger.showSnackBar(
        SnackBar(
          content: Text(accion == 'confirmar' ? 'Reserva confirmada' : 'Reserva cancelada'),
        ),
      );
    } on Object catch (error) {
      // Un `422` significa que la reserva ya no está en el estado que permite la acción.
      // Se muestra la frase del backend y la lista se refresca para que el dueño vea el
      // estado real en vez de una tarjeta que ya miente.
      messenger.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
      await ref.read(reservasCanchaProvider(canchaId).notifier).recargar();
    }
  }
}

class _TarjetaReserva extends StatelessWidget {
  const _TarjetaReserva({
    required this.reserva,
    required this.alConfirmar,
    required this.alCancelar,
  });

  final ReservaGestion reserva;
  final VoidCallback alConfirmar;
  final VoidCallback alCancelar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(reserva.nombreCliente, style: theme.textTheme.titleMedium),
                ),
                switch (reserva.estado) {
                  EstadoReserva.confirmada => const EstadoChip.confirmada(),
                  EstadoReserva.cancelada => const EstadoChip.cancelada(),
                  EstadoReserva.pendientePago => const EstadoChip.pendientePago(),
                },
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${etiquetaFecha(reserva.fecha)} · ${reserva.rango}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Total', style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text(
                  formatoMonto(reserva.tarifa),
                  style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary),
                ),
              ],
            ),
            if (reserva.motivoSinConfirmar != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.tertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      reserva.motivoSinConfirmar!,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary),
                    ),
                  ),
                ],
              ),
            ],
            if (reserva.puedeConfirmar || reserva.puedeCancelar) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (reserva.puedeConfirmar)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: alConfirmar,
                        icon: const Icon(Icons.check),
                        label: const Text('Confirmar'),
                      ),
                    ),
                  if (reserva.puedeConfirmar && reserva.puedeCancelar) const SizedBox(width: 12),
                  if (reserva.puedeCancelar)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: alCancelar,
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/format.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/models.dart';
import '../state/reservas_provider.dart';
import 'pago_sheet.dart';
import 'widgets/estado_chip.dart';

/// Historial de reservas del cliente (`GET /api/mis-reservas`).
///
/// HEUR-9: una reserva `pendiente_pago` ofrece el pago aquí mismo, sin obligar a entrar
/// de nuevo al flujo de reserva. Un pago rechazado muestra el reintento en la tarjeta.
class MisReservasScreen extends ConsumerWidget {
  const MisReservasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservas = ref.watch(misReservasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis reservas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(misReservasProvider.notifier).recargar(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(misReservasProvider.notifier).recargar(),
        child: reservas.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Aviso(
            icono: Icons.cloud_off,
            mensaje: mensajeDeError(error),
            accion: FilledButton.tonal(
              onPressed: () => ref.read(misReservasProvider.notifier).recargar(),
              child: const Text('Reintentar'),
            ),
          ),
          data: (lista) => lista.isEmpty
              ? const _Aviso(
                  icono: Icons.event_available_outlined,
                  mensaje: 'Todavía no tienes reservas.\nElige una cancha y reserva tu horario.',
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: lista.length,
                  itemBuilder: (context, index) => _ReservaCard(
                    reserva: lista[index],
                    alPagar: () => _pagar(context, ref, lista[index]),
                  ),
                ),
        ),
      ),
    );
  }

  /// Abre la hoja de pago y, si el pago queda aprobado, recarga la lista para que el
  /// estado de la tarjeta y el del pago no discrepen.
  Future<void> _pagar(BuildContext context, WidgetRef ref, Reserva reserva) async {
    final pago = reserva.pago;
    if (pago == null) return;
    final pagado = await PagoSheet.abrir(
      context,
      pagoId: pago.id,
      reservaId: reserva.id,
      resumen: '${etiquetaFecha(reserva.fecha)} · ${reserva.rango}',
    );
    if (pagado == true) {
      await ref.read(misReservasProvider.notifier).recargar();
    }
  }
}

class _ReservaCard extends StatelessWidget {
  const _ReservaCard({required this.reserva, required this.alPagar});

  final Reserva reserva;
  final VoidCallback alPagar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pendiente = reserva.estado == EstadoReserva.pendientePago;

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
                  child: Text(reserva.cancha.nombre, style: theme.textTheme.titleMedium),
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
            Text(
              reserva.cancha.ubicacion,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
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
            if (reserva.pagoFallido) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'El pago fue rechazado. La reserva sigue apartada.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
            if (pendiente && reserva.pago != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: alPagar,
                icon: const Icon(Icons.credit_card),
                label: Text(reserva.pagoFallido ? 'Reintentar el pago' : 'Pagar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.mensaje, this.accion});

  final IconData icono;
  final String mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(icono, size: 56, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(mensaje, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        if (accion != null) ...[const SizedBox(height: 24), Center(child: accion)],
      ],
    );
  }
}

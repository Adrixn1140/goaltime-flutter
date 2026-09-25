import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/format.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/models.dart';
import '../state/pago_provider.dart';
import 'widgets/estado_chip.dart';

/// Hoja de pago de una reserva.
///
/// Un mismo flujo para los tres caminos de entrada (reserva recién creada, "Mis
/// reservas" y reintento), porque el pago se ve igual en todos: un resumen, el estado
/// actual y una sola acción primaria según dónde esté.
///
/// HEUR-1: el estado del pago siempre está visible; se muestra spinner mientras se
/// consulta y nunca un botón que "no hace nada".
/// HEUR-9: si el pago se rechaza, la misma hoja ofrece reintentar en vez de dejar al
/// usuario buscando qué hacer.
class PagoSheet extends ConsumerStatefulWidget {
  const PagoSheet({
    super.key,
    required this.pagoId,
    required this.reservaId,
    required this.resumen,
  });

  final int pagoId;
  final int reservaId;

  /// Texto ya formateado de la reserva: "Vie 25 sep · 08:00 – 10:00".
  final String resumen;

  /// Abre la hoja de pago. Devuelve `true` si el pago quedó aprobado.
  static Future<bool?> abrir(
    BuildContext context, {
    required int pagoId,
    required int reservaId,
    required String resumen,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PagoSheet(pagoId: pagoId, reservaId: reservaId, resumen: resumen),
    );
  }

  @override
  ConsumerState<PagoSheet> createState() => _PagoSheetState();
}

class _PagoSheetState extends ConsumerState<PagoSheet> {
  bool _ocupado = false;
  String? _error;
  Checkout? _checkout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pagoAsync = ref.watch(pagoProvider(widget.pagoId));
    final pago = pagoAsync.value;
    final estado = pago?.estado ?? EstadoPago.pendiente;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pago de la reserva', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.resumen, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Total', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  formatoMonto(pago?.monto),
                  style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: EstadoChip.pago(estado)),
            if (pagoAsync.hasError) ...[
              const SizedBox(height: 12),
              _MensajeError(texto: mensajeDeError(pagoAsync.error!), alReintentar: _consultar),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _MensajeError(texto: _error!, alReintentar: () => setState(() => _error = null)),
            ],
            const SizedBox(height: 20),
            ..._acciones(estado, pago),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _ocupado ? null : () => Navigator.of(context).pop(false),
              child: const Text('Ahora no'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _acciones(EstadoPago estado, Pago? pago) {
    if (_ocupado) {
      return const [LinearProgressIndicator()];
    }

    if (estado == EstadoPago.aprobado) {
      return [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.check),
          label: const Text('Reserva confirmada'),
        ),
      ];
    }

    if (estado == EstadoPago.rechazado) {
      return [
        FilledButton.icon(
          onPressed: _abrirPago,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar el pago'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tu pago no se pudo aprobar. La reserva sigue reservada para ti mientras vuelves a intentar.',
          textAlign: TextAlign.center,
        ),
      ];
    }

    // Pendiente: la acción depende de cómo se vaya a cobrar.
    if (pago != null && pago.esSimulado) {
      return [
        FilledButton.icon(
          onPressed: () => _simular(aprobado: true),
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('Simular pago aprobado'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _simular(aprobado: false),
          child: const Text('Simular pago rechazado'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Pasarela de prueba: estos botones sustituyen a Stripe para poder probar el flujo completo.',
          textAlign: TextAlign.center,
        ),
      ];
    }

    return [
      FilledButton.icon(
        onPressed: _abrirPago,
        icon: const Icon(Icons.credit_card),
        label: const Text('Pagar con tarjeta'),
      ),
      if (_checkout != null) ...[
        const SizedBox(height: 8),
        Text(
          'No se abrió el navegador. Copia el enlace de pago:',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton.icon(
          onPressed: _copiarEnlace,
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copiar enlace'),
        ),
      ],
    ];
  }

  /// Abre la sesión de pago en la pasarela y, si es una URL real, la abre en el
  /// navegador. En modo `mock` la URL es ilustrativa: se cambia el botón en vez de
  /// mandar al usuario a una página que no existe.
  Future<void> _abrirPago() async {
    await _conOcupacion(() async {
      final checkout = await ref.read(pagoProvider(widget.pagoId).notifier).abrirCheckout(
        reservaId: widget.reservaId,
      );
      if (!mounted) return;
      setState(() => _checkout = checkout);

      if (checkout.esIlustrativa) {
        ref.invalidate(pagoProvider(widget.pagoId));
        return;
      }

      final abierta = await _abrirExterno(checkout.checkoutUrl);
      if (!abierta) return;
      // El webhook puede tardar: se consulta unas veces hasta que el pago se resuelva.
      await ref.read(pagoProvider(widget.pagoId).notifier).esperarConfirmacion();
    });
  }

  Future<void> _simular({required bool aprobado}) async {
    await _conOcupacion(() async {
      final resultado = await ref
          .read(pagoProvider(widget.pagoId).notifier)
          .simular(aprobado: aprobado);
      if (!mounted) return;
      final texto = switch (resultado.pago.estado) {
        EstadoPago.aprobado => '¡Pago aprobado! Tu reserva quedó confirmada.',
        EstadoPago.rechazado => 'El pago fue rechazado. Puedes reintentar.',
        EstadoPago.pendiente => 'El pago sigue pendiente.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
    });
  }

  Future<void> _consultar() async {
    ref.invalidate(pagoProvider(widget.pagoId));
  }

  Future<void> _copiarEnlace() async {
    final url = _checkout?.checkoutUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace copiado')));
  }

  /// `true` si el navegador aceptó la URL. Si falla, la hoja muestra el enlace para
  /// copiarlo a mano en vez de dejar al usuario sin salida (HEUR-9).
  Future<bool> _abrirExterno(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } on Object catch (error) {
      debugPrint('No se pudo abrir el checkout: $error');
    }
    if (mounted) setState(() {});
    return false;
  }

  /// Ejecuta una acción de pago manteniendo el botón ocupado y mostrando el error del
  /// backend si algo falla.
  Future<void> _conOcupacion(Future<void> Function() accion) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await accion();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = mensajeDeError(error));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }
}

class _MensajeError extends StatelessWidget {
  const _MensajeError({required this.texto, required this.alReintentar});

  final String texto;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: alReintentar, child: const Text('Actualizar estado')),
          ),
        ],
      ),
    );
  }
}

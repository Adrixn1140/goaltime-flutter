import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Etiqueta de color para el estado de una reserva o de un pago.
///
/// El color va acompañado **siempre** de texto: el color solo no es accesible para quien
/// no distingue rojo y verde (HEUR-4, HEUR-2). El mismo vocabulario se usa en "Mis
/// reservas" y en el resumen de pago para que el usuario no tenga que aprender dos.
class EstadoChip extends StatelessWidget {
  const EstadoChip.pendientePago({super.key})
    : _estilo = _Estilo.pendiente,
      etiqueta = 'Pendiente de pago',
      icono = Icons.schedule;

  const EstadoChip.confirmada({super.key})
    : _estilo = _Estilo.exito,
      etiqueta = 'Confirmada',
      icono = Icons.check_circle_outline;

  const EstadoChip.cancelada({super.key})
    : _estilo = _Estilo.neutro,
      etiqueta = 'Cancelada',
      icono = Icons.cancel_outlined;

  const EstadoChip._(this._estilo, this.etiqueta, this.icono);

  /// Los tres estados de pago. Es una fábrica y no un constructor `const` con argumento
  /// porque el color depende del valor recibido: decide el código que llama, no la
  /// declaración de la clase.
  factory EstadoChip.pago(EstadoPago estado) => switch (estado) {
    EstadoPago.aprobado => const EstadoChip.confirmada(),
    EstadoPago.rechazado =>
      const EstadoChip._(_Estilo.error, 'Rechazado', Icons.error_outline),
    EstadoPago.pendiente =>
      const EstadoChip._(_Estilo.pendiente, 'Pendiente', Icons.schedule),
  };

  final _Estilo _estilo;
  final String etiqueta;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (fondo, foreground) = switch (_estilo) {
      _Estilo.exito => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _Estilo.error => (scheme.errorContainer, scheme.onErrorContainer),
      _Estilo.pendiente => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _Estilo.neutro => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            etiqueta,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Estilo { exito, error, pendiente, neutro }

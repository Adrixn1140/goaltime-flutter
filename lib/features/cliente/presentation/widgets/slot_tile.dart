import 'package:flutter/material.dart';

import '../../../../shared/format.dart';
import '../../data/models.dart';

/// Un slot de la disponibilidad.
///
/// Un slot no disponible se muestra **deshabilitado pero visible**, con su motivo escrito
/// ("Ocupado", "Ya pasó") en lugar de desaparecer de la lista: el usuario ve que existe,
/// que hay alternatives y por qué no puede elegirlo (HEUR-5, HEUR-8).
class SlotTile extends StatelessWidget {
  const SlotTile({
    super.key,
    required this.slot,
    required this.onSelected,
    this.seleccionado = false,
  });

  final Slot slot;
  final ValueChanged<Slot> onSelected;

  /// Marca el slot elegido. El usuario tiene que ver qué seleccionó sin releer la lista
  /// entera (HEUR-1).
  final bool seleccionado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final deshabilitado = !slot.disponible;

    return Semantics(
      button: !deshabilitado,
      enabled: !deshabilitado,
      selected: seleccionado,
      label: deshabilitado
          ? '${slot.rango}, ${slot.motivo?.etiqueta ?? 'no disponible'}'
          : '${slot.rango}, ${formatoMonto(slot.tarifa)}',
      child: InkWell(
        onTap: deshabilitado ? null : () => onSelected(slot),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: deshabilitado
                ? scheme.surfaceContainerHighest
                : (seleccionado ? scheme.primaryContainer : scheme.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: seleccionado ? scheme.primary : scheme.outlineVariant,
              width: seleccionado ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.rango,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: deshabilitado ? scheme.onSurfaceVariant : scheme.onSurface,
                        decoration: deshabilitado ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      deshabilitado
                          ? slot.motivo?.etiqueta ?? 'No disponible'
                          : formatoMonto(slot.tarifa),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: deshabilitado ? scheme.onSurfaceVariant : scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (deshabilitado)
                Icon(Icons.block, size: 18, color: scheme.outline)
              else if (seleccionado)
                Icon(Icons.check_circle, size: 18, color: scheme.primary)
              else
                Icon(Icons.chevron_right, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

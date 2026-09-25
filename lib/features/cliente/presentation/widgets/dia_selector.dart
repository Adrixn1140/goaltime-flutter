import 'package:flutter/material.dart';

import '../../../../shared/format.dart';

/// Selector de día de la disponibilidad.
///
/// Muestra los 6 días que devuelve la API en una tira horizontal: cabe de un vistazo y no
/// obliga a abrir un calendario (HEUR-7, HEUR-8). Cada botón lleva el día escrito, no
/// sólo el número, para que el usuario no tenga que recordar a qué fecha corresponde el
/// "24" (HEUR-6).
class DiaSelector extends StatelessWidget {
  const DiaSelector({
    super.key,
    required this.fechas,
    required this.seleccionada,
    required this.onChanged,
  });

  final List<String> fechas;
  final String? seleccionada;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (fechas.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: fechas.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final fecha = fechas[index];
          final dia = parseFechaIso(fecha);
          final activa = fecha == seleccionada;
          return _DiaButton(
            etiquetaDia: dia == null ? '—' : etiquetaDiaCorto(dia),
            sub: etiquetaFecha(fecha),
            activa: activa,
            onTap: () => onChanged(fecha),
          );
        },
      ),
    );
  }
}

class _DiaButton extends StatelessWidget {
  const _DiaButton({
    required this.etiquetaDia,
    required this.sub,
    required this.activa,
    required this.onTap,
  });

  final String etiquetaDia;
  final String sub;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fondo = activa ? scheme.primary : scheme.surface;
    final texto = activa ? scheme.onPrimary : scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: activa ? scheme.primary : scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              etiquetaDia,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: texto, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: theme.textTheme.labelSmall?.copyWith(color: texto.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

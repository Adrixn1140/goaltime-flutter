import 'package:flutter/material.dart';

/// Aviso a pantalla completa con la siguiente acción.
///
/// El mismo widget para error de carga, lista vacía y "todavía no hay nada": el dueño no
/// debería tener que aprender una pantalla distinta para cada estado, y el patrón
/// "icono grande + texto + botón" se lee igual en los tres (HEUR-4).
class AvisoGestion extends StatelessWidget {
  const AvisoGestion({super.key, required this.icono, required this.mensaje, this.accion});

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

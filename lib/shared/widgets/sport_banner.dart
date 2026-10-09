import 'package:flutter/material.dart';

/// Cabecera deportiva sin assets externos, adaptable al tamaño de texto.
class SportBanner extends StatelessWidget {
  const SportBanner({
    super.key,
    required this.etiqueta,
    required this.titulo,
    required this.descripcion,
    this.icono = Icons.sports_soccer,
    this.accion,
  });

  final String etiqueta, titulo, descripcion;
  final IconData icono;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF102D2A), Color(0xFF176B50)],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, color: const Color(0xFFB9F36B), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                etiqueta.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFB9F36B),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          titulo,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          descripcion,
          style: const TextStyle(color: Color(0xFFD7E7DE), height: 1.5),
        ),
        if (accion != null) ...[const SizedBox(height: 20), accion!],
      ],
    ),
  );
}

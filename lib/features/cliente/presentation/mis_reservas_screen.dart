import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// Historial de reservas del cliente (Fase 4).
class MisReservasScreen extends StatelessWidget {
  const MisReservasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      title: 'Mis reservas',
      message: 'Historial de reservas (Fase 4):\n'
          'GET /api/mis-reservas',
    );
  }
}
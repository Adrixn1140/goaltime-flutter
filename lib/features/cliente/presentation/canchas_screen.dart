import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// Catálogo de canchas (Fase 4).
class CanchasScreen extends StatelessWidget {
  const CanchasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      title: 'Canchas',
      message: 'Catálogo de canchas disponibles (Fase 4):\n'
          'GET /api/canchas',
    );
  }
}
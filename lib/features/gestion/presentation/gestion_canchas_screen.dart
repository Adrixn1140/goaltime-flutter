import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// CRUD de canchas y horarios del dueño (Fase 6).
class GestionCanchasScreen extends StatelessWidget {
  const GestionCanchasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      title: 'Mis canchas',
      message: 'CRUD de canchas y horarios (Fase 6):\n'
          'GET/POST /api/canchas (solo propias, por dueno_id)',
    );
  }
}
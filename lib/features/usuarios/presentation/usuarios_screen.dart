import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// Gestión de usuarios y reportes (Fase 7).
class UsuariosScreen extends StatelessWidget {
  const UsuariosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(
      title: 'Usuarios',
      message: 'Gestión de usuarios y reportes (Fase 7):\n'
          'GET /api/usuarios · GET /api/reporte',
    );
  }
}
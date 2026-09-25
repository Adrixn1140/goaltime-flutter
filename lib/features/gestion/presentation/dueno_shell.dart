import 'package:flutter/material.dart';

/// Shell del rol Dueño: gestiona sus canchas.
class DuenoShell extends StatelessWidget {
  const DuenoShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión')),
      body: child,
    );
  }
}
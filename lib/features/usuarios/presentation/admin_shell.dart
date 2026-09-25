import 'package:flutter/material.dart';

/// Shell del rol Admin: gestión global.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: child,
    );
  }
}
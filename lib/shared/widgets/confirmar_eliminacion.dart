import 'package:flutter/material.dart';

import '../../features/auth/auth_state.dart' show mensajeDeError;

/// Mantiene la confirmación abierta si falla y bloquea envíos repetidos.
Future<bool> confirmarEliminacion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required Future<void> Function() eliminar,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _Confirmacion(titulo: titulo, mensaje: mensaje, eliminar: eliminar),
    ) ??
    false;

class _Confirmacion extends StatefulWidget {
  const _Confirmacion({
    required this.titulo,
    required this.mensaje,
    required this.eliminar,
  });
  final String titulo, mensaje;
  final Future<void> Function() eliminar;
  @override
  State<_Confirmacion> createState() => _ConfirmacionState();
}

class _ConfirmacionState extends State<_Confirmacion> {
  bool _ocupado = false;
  String? _error;
  Future<void> _eliminar() async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await widget.eliminar();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _error = mensajeDeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_ocupado,
    child: AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.mensaje),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _ocupado ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _ocupado ? null : _eliminar,
          child: Text(_ocupado ? 'Eliminando…' : 'Eliminar'),
        ),
      ],
    ),
  );
}

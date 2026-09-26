import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/models.dart';
import '../state/gestion_provider.dart';

/// Alta y edición de una cancha. Un solo formulario para las dos cosas: los campos son los
/// mismos y lo único que cambia es el título y el verbo del botón.
class FormCanchaSheet extends ConsumerStatefulWidget {
  const FormCanchaSheet({super.key, this.cancha});

  final CanchaGestion? cancha;

  /// Abre la hoja y espera a que se cierre. Devuelve `true` si hubo un cambio guardado.
  static Future<bool?> abrir(BuildContext context, {CanchaGestion? cancha}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FormCanchaSheet(cancha: cancha),
    );
  }

  @override
  ConsumerState<FormCanchaSheet> createState() => _FormCanchaSheetState();
}

class _FormCanchaSheetState extends ConsumerState<FormCanchaSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.cancha?.nombre ?? '');
  late final _ubicacion = TextEditingController(text: widget.cancha?.ubicacion ?? '');
  bool _enviando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _ubicacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.cancha != null;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editando ? 'Editar cancha' : 'Nueva cancha',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombre,
              textInputAction: TextInputAction.next,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Cancha El Retiro',
              ),
              validator: _obligatorio('El nombre'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ubicacion,
              textInputAction: TextInputAction.done,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Dirección', hintText: 'Cra 45 # 12-30'),
              validator: _obligatorio('La dirección'),
              onFieldSubmitted: (_) => _enviar(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _enviando ? null : _enviar,
                child: _enviando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(editando ? 'Guardar cambios' : 'Crear cancha'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static FormFieldValidator<String> _obligatorio(String etiqueta) => (valor) {
    if (valor == null || valor.trim().isEmpty) return '$etiqueta es obligatoria';
    return null;
  };

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enviando = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(canchasGestionProvider.notifier);
    final nombre = _nombre.text.trim();
    final ubicacion = _ubicacion.text.trim();
    final editando = widget.cancha != null;

    try {
      if (editando) {
        await notifier.editar(widget.cancha!.id, nombre: nombre, ubicacion: ubicacion);
      } else {
        await notifier.crear(nombre: nombre, ubicacion: ubicacion);
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(editando ? 'Cambios guardados' : 'Cancha creada')),
      );
    } on Object catch (error) {
      // El mensaje del backend vale más que uno genérico: si el nombre es demasiado largo
      // o la dirección quedó vacía, él sabe por qué (HEUR-9).
      messenger.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
      if (mounted) setState(() => _enviando = false);
    }
  }
}

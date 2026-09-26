import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/format.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/models.dart';
import '../state/gestion_provider.dart';

/// Hoja de alta y edición de un horario.
///
/// La tarifa se pide con teclado numérico y punto, porque escribirlos a mano es la forma
/// más rápida de equivocar un precio — y el backend responde `422` a una tarifa en cero
/// después de todo el viaje. El día va en un desplegable con el nombre completo: `0` a `6`
/// no le dice nada a nadie (HEUR-2, HEUR-5).
class FormHorarioSheet extends ConsumerStatefulWidget {
  const FormHorarioSheet({super.key, required this.canchaId, this.horario});

  final int canchaId;
  final HorarioCancha? horario;

  static Future<bool?> abrir(BuildContext context, {required int canchaId, HorarioCancha? horario}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FormHorarioSheet(canchaId: canchaId, horario: horario),
    );
  }

  @override
  ConsumerState<FormHorarioSheet> createState() => _FormHorarioSheetState();
}

class _FormHorarioSheetState extends ConsumerState<FormHorarioSheet> {
  final _formKey = GlobalKey<FormState>();
  late int _dia = widget.horario?.dia ?? _diaDeHoy();
  late TimeOfDay _inicio = _hora(widget.horario?.horaInicio) ?? const TimeOfDay(hour: 8, minute: 0);
  late TimeOfDay _fin = _hora(widget.horario?.horaFin) ?? const TimeOfDay(hour: 10, minute: 0);
  late final _tarifa = TextEditingController(
    text: widget.horario == null ? '' : _sinDecimales(widget.horario!.tarifa),
  );
  bool _enviando = false;

  @override
  void dispose() {
    _tarifa.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.horario != null;
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
              editando ? 'Editar horario' : 'Nuevo horario',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _dia,
              decoration: const InputDecoration(labelText: 'Día'),
              items: [
                for (var dia = 0; dia < 7; dia++)
                  DropdownMenuItem(value: dia, child: Text(etiquetaDiaSemana(dia))),
              ],
              onChanged: (valor) => setState(() => _dia = valor ?? _dia),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CampoHora(
                    etiqueta: 'Empieza',
                    valor: _inicio,
                    alElegir: (hora) => setState(() => _inicio = hora),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CampoHora(
                    etiqueta: 'Termina',
                    valor: _fin,
                    alElegir: (hora) => setState(() => _fin = hora),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tarifa,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(
                labelText: 'Tarifa',
                prefixText: r'$ ',
                hintText: '60000',
              ),
              validator: (valor) {
                final tarifa = double.tryParse((valor ?? '').trim());
                if (tarifa == null) return 'Escribe la tarifa, sólo números';
                if (tarifa <= 0) return 'La tarifa debe ser mayor que cero';
                return null;
              },
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
                    : Text(editando ? 'Guardar cambios' : 'Crear horario'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enviando = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(horariosProvider(widget.canchaId).notifier);
    final horario = widget.horario;
    final horaInicio = _formato(_inicio);
    final horaFin = _formato(_fin);
    final tarifa = double.parse(_tarifa.text.trim());

    try {
      if (horario == null) {
        await notifier.crear(
          dia: _dia,
          horaInicio: horaInicio,
          horaFin: horaFin,
          tarifa: tarifa,
        );
      } else {
        await notifier.editar(
          horario.id,
          dia: _dia,
          horaInicio: horaInicio,
          horaFin: horaFin,
          tarifa: tarifa,
        );
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(horario == null ? 'Horario creado' : 'Horario actualizado')),
      );
    } on Object catch (error) {
      // Un `422` aquí casi siempre es un solape o un `hora_fin` que no es posterior al
      // inicio. El backend lo dice con precisión y esa frase es la que se muestra.
      messenger.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// El día de hoy, porque es el primero que un dueño quiere abrir.
  static int _diaDeHoy() => DateTime.now().weekday - 1;

  static String _formato(TimeOfDay hora) =>
      '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? _hora(String? texto) {
    if (texto == null) return null;
    final partes = texto.split(':');
    if (partes.length != 2) return null;
    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);
    if (hora == null || minuto == null) return null;
    return TimeOfDay(hour: hora, minute: minuto);
  }

  /// `60000.5` → `60000.5`; `60000.0` → `60000`. Sin decimales de más, que en una tarifa
  /// no significan nada.
  static String _sinDecimales(double tarifa) =>
      tarifa == tarifa.roundToDouble() ? tarifa.toStringAsFixed(0) : tarifa.toString();
}

class _CampoHora extends StatelessWidget {
  const _CampoHora({required this.etiqueta, required this.valor, required this.alElegir});

  final String etiqueta;
  final TimeOfDay valor;
  final ValueChanged<TimeOfDay> alElegir;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final elegida = await showTimePicker(context: context, initialTime: valor);
        if (elegida != null) alElegir(elegida);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: etiqueta),
        child: Text(
          '${valor.hour.toString().padLeft(2, '0')}:${valor.minute.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}

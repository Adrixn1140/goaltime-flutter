import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/format.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/models.dart';
import '../state/gestion_provider.dart';
import 'form_horario_sheet.dart';
import 'widgets/aviso_gestion.dart';

/// Horarios de una cancha (`GET /api/gestion/canchas/{id}/horarios`).
///
/// Los horarios se muestran agrupados por día y en orden de hora, que es como el dueño
/// piensa su agenda semanal; el backend ya los entrega así y la app no los reordena.
class HorariosScreen extends ConsumerWidget {
  const HorariosScreen({super.key, required this.canchaId});

  final int canchaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horarios = ref.watch(horariosProvider(canchaId));

    return Scaffold(
      appBar: AppBar(title: Text('Horarios · ${nombreCancha(ref, canchaId)}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => FormHorarioSheet.abrir(context, canchaId: canchaId),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo horario'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(horariosProvider(canchaId).notifier).recargar(),
        child: horarios.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AvisoGestion(
            icono: Icons.cloud_off,
            mensaje: mensajeDeError(error),
            accion: FilledButton.tonal(
              onPressed: () => ref.read(horariosProvider(canchaId).notifier).recargar(),
              child: const Text('Reintentar'),
            ),
          ),
          data: (lista) => lista.isEmpty
              ? AvisoGestion(
                  icono: Icons.schedule,
                  mensaje:
                      'Esta cancha no tiene horarios.\nSin ellos los clientes no pueden reservarla.',
                  accion: FilledButton.icon(
                    onPressed: () => FormHorarioSheet.abrir(context, canchaId: canchaId),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear el primero'),
                  ),
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  children: [
                    for (final grupo in _porDia(lista)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          etiquetaDiaSemana(grupo.dia),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final horario in grupo.horarios)
                        _TarjetaHorario(
                          horario: horario,
                          alEditar: () => FormHorarioSheet.abrir(
                            context,
                            canchaId: canchaId,
                            horario: horario,
                          ),
                          alBorrar: () => _confirmarBorrar(context, ref, horario),
                        ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _confirmarBorrar(
    BuildContext context,
    WidgetRef ref,
    HorarioCancha horario,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogoContext) => AlertDialog(
        title: const Text('¿Eliminar el horario?'),
        content: Text(
          'Se quitará ${horario.rango} del ${etiquetaDiaSemana(horario.dia).toLowerCase()}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogoContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogoContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await ref.read(horariosProvider(canchaId).notifier).borrar(horario.id);
      messenger.showSnackBar(const SnackBar(content: Text('Horario eliminado')));
    } on Object catch (error) {
      // El caso real: el horario tiene reservas y el backend responde `409` explicando que
      // no se puede eliminar. Se muestra su frase, no un "no se pudo".
      messenger.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }
}

/// Nombre de la cancha para el título, buscado en la lista que ya está en memoria.
///
/// No se pasa por la URL: el nombre se renombra, y un título con el nombre viejo se nota.
/// Si no está en la lista —un enlace directo a la pantalla— se usa un texto genérico en vez
/// de inventar uno.
String nombreCancha(WidgetRef ref, int canchaId) {
  final canchas = ref.watch(canchasGestionProvider).asData?.value;
  if (canchas == null) return 'tu cancha';
  for (final cancha in canchas) {
    if (cancha.id == canchaId) return cancha.nombre;
  }
  return 'tu cancha';
}

class _TarjetaHorario extends StatelessWidget {
  const _TarjetaHorario({required this.horario, required this.alEditar, required this.alBorrar});

  final HorarioCancha horario;
  final VoidCallback alEditar;
  final VoidCallback alBorrar;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.schedule),
        title: Text(horario.rango),
        subtitle: Text(formatoMonto(horario.tarifa)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: alEditar,
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: alBorrar,
            ),
          ],
        ),
      ),
    );
  }
}

class _GrupoDia {
  const _GrupoDia(this.dia, this.horarios);

  final int dia;
  final List<HorarioCancha> horarios;
}

/// Agrupa por día conservando el orden que vino del backend.
///
/// No reordena: el endpoint ya devuelve `ORDER BY dia, hora_inicio`, y volver a ordenar en
/// la app sería una segunda fuente de verdad para lo mismo.
List<_GrupoDia> _porDia(List<HorarioCancha> horarios) {
  final grupos = <int, List<HorarioCancha>>{};
  for (final horario in horarios) {
    grupos.putIfAbsent(horario.dia, () => []).add(horario);
  }
  return [
    for (final dia in grupos.keys.toList()..sort())
      _GrupoDia(dia, grupos[dia]!),
  ];
}

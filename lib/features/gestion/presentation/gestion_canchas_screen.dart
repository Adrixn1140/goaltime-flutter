import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/format.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/models.dart';
import '../state/gestion_provider.dart';
import 'form_cancha_sheet.dart';
import 'widgets/aviso_gestion.dart';

/// Canchas del dueño (`GET /api/gestion/canchas`).
///
/// Tocar una tarjeta abre sus acciones —horarios, reservas, editar, baja— porque el dueño
/// llega a la app con una tarea, no con un menú: elegir desde la cancha es menos pasos que
/// recordar dónde estaba cada cosa (HEUR-3, HEUR-7).
class GestionCanchasScreen extends ConsumerWidget {
  const GestionCanchasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canchas = ref.watch(canchasGestionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis canchas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => FormCanchaSheet.abrir(context),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cancha'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(canchasGestionProvider.notifier).recargar(),
        child: canchas.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AvisoGestion(
            icono: Icons.cloud_off,
            mensaje: mensajeDeError(error),
            accion: FilledButton.tonal(
              onPressed: () => ref.read(canchasGestionProvider.notifier).recargar(),
              child: const Text('Reintentar'),
            ),
          ),
          data: (lista) => lista.isEmpty
              ? const AvisoGestion(
                  icono: Icons.sports_soccer_outlined,
                  mensaje:
                      'Todavía no tienes canchas.\nCrea la primera para empezar a recibir reservas.',
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: lista.length,
                  itemBuilder: (context, index) => _CanchaCard(cancha: lista[index]),
                ),
        ),
      ),
    );
  }
}

class _CanchaCard extends ConsumerWidget {
  const _CanchaCard({required this.cancha});

  final CanchaGestion cancha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _elegirAccion(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(cancha.nombre, style: theme.textTheme.titleMedium),
                  ),
                  if (!cancha.activo)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Inactiva',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                cancha.ubicacion,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: scheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    '${cancha.totalHorarios} ${cancha.totalHorarios == 1 ? 'horario' : 'horarios'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (cancha.tarifaBase != null) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.payments_outlined, size: 16, color: scheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      'desde ${formatoMonto(cancha.tarifaBase)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              // Una cancha sin horarios no recibe reservas: decirlo aquí evita que el
              // dueño se entere por un cliente que pregunta.
              if (cancha.totalHorarios == 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: scheme.tertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Agrega horarios para que los clientes puedan reservar.',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Muestra las acciones y actúa con la que se elija.
  ///
  /// La hoja devuelve **qué** se eligió en vez de navegar desde dentro de ella: así el
  /// resto de la pantalla usa su propio [BuildContext], que sigue vivo después de cerrar
  /// la hoja. Un `context` de bottom sheet se invalida al cerrarse, y abrir la siguiente
  /// pantalla con él falla justo cuando el dueño hizo lo correcto.
  Future<void> _elegirAccion(BuildContext context, WidgetRef ref) async {
    final accion = await showModalBottomSheet<_AccionCancha>(
      context: context,
      showDragHandle: true,
      builder: (hojaContext) => _HojaAcciones(cancha: cancha),
    );
    if (accion == null || !context.mounted) return;

    switch (accion) {
      case _AccionCancha.horarios:
        context.push('/dueno/canchas/${cancha.id}/horarios');
      case _AccionCancha.reservas:
        context.push('/dueno/canchas/${cancha.id}/reservas');
      case _AccionCancha.editar:
        await FormCanchaSheet.abrir(context, cancha: cancha);
      case _AccionCancha.baja:
        await _confirmarCambioEstado(context, ref);
    }
  }

  /// La baja pide confirmación porque esconde la cancha del catálogo: a los ojos del
  /// cliente es tan fuerte como un borrado, aunque por dentro sólo sea una bandera
  /// (HEUR-3).
  Future<void> _confirmarCambioEstado(BuildContext context, WidgetRef ref) async {
    final reactivar = !cancha.activo;
    final messenger = ScaffoldMessenger.of(context);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogoContext) => AlertDialog(
        title: Text(reactivar ? '¿Reactivar la cancha?' : '¿Dar de baja la cancha?'),
        content: Text(
          reactivar
              ? 'Volverá a aparecer en el catálogo para los clientes.'
              : 'Dejará de aparecer en el catálogo. Sus horarios y reservas se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogoContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogoContext).pop(true),
            child: Text(reactivar ? 'Reactivar' : 'Dar de baja'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      // La baja usa `DELETE` (baja lógica en el backend); la reactivación es un `PATCH`
      // con `activo: true`. Son los dos verbos que el contrato define para esto.
      final notifier = ref.read(canchasGestionProvider.notifier);
      if (reactivar) {
        await notifier.reactivar(cancha.id);
      } else {
        await notifier.bajar(cancha.id);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(reactivar ? 'Cancha reactivada' : 'Cancha dada de baja')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }
}

enum _AccionCancha { horarios, reservas, editar, baja }

class _HojaAcciones extends StatelessWidget {
  const _HojaAcciones({required this.cancha});

  final CanchaGestion cancha;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      // Desplazable porque la hoja tiene un alto por omisión y en una pantalla baja las
      // cinco filas no caben: sin esto el último verb —dar de baja— quedaba cortado.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(cancha.nombre, style: theme.textTheme.titleMedium),
              subtitle: Text(cancha.ubicacion),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Horarios'),
              subtitle: Text('${cancha.totalHorarios} definidos'),
              onTap: () => Navigator.of(context).pop(_AccionCancha.horarios),
            ),
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('Reservas'),
              onTap: () => Navigator.of(context).pop(_AccionCancha.reservas),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar datos'),
              onTap: () => Navigator.of(context).pop(_AccionCancha.editar),
            ),
            ListTile(
              leading: Icon(cancha.activo ? Icons.pause_circle_outline : Icons.play_circle_outline),
              title: Text(cancha.activo ? 'Dar de baja' : 'Reactivar'),
              subtitle: Text(
                cancha.activo
                    ? 'Deja de aparecer en el catálogo, sin borrar su historial'
                    : 'Vuelve a aparecer en el catálogo',
              ),
              onTap: () => Navigator.of(context).pop(_AccionCancha.baja),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

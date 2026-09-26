import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_state.dart' show mensajeDeError;
import '../../gestion/presentation/widgets/aviso_gestion.dart';
import '../data/models.dart';
import '../state/admin_provider.dart';

/// Usuarios de la plataforma (`GET /api/usuarios`).
///
/// Cada fila resume lo que el admin necesita para decidir sin abrir otra pantalla —rol,
/// estado y cuántos turnos y reservas tiene encima— y las acciones viven en la tarjeta,
/// no en un menú escondido (HEUR-3, HEUR-6). Los conteos son también el aviso previo: si
/// el dueño tiene 3 canchas, la app lo dice antes de que el backend responda `422`.
class UsuariosScreen extends ConsumerWidget {
  const UsuariosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuarios = ref.watch(usuariosAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(usuariosAdminProvider.notifier).recargar(),
        child: usuarios.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AvisoGestion(
            icono: Icons.cloud_off,
            mensaje: mensajeDeError(error),
            accion: FilledButton.tonal(
              onPressed: () => ref.read(usuariosAdminProvider.notifier).recargar(),
              child: const Text('Reintentar'),
            ),
          ),
          data: (lista) => lista.isEmpty
              ? const AvisoGestion(
                  icono: Icons.people_outline,
                  mensaje: 'No hay usuarios registrados.',
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: lista.length,
                  itemBuilder: (context, index) => _UsuarioCard(usuario: lista[index]),
                ),
        ),
      ),
    );
  }
}

class _UsuarioCard extends ConsumerWidget {
  const _UsuarioCard({required this.usuario});

  final UsuarioAdmin usuario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final inactivo = !usuario.activo;

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
                children: [
                  CircleAvatar(child: Text(usuario.nombre.characters.first.toUpperCase())),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(usuario.nombre, style: theme.textTheme.titleMedium),
                        Text(usuario.email, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  RolChip(rol: usuario.rol),
                ],
              ),
              const SizedBox(height: 12),
              // Los conteos van como texto y no sólo como número suelto: un `3` al lado
              // de un ícono de cancha no dice de qué son las tres (HEUR-2).
              Text(
                '${usuario.canchas} ${usuario.canchas == 1 ? 'cancha' : 'canchas'} · '
                '${usuario.reservas} ${usuario.reservas == 1 ? 'reserva' : 'reservas'}',
                style: theme.textTheme.bodyMedium,
              ),
              if (inactivo)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Cuenta desactivada: no puede iniciar sesión',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _elegirAccion(BuildContext context, WidgetRef ref) async {
    final accion = await showModalBottomSheet<_AccionUsuario>(
      context: context,
      showDragHandle: true,
      builder: (context) => _HojaAcciones(usuario: usuario),
    );
    if (accion == null || !context.mounted) return;

    switch (accion) {
      case _AccionUsuario.cambiarRol:
        final rol = await _elegirRol(context);
        if (rol == null || !context.mounted) return;
        await _aplicar(context, ref, () => _cambiar(ref, rol: rol));
      case _AccionUsuario.activar:
        await _aplicar(context, ref, () => _cambiar(ref, activo: true));
      case _AccionUsuario.desactivar:
        await _confirmarDesactivar(context, ref);
    }
  }

  Future<RolUsuario?> _elegirRol(BuildContext context) {
    return showModalBottomSheet<RolUsuario>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Cambiar el rol de ${usuario.nombre}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              for (final rol in RolUsuario.values)
                ListTile(
                  leading: Icon(_iconoDe(rol)),
                  title: Text(rol.etiqueta),
                  // El rol actual se marca y no se puede volver a elegir: el backend lo
                  // aceptaría, pero es un viaje en círculo que no le dice nada al admin.
                  trailing: rol == usuario.rol ? const Icon(Icons.check) : null,
                  enabled: rol != usuario.rol,
                  onTap: () => Navigator.of(context).pop(rol),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarDesactivar(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desactivar la cuenta?'),
        content: Text(
          '${usuario.nombre} no podrá iniciar sesión y sus sesiones abiertas dejarán de '
          'funcionar.\nSus reservas y su historial se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _aplicar(context, ref, () => _cambiar(ref, activo: false));
  }

  /// Envuelve la mutación para que un `422` del backend se vea como lo que es: un
  /// mensaje que dice qué hacer, no una pantalla que se queda quieta.
  Future<void> _aplicar(BuildContext context, WidgetRef ref, Future<void> Function() accion) async {
    // El `messenger` se toma antes de esperar: después del async gap el `context` puede
    // haber salido del árbol y buscarlo ahí lanzaría en vez de mostrar el error.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await accion();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(mensajeDeError(error)), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _cambiar(WidgetRef ref, {RolUsuario? rol, bool? activo}) async {
    final notificador = ref.read(usuariosAdminProvider.notifier);
    await notificador.cambiar(usuario.id, rol: rol, activo: activo);
    // El reporte cuenta usuarios por rol y los inactivos, así que cualquier cambio lo deja
    // viejo: invalidarlo aquí evita que el admin lea "3 dueños" con 2 en la lista de arriba.
    ref.invalidate(reporteProvider);
  }
}

IconData _iconoDe(RolUsuario rol) => switch (rol) {
  RolUsuario.cliente => Icons.person_outline,
  RolUsuario.dueno => Icons.sports_soccer_outlined,
  RolUsuario.admin => Icons.shield_outlined,
};

enum _AccionUsuario { cambiarRol, activar, desactivar }

class _HojaAcciones extends StatelessWidget {
  const _HojaAcciones({required this.usuario});

  final UsuarioAdmin usuario;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(usuario.nombre, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(usuario.email),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Cambiar rol'),
              subtitle: Text('Ahora es ${usuario.etiquetaRol.toLowerCase()}'),
              onTap: () => Navigator.of(context).pop(_AccionUsuario.cambiarRol),
            ),
            ListTile(
              leading: Icon(usuario.activo ? Icons.person_off_outlined : Icons.person_add_alt),
              title: Text(usuario.activo ? 'Desactivar cuenta' : 'Activar cuenta'),
              subtitle: Text(
                usuario.activo
                    ? 'Deja de poder entrar; su historial se conserva'
                    : 'Vuelve a poder iniciar sesión',
              ),
              onTap: () => Navigator.of(
                context,
              ).pop(usuario.activo ? _AccionUsuario.desactivar : _AccionUsuario.activar),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta del rol. Reutiliza la paleta de `EstadoChip` para que el admin no tenga que
/// aprender un color nuevo por rol: azul = admin, verde = dueño, neutro = cliente.
class RolChip extends StatelessWidget {
  const RolChip({super.key, required this.rol});

  final RolUsuario rol;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (fondo, texto) = switch (rol) {
      RolUsuario.admin => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      RolUsuario.dueno => (scheme.primaryContainer, scheme.onPrimaryContainer),
      RolUsuario.cliente => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
      child: Text(rol.etiqueta, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: texto)),
    );
  }
}

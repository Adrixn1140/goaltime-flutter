import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_state.dart';
import '../state/canchas_provider.dart';
import '../state/reservas_provider.dart';

/// Perfil del cliente: los datos que el backend ya devolvió al iniciar sesión y el
/// cierre de sesión.
///
/// El backend no expone todavía "mi perfil" (`GET /api/usuarios/perfil` está fuera de
/// esta sesión), así que la pantalla muestra lo que se guardó en el almacenamiento seguro
/// al entrar. Se dice explícitamente en pantalla para que el usuario no crea que es un
/// perfil editable.
class PerfilScreen extends ConsumerWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usuario = ref.watch(authProvider).usuario;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person,
                      size: 30,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          usuario?.nombre ?? 'Cliente',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          usuario?.email ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Rol'),
            trailing: Text(
              switch (ref.watch(authProvider).role) {
                AppRole.dueno => 'Dueño',
                AppRole.admin => 'Administrador',
                AppRole.cliente || null => 'Cliente',
              },
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () => _confirmarSalir(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 12),
          Text(
            'Al cerrar sesión se borra la sesión guardada en este teléfono.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  /// Confirmación antes de salir: cerrar sesión tira abajo las reservas que el usuario
  /// estaba viendo, así que se pregunta en vez de hacerlo de un toque (HEUR-3, HEUR-7).
  Future<void> _confirmarSalir(BuildContext context, WidgetRef ref) async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tendrás que volver a entrar con tu correo y contraseña.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (salir != true) return;
    // El router devuelve al login al cambiar el estado de sesión; la lista de reservas se
    // invalida para que el próximo cliente que entre en este teléfono no vea las de otro.
    ref.invalidate(misReservasProvider);
    ref.invalidate(canchasProvider);
    await ref.read(authProvider.notifier).signOut();
  }
}

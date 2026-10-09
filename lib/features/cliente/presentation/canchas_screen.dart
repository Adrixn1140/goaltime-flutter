import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/format.dart';
import '../../../shared/widgets/sport_banner.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/models.dart';
import '../state/canchas_provider.dart';

/// Catálogo de canchas (`GET /api/canchas`).
///
/// HEUR-6: el usuario reconoce la cancha por nombre, foto y ubicación, no por un id.
/// HEUR-1: los tres estados posibles (cargando, con datos, sin datos) están dibujados.
class CanchasScreen extends ConsumerWidget {
  const CanchasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canchas = ref.watch(canchasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Canchas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(canchasProvider.notifier).recargar(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(canchasProvider.notifier).recargar(),
        child: canchas.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Aviso(
            icono: Icons.cloud_off,
            titulo: 'No pudimos cargar las canchas',
            mensaje: mensajeDeError(error),
            accion: FilledButton.tonal(
              onPressed: () => ref.read(canchasProvider.notifier).recargar(),
              child: const Text('Reintentar'),
            ),
          ),
          data: (lista) => lista.isEmpty
              ? const _Aviso(
                  icono: Icons.sports_soccer_outlined,
                  titulo: 'Todavía no hay canchas',
                  mensaje:
                      'Apenas se publiquen, aparecerán aquí para reservar.',
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: lista.length + 1,
                  itemBuilder: (context, index) => index == 0
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: SportBanner(
                            etiqueta: 'GoalTime · Riohacha',
                            titulo: 'Haz espacio\npara jugar.',
                            descripcion:
                                'Encuentra tu cancha y reúne a tu equipo.',
                            accion: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFB9F36B),
                              ),
                              onPressed: () => context.go('/cliente/equipos'),
                              icon: const Icon(Icons.groups_outlined),
                              label: const Text('Organizar mi equipo'),
                            ),
                          ),
                        )
                      : _CanchaCard(cancha: lista[index - 1]),
                ),
        ),
      ),
    );
  }
}

class _CanchaCard extends StatelessWidget {
  const _CanchaCard({required this.cancha});

  final Cancha cancha;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        // HEUR-6: toda la tarjeta es la acción; el usuario no busca un botón pequeño.
        onTap: () => context.push('/cliente/canchas/${cancha.id}/reserva'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Foto(cancha: cancha),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cancha.nombre,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 14,
                              color: scheme.outline,
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                cancha.ubicacion,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.outline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        cancha.tarifaBase == null ? 'Sin horarios' : 'Desde',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                      Text(
                        formatoMonto(cancha.tarifaBase),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Icon(Icons.chevron_right, color: scheme.outline),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Foto extends StatelessWidget {
  const _Foto({required this.cancha});

  final Cancha cancha;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // El seed no trae fotos (`foto` vacío a propósito): en vez de un marco roto se
    // muestra el color de marca, que es lo que verá el usuario hasta que haya assets.
    return SizedBox(
      height: 150,
      width: double.infinity,
      child: cancha.tieneFoto
          ? Image.network(
              cancha.foto,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(scheme),
            )
          : _placeholder(scheme),
    );
  }

  Widget _placeholder(ColorScheme scheme) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF164A3B), Color(0xFF278864)],
      ),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: .25),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: .25),
              width: 2,
            ),
          ),
        ),
        const Icon(Icons.sports_soccer, size: 42, color: Color(0xFFDAF4B8)),
        const Positioned(
          left: 28,
          bottom: 26,
          child: Text(
            'TU PRÓXIMO PARTIDO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(icono, size: 56, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          mensaje,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        if (accion != null) ...[
          const SizedBox(height: 24),
          Center(child: accion),
        ],
      ],
    );
  }
}

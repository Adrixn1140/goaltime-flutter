import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/sport_banner.dart';
import '../../auth/auth_state.dart';
import '../data/arbitros_repository.dart';
import '../state/arbitros_provider.dart';

class ArbitrosScreen extends ConsumerStatefulWidget {
  const ArbitrosScreen({super.key});
  @override
  ConsumerState<ArbitrosScreen> createState() => _ArbitrosScreenState();
}

class _ArbitrosScreenState extends ConsumerState<ArbitrosScreen> {
  final _texto = TextEditingController();
  String _consulta = '';
  bool _solo = false;
  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtro = (q: _consulta, soloDisponibles: _solo);
    final perfiles = ref.watch(arbitrosProvider(filtro));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Árbitros'),
        leading: GoRouterState.of(context).uri.path == '/arbitros'
            ? BackButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(arbitrosProvider(filtro).future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const SportBanner(
              etiqueta: 'Juego limpio',
              titulo: 'Quien pone\nlas reglas.',
              descripcion: 'Conoce árbitros y compara sus tarifas por partido.',
              icono: Icons.sports_outlined,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _texto,
              maxLength: 100,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Nombre o ciudad',
                counterText: '',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Buscar árbitros',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () =>
                      setState(() => _consulta = _texto.text.trim()),
                ),
              ),
              onSubmitted: (_) =>
                  setState(() => _consulta = _texto.text.trim()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Solo disponibles'),
                  selected: _solo,
                  onSelected: (valor) => setState(() => _solo = valor),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _texto.clear();
                    _consulta = '';
                    _solo = false;
                  }),
                  child: const Text('Limpiar filtros'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Disponibilidad declarada, no una agenda confirmada. Perfiles y experiencia no verificados. Tarifas orientativas en COP, de menor a mayor.',
            ),
            const SizedBox(height: 20),
            perfiles.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Column(
                children: [
                  Text(mensajeDeError(error)),
                  TextButton(
                    onPressed: () => ref.invalidate(arbitrosProvider(filtro)),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
              data: (lista) => lista.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No hay árbitros publicados con estos filtros. Prueba otra búsqueda.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Column(
                      children: lista
                          .map((p) => _PerfilCard(perfil: p))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerfilCard extends StatelessWidget {
  const _PerfilCard({required this.perfil});
  final PerfilArbitro perfil;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = perfil;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.sports)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p.nombre, style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text(p.disponible ? 'Disponible' : 'No disponible'),
                ),
                Chip(label: Text('${p.experiencia} años de experiencia')),
              ],
            ),
            Text(p.ciudad, style: theme.textTheme.titleMedium),
            if (p.biografia.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(p.biografia),
            ],
            const Divider(height: 28),
            Text(
              '${NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: p.tarifa % 1 == 0 ? 0 : 2).format(p.tarifa)} COP / partido',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText('Contacto: ${p.celular}'),
            const SizedBox(height: 6),
            const Text(
              'Acuerda detalles directamente. Sin contratación ni cobro dentro de la app.',
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/sport_banner.dart';
import '../../auth/auth_state.dart';
import '../data/equipos_repository.dart';
import '../state/equipos_provider.dart';

class EquiposScreen extends ConsumerWidget {
  const EquiposScreen({super.key});

  Future<void> _crear(BuildContext context, WidgetRef ref) async {
    final resultado = await showModalBottomSheet<Equipo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) =>
          _FormularioEquipo(repository: ref.read(equiposRepositoryProvider)),
    );
    if (resultado == null || !context.mounted) return;
    ref.invalidate(equiposProvider);
    context.push('/cliente/equipos/${resultado.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipos = ref.watch(equiposProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mis equipos')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(equiposProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SportBanner(
              etiqueta: 'El próximo partido empieza aquí',
              titulo: 'Tu gente.\nTu equipo.',
              descripcion: 'Arma tu plantilla y prepárate para lo que viene.',
              icono: Icons.shield_outlined,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _crear(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Crear equipo'),
            ),
            const SizedBox(height: 24),
            Text(
              'TUS PLANTILLAS',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            equipos.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _ErrorCarga(
                error: error,
                reintentar: () => ref.invalidate(equiposProvider),
              ),
              data: (lista) => lista.isEmpty
                  ? const _EstadoVacio(
                      titulo: 'Aquí comienza tu equipo',
                      mensaje: 'Crea tu primer equipo y añade a quienes juegan contigo.',
                    )
                  : Column(
                      children: lista
                          .map(
                            (equipo) => Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                leading: const CircleAvatar(
                                  child: Icon(Icons.shield_outlined),
                                ),
                                title: Text(
                                  equipo.nombre,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${equipo.jugadores.length} jugadores · Plantilla privada',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push(
                                  '/cliente/equipos/${equipo.id}',
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Avance hacia torneos · Por ahora, solo equipos y jugadores.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class EquipoScreen extends ConsumerWidget {
  const EquipoScreen({super.key, required this.id});
  final int id;

  Future<void> _agregar(BuildContext context, WidgetRef ref) async {
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _FormularioEquipo(
        repository: ref.read(equiposRepositoryProvider),
        equipoId: id,
      ),
    );
    if (creado != true || !context.mounted) return;
    ref.invalidate(equipoProvider(id));
    ref.invalidate(equiposProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Jugador añadido al equipo')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipo = ref.watch(equipoProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Plantilla del equipo')),
      body: equipo.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _ErrorCarga(
              error: error,
              reintentar: () => ref.invalidate(equipoProvider(id)),
            ),
          ),
        ),
        data: (datos) => RefreshIndicator(
          onRefresh: () => ref.refresh(equipoProvider(id).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SportBanner(
                etiqueta: 'Mi equipo',
                titulo: datos.nombre,
                descripcion:
                    '${datos.jugadores.length} jugadores en tu plantilla',
                icono: Icons.shield_outlined,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _agregar(context, ref),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Añadir jugador'),
              ),
              const SizedBox(height: 20),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline),
                title: Text('Plantilla privada'),
                subtitle: Text(
                  'Solo tú puedes ver estos datos. Usa datos ficticios en la demo.',
                ),
              ),
              if (datos.jugadores.isEmpty)
                const _EstadoVacio(
                  titulo: 'Falta el primer fichaje',
                  mensaje: 'Añade un jugador para empezar tu plantilla.',
                )
              else
                ...datos.jugadores.map(
                  (jugador) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                child: Text(
                                  jugador.nombre.substring(0, 1).toUpperCase(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  jugador.nombreCompleto,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          Text('Documento  ${jugador.documentoOculto}'),
                          const SizedBox(height: 8),
                          Text('Celular  ${jugador.celular}'),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.titulo, required this.mensaje});
  final String titulo, mensaje;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
    child: Column(
      children: [
        Icon(
          Icons.groups_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          titulo,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(mensaje, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _ErrorCarga extends StatelessWidget {
  const _ErrorCarga({required this.error, required this.reintentar});
  final Object error;
  final VoidCallback reintentar;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(mensajeDeError(error), textAlign: TextAlign.center),
      TextButton(onPressed: reintentar, child: const Text('Reintentar')),
    ],
  );
}

/// El formulario permanece abierto si falla el servidor, sin perder lo escrito.
class _FormularioEquipo extends StatefulWidget {
  const _FormularioEquipo({required this.repository, this.equipoId});
  final EquiposRepository repository;
  final int? equipoId;
  @override
  State<_FormularioEquipo> createState() => _FormularioEquipoState();
}

class _FormularioEquipoState extends State<_FormularioEquipo> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _documento = TextEditingController();
  final _celular = TextEditingController();
  bool _guardando = false;
  String? _error;
  bool get _jugador => widget.equipoId != null;

  @override
  void dispose() {
    for (final controller in [_nombre, _apellido, _documento, _celular]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate() || _guardando) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_jugador) {
        await widget.repository.agregarJugador(widget.equipoId!, {
          'nombre': _nombre.text.trim(),
          'apellido': _apellido.text.trim(),
          'documento': _documento.text.trim(),
          'celular': _celular.text.trim(),
        });
        if (mounted) Navigator.pop(context, true);
      } else {
        final equipo = await widget.repository.crear(_nombre.text.trim());
        if (mounted) Navigator.pop(context, equipo);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = mensajeDeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_guardando,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _jugador ? 'Nuevo jugador' : 'Nuevo equipo',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancelar',
                    onPressed: _guardando ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _jugador
                    ? 'Usa datos ficticios para esta demostración.'
                    : 'Dale un nombre a quienes juegan contigo.',
              ),
              const SizedBox(height: 24),
              _campo(
                _nombre,
                _jugador ? 'Nombre' : 'Nombre del equipo',
                _jugador ? 2 : 3,
                80,
              ),
              if (_jugador) ...[
                const SizedBox(height: 16),
                _campo(_apellido, 'Apellido', 2, 80),
                const SizedBox(height: 16),
                _campo(
                  _documento,
                  'Número de documento',
                  5,
                  20,
                  numerico: true,
                ),
                const SizedBox(height: 16),
                _campo(_celular, 'Celular', 10, 15, numerico: true),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_jugador ? 'Guardar jugador' : 'Guardar equipo'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _campo(
    TextEditingController controller,
    String label,
    int minimo,
    int maximo, {
    bool numerico = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_guardando,
    maxLength: maximo,
    keyboardType: numerico ? TextInputType.number : TextInputType.text,
    textCapitalization: numerico
        ? TextCapitalization.none
        : TextCapitalization.words,
    textInputAction: TextInputAction.next,
    inputFormatters: numerico ? [FilteringTextInputFormatter.digitsOnly] : null,
    decoration: InputDecoration(
      labelText: label,
      counterText: '',
      helperText: numerico
          ? 'De $minimo a $maximo dígitos, sin espacios ni +'
          : null,
    ),
    validator: (value) {
      final texto = value?.trim() ?? '';
      if (texto.length < minimo || texto.length > maximo) {
        return 'Escribe entre $minimo y $maximo ${numerico ? 'dígitos' : 'caracteres'}';
      }
      return null;
    },
  );
}

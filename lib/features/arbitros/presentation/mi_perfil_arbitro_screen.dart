import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/sport_banner.dart';
import '../../auth/auth_state.dart';
import '../data/arbitros_repository.dart';
import '../state/arbitros_provider.dart';

class MiPerfilArbitroScreen extends ConsumerWidget {
  const MiPerfilArbitroScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Mi perfil arbitral')),
    body: ref
        .watch(miPerfilArbitroProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mensajeDeError(error)),
                TextButton(
                  onPressed: () => ref.invalidate(miPerfilArbitroProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
          data: (perfil) => _EditorPerfil(
            key: ValueKey(ref.watch(authProvider).usuario?.email),
            perfil: perfil,
          ),
        ),
  );
}

class _EditorPerfil extends ConsumerStatefulWidget {
  const _EditorPerfil({super.key, this.perfil});
  final PerfilArbitro? perfil;
  @override
  ConsumerState<_EditorPerfil> createState() => _EditorPerfilState();
}

class _EditorPerfilState extends ConsumerState<_EditorPerfil> {
  final _form = GlobalKey<FormState>();
  final _ciudad = TextEditingController(),
      _celular = TextEditingController(),
      _experiencia = TextEditingController(),
      _tarifa = TextEditingController(),
      _bio = TextEditingController();
  bool _publicado = false, _disponible = true, _guardando = false;
  String? _error;
  String? _guardado;
  @override
  void initState() {
    super.initState();
    final p = widget.perfil;
    _ciudad.text = p?.ciudad ?? '';
    _celular.text = p?.celular ?? '';
    _experiencia.text = '${p?.experiencia ?? 0}';
    _tarifa.text = p?.tarifa.toStringAsFixed(2) ?? '';
    _bio.text = p?.biografia ?? '';
    _publicado = p?.publicado ?? false;
    _disponible = p?.disponible ?? true;
  }

  @override
  void dispose() {
    for (final c in [_ciudad, _celular, _experiencia, _tarifa, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
      _guardado = null;
    });
    try {
      final perfil = await ref.read(arbitrosRepositoryProvider).guardar({
        'ciudad': _ciudad.text.trim(),
        'celular': _celular.text.trim(),
        'experiencia': int.parse(_experiencia.text),
        'tarifa': _tarifa.text.replaceAll(',', '.').trim(),
        'biografia': _bio.text.trim(),
        'disponible': _disponible,
        'publicado': _publicado,
      });
      if (!mounted) return;
      ref.invalidate(arbitrosProvider);
      ref.invalidate(miPerfilArbitroProvider);
      setState(() {
        _guardando = false;
        _guardado = perfil.publicado
            ? 'Perfil guardado y publicado en el directorio.'
            : 'Perfil guardado en privado. No aparece en el directorio.';
      });
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
    child: Form(
      key: _form,
      onChanged: () {
        if (_guardado != null) setState(() => _guardado = null);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SportBanner(
            etiqueta: 'Tu presentación',
            titulo: 'Hazte visible.',
            descripcion: 'Tú decides qué ofreces y cuándo publicar tu perfil.',
            icono: Icons.sports_outlined,
          ),
          const SizedBox(height: 20),
          Text(
            ref.watch(authProvider).usuario?.nombre ?? 'Árbitro',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _campo(
            _ciudad,
            'Ciudad',
            max: 100,
            validator: (v) =>
                v.length < 2 ? 'Escribe tu ciudad (mínimo 2 caracteres)' : null,
          ),
          const SizedBox(height: 16),
          _campo(
            _celular,
            'Celular de contacto',
            max: 15,
            numerico: true,
            validator: (v) => RegExp(r'^[0-9]{10,15}$').hasMatch(v)
                ? null
                : 'Escribe de 10 a 15 dígitos',
          ),
          const SizedBox(height: 16),
          _campo(
            _experiencia,
            'Años de experiencia',
            max: 2,
            numerico: true,
            validator: (v) =>
                (int.tryParse(v) ?? -1) < 0 || (int.tryParse(v) ?? 61) > 60
                ? 'Entre 0 y 60 años'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _tarifa,
            enabled: !_guardando,
            maxLength: 11,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tarifa por partido (COP)',
              helperText:
                  'Sin separadores de miles. Ejemplo: 55000 o 55000,50.',
            ),
            validator: (v) {
              final valor = (v ?? '').trim().replaceAll(',', '.');
              final numero = double.tryParse(valor);
              return !RegExp(r'^[0-9]+(\.[0-9]{1,2})?$').hasMatch(valor) ||
                      numero == null ||
                      numero <= 0 ||
                      numero > 10000000
                  ? 'Mayor que 0, hasta 10.000.000; máximo 2 decimales'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _bio,
            enabled: !_guardando,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Presentación',
              helperText:
                  'Modalidades, experiencia y lo que incluye tu tarifa.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disponible'),
            subtitle: const Text(
              'Declaración general, no una agenda confirmada.',
            ),
            value: _disponible,
            onChanged: _guardando
                ? null
                : (v) => setState(() {
                    _disponible = v;
                    _guardado = null;
                  }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Publicar perfil'),
            subtitle: const Text(
              'Autorizo mostrar mi nombre, ciudad, celular, presentación, experiencia y tarifa a otras cuentas. Desactívalo y guarda para ocultarme.',
            ),
            value: _publicado,
            onChanged: _guardando
                ? null
                : (v) => setState(() {
                    _publicado = v;
                    _guardado = null;
                  }),
          ),
          const Text(
            'Los cambios de publicación y disponibilidad solo se aplican al guardar. Usa datos ficticios durante la demo.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_guardado != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_guardado!),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_guardando ? 'Guardando…' : 'Guardar perfil'),
          ),
          TextButton(
            onPressed: _guardando
                ? null
                : () => context.go('/arbitro/directorio'),
            child: const Text('Ver directorio de árbitros'),
          ),
        ],
      ),
    ),
  );

  Widget _campo(
    TextEditingController controller,
    String label, {
    required int max,
    required String? Function(String) validator,
    bool numerico = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_guardando,
    maxLength: max,
    textInputAction: TextInputAction.next,
    keyboardType: numerico ? TextInputType.number : TextInputType.text,
    textCapitalization: numerico
        ? TextCapitalization.none
        : TextCapitalization.words,
    inputFormatters: numerico ? [FilteringTextInputFormatter.digitsOnly] : null,
    decoration: InputDecoration(labelText: label, counterText: ''),
    validator: (v) => validator((v ?? '').trim()),
  );
}

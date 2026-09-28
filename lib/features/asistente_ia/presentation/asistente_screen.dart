import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/format.dart';
import '../data/models.dart';
import '../state/asistente_provider.dart';

/// Asistente de reserva por lenguaje natural (`spec.md 3.6`).
///
/// Un chat en el que la persona escribe "quiero jugar mañana en la noche" y recibe una
/// respuesta redactada con hasta tres canchas libres. Cada sugerencia es un botón que
/// lleva a la reserva con el día y el horario ya preseleccionados: el asistente no
/// reserva, suguiere —quien confirma es la persona, en la pantalla de reserva.
class AsistenteScreen extends ConsumerStatefulWidget {
  const AsistenteScreen({super.key});

  @override
  ConsumerState<AsistenteScreen> createState() => _AsistenteScreenState();
}

class _AsistenteScreenState extends ConsumerState<AsistenteScreen> {
  final _controlador = TextEditingController();
  final _lista = ScrollController();

  @override
  void dispose() {
    _controlador.dispose();
    _lista.dispose();
    super.dispose();
  }

  void _enviar() {
    final texto = _controlador.text;
    if (texto.trim().isEmpty) return;
    _controlador.clear();
    ref.read(conversacionProvider.notifier).enviar(texto);
  }

  void _bajarAlFinal() {
    if (!_lista.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_lista.hasClients) return;
      _lista.animateTo(
        _lista.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversacion = ref.watch(conversacionProvider);

    // Cada mensaje nuevo (del usuario o del asistente) cierra el scroll al final, para
    // que la burbuja que acaba de aparecer no quede fuera de vista.
    ref.listen(conversacionProvider, (anterior, siguiente) {
      if (anterior != null &&
          siguiente.mensajes.length != anterior.mensajes.length) {
        _bajarAlFinal();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Asistente')),
      body: Column(
        children: [
          Expanded(
            child: conversacion.mensajes.isEmpty
                ? const _Saludo()
                : ListView.builder(
                    controller: _lista,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: conversacion.mensajes.length + (conversacion.enviando ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == conversacion.mensajes.length) {
                        return const _BurbujaPensando();
                      }
                      final mensaje = conversacion.mensajes[index];
                      return _Burbuja(
                        mensaje: mensaje,
                        alReservar: _irAReserva,
                      );
                    },
                  ),
          ),
          _BarraDeEscritura(
            controlador: _controlador,
            enviando: conversacion.enviando,
            alEnviar: _enviar,
          ),
        ],
      ),
    );
  }

  void _irAReserva(SugerenciaAsistente sugerencia) {
    // La fecha y el horario viajan por query para que la pantalla de reserva los
    // pueda preseleccionar sin cargar estado intermedio: el asistente no reserva, sólo
    // lleva a la persona al paso de confirmar con los datos que él eligió.
    context.go(
      '/cliente/canchas/${sugerencia.canchaId}/reserva'
      '?fecha=${sugerencia.fecha}&horario_id=${sugerencia.horarioId}',
    );
  }
}

/// Primera visita: antes de mandar el primer mensaje la pantalla explica qué es esto.
class _Saludo extends StatelessWidget {
  const _Saludo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Cuéntame cuándo quieres jugar\ny te busco canchas libres.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Por ejemplo: "mañana en la noche"',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.mensaje, required this.alReservar});

  final MensajeChat mensaje;
  final ValueChanged<SugerenciaAsistente> alReservar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delUsuario = mensaje.delUsuario;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            delUsuario ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: delUsuario ? scheme.primaryContainer : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(delUsuario ? 16 : 4),
                bottomRight: Radius.circular(delUsuario ? 4 : 16),
              ),
            ),
            child: Text(
              mensaje.texto,
              style: TextStyle(
                color: delUsuario ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ),
          if (mensaje.sugerencias.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...mensaje.sugerencias.map(
              (sugerencia) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _TarjetaSugerencia(
                  sugerencia: sugerencia,
                  alReservar: () => alReservar(sugerencia),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaSugerencia extends StatelessWidget {
  const _TarjetaSugerencia({required this.sugerencia, required this.alReservar});

  final SugerenciaAsistente sugerencia;
  final VoidCallback alReservar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sports_soccer, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sugerencia.cancha,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${etiquetaFecha(sugerencia.fecha)} · ${sugerencia.rango}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  formatoMonto(sugerencia.tarifa),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: alReservar,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('Reservar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BurbujaPensando extends StatelessWidget {
  const _BurbujaPensando();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          const Text('Buscando…'),
        ],
      ),
    );
  }
}

class _BarraDeEscritura extends StatelessWidget {
  const _BarraDeEscritura({
    required this.controlador,
    required this.enviando,
    required this.alEnviar,
  });

  final TextEditingController controlador;
  final bool enviando;
  final VoidCallback alEnviar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controlador,
              enabled: !enviando,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => alEnviar(),
              decoration: const InputDecoration(
                hintText: 'Escribe tu petición…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: enviando ? null : alEnviar,
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Enviar',
          ),
        ],
      ),
    );
  }
}
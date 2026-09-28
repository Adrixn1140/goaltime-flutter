import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/asistente_repository.dart';
import '../data/models.dart';

final asistenteRepositoryProvider = Provider<AsistenteRepository>(
  (ref) => AsistenteRepository(ref.watch(apiClientProvider)),
);

/// Un mensaje de la conversación, del usuario o del asistente.
///
/// Las [sugerencias] sólo las traen las respuestas del asistente que consultaron
/// disponibilidad: un saludo no trae ninguna, y tampoco es un error que no traiga.
class MensajeChat {
  const MensajeChat({
    required this.delUsuario,
    required this.texto,
    this.sugerencias = const [],
  });

  final bool delUsuario;
  final String texto;
  final List<SugerenciaAsistente> sugerencias;
}

/// Estado de la conversación con el asistente.
///
/// `enviando` es lo que deshabilita el campo y muestra el indicador: un mensaje no se
/// puede mandar mientras el anterior sigue en vuelo, porque el asistente es de dos
/// vueltas y el orden de los turnos importa.
class ConversacionEstado {
  const ConversacionEstado({this.mensajes = const [], this.enviando = false});

  final List<MensajeChat> mensajes;
  final bool enviando;
}

final conversacionProvider =
    NotifierProvider<ConversacionNotifier, ConversacionEstado>(ConversacionNotifier.new);

class ConversacionNotifier extends Notifier<ConversacionEstado> {
  @override
  ConversacionEstado build() => const ConversacionEstado();

  /// Envía la frase del usuario y encola la respuesta del asistente.
  ///
  /// El mensaje del usuario entra primero (para que se vea en el orden que se
  /// escribió), luego viene la respuesta. Un fallo de red o del backend (502 del
  /// proveedor) se muestra como otro mensaje del asistente, con el texto ya
  /// redactado para la persona — igual que haría en una conversación real.
  Future<void> enviar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty || state.enviando) return;

    state = ConversacionEstado(
      mensajes: [
        ...state.mensajes,
        MensajeChat(delUsuario: true, texto: limpio),
      ],
      enviando: true,
    );

    final RespuestaAsistente respuesta;
    try {
      respuesta = await ref.read(asistenteRepositoryProvider).consultar(mensaje: limpio);
    } catch (error) {
      state = ConversacionEstado(
        mensajes: [
          ...state.mensajes,
          MensajeChat(delUsuario: false, texto: mensajeDeError(error)),
        ],
      );
      return;
    }

    state = ConversacionEstado(
      mensajes: [
        ...state.mensajes,
        MensajeChat(
          delUsuario: false,
          texto: respuesta.respuesta,
          sugerencias: respuesta.sugerencias,
        ),
      ],
    );
  }
}
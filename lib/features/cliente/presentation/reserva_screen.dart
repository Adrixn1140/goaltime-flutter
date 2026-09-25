import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/format.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../data/models.dart';
import '../state/canchas_provider.dart';
import '../state/disponibilidad_provider.dart';
import '../state/reservas_provider.dart';
import 'pago_sheet.dart';
import 'widgets/dia_selector.dart';
import 'widgets/slot_tile.dart';

/// Disponibilidad de una cancha y creación de la reserva (`spec.md 3.2`).
///
/// El flujo es ver → elegir → confirmar → pagar. La confirmación de la reserva va en un
/// diálogo aparte con el resumen (cancha, día, hora y precio) porque el precio lo calcula
/// el backend: mostrarlo antes de enviar evita el "esto no era lo que pensé" (HEUR-5,
/// HEUR-8). El monto que se confirma es el mismo que el backend cobra.
class PantallaReserva extends ConsumerStatefulWidget {
  const PantallaReserva({super.key, required this.canchaId});

  final int canchaId;

  @override
  ConsumerState<PantallaReserva> createState() => _PantallaReservaState();
}

class _PantallaReservaState extends ConsumerState<PantallaReserva> {
  String? _dia;
  int? _horarioId;
  bool _reservando = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final cancha = _cancha();

    return Scaffold(
      appBar: AppBar(title: Text(cancha?.nombre ?? 'Reservar')),
      body: Column(
        children: [
          _DiaPicker(
            canchaId: widget.canchaId,
            dia: _dia,
            onElegirDia: (fecha) => setState(() {
              _dia = fecha;
              _horarioId = null;
            }),
          ),
          Expanded(
            child: ref
                .watch(disponibilidadProvider(widget.canchaId))
                .when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _Aviso(
                    mensaje: mensajeDeError(error),
                    alReintentar: () => ref.invalidate(disponibilidadProvider(widget.canchaId)),
                  ),
                  data: (slots) => _ListaSlots(
                    slots: slots,
                    dia: _dia,
                    seleccionado: _horarioId,
                    alElegir: (slot) => setState(() {
                      _horarioId = slot.horarioId;
                      // El día se toma del slot elegido: así el resumen y la reserva
                      // usan siempre la misma fecha, aunque el usuario no haya tocado la
                      // tira de días.
                      _dia = slot.fecha;
                    }),
                  ),
                ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _Banner(
                texto: _error!,
                icono: Icons.error_outline,
                alCerrar: () => setState(() => _error = null),
              ),
            ),
          _BarraConfirmar(
            texto: _reservando
                ? 'Reservando…'
                : (_horarioId == null ? 'Elige un horario' : 'Reservar'),
            activo: _horarioId != null && !_reservando,
            alConfirmar: _reservando ? null : _confirmar,
          ),
          SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
        ],
      ),
    );
  }

  /// La cancha se toma del catálogo ya cargado: entrar por enlace directo sin venir de la
  /// lista no debe romper la pantalla, sólo se pierde el nombre en la barra.
  Cancha? _cancha() {
    final canchas = ref.read(canchasProvider).value;
    if (canchas == null) return null;
    for (final cancha in canchas) {
      if (cancha.id == widget.canchaId) return cancha;
    }
    return null;
  }

  /// Reserva el slot elegido y abre la hoja de pago.
  Future<void> _confirmar() async {
    final slot = _slot(_horarioId);
    if (slot == null || _reservando) return;

    final dia = slot.fecha;
    final resumen = '${etiquetaFecha(dia)} · ${slot.rango}';

    setState(() {
      _reservando = true;
      _error = null;
    });

    try {
      final creada = await ref
          .read(misReservasProvider.notifier)
          .reservar(canchaId: widget.canchaId, horarioId: slot.horarioId, fecha: dia);
      if (!mounted) return;
      setState(() => _reservando = false);
      _abrirPago(reserva: creada, resumen: resumen, monto: slot.tarifa, cancha: _cancha());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _reservando = false;
        // 409 y 422 son los dos casos en que lo que se veía ya no era la realidad: además
        // del mensaje, se refresca la disponibilidad para que el siguiente intento use
        // datos frescos (HEUR-9).
        _error = mensajeDeError(error);
      });
      if (error is ApiException && (error.esConflicto || error.esReglaNegocio)) {
        ref.invalidate(disponibilidadProvider(widget.canchaId));
      }
    }
  }

  Future<void> _abrirPago({
    required ReservaCreada reserva,
    required String resumen,
    required double monto,
    Cancha? cancha,
  }) async {
    final pagoId = reserva.pago.id;
    final reservaId = reserva.reservaId;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => _DialogoTicket(
        resumen: resumen,
        monto: monto,
        nombreCancha: cancha?.nombre,
        alPagar: () => Navigator.of(context).pop(true),
        alCerrar: () => Navigator.of(context).pop(false),
      ),
    );

    if (confirmado != true || !mounted) return;
    final pagado = await PagoSheet.abrir(
      context,
      pagoId: pagoId,
      reservaId: reservaId,
      resumen: resumen,
    );
    if (!mounted) return;
    if (pagado == true) {
      setState(() => _error = null);
    }
  }

  Slot? _slot(int? horarioId) {
    if (horarioId == null) return null;
    final slots = ref.read(disponibilidadProvider(widget.canchaId)).value;
    if (slots == null) return null;
    for (final slot in slots) {
      if (slot.horarioId == horarioId) return slot;
    }
    return null;
  }
}

/// Tira de días sobre la lista de slots. Se separa del cuerpo para que el provider se
/// pueda observar sin reconstruir los tiles.
class _DiaPicker extends ConsumerWidget {
  const _DiaPicker({required this.canchaId, required this.dia, required this.onElegirDia});

  final int canchaId;
  final String? dia;
  final ValueChanged<String> onElegirDia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(disponibilidadProvider(canchaId)).value;
    if (slots == null) return const SizedBox(height: 16);
    final fechas = diasDe(slots);
    if (fechas.isEmpty) return const SizedBox(height: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text('Elige el día', style: Theme.of(context).textTheme.titleSmall),
        ),
        DiaSelector(
          fechas: fechas,
          seleccionada: dia ?? fechas.first,
          onChanged: onElegirDia,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ListaSlots extends StatelessWidget {
  const _ListaSlots({
    required this.slots,
    required this.dia,
    required this.seleccionado,
    required this.alElegir,
  });

  final List<Slot> slots;
  final String? dia;
  final int? seleccionado;
  final ValueChanged<Slot> alElegir;

  @override
  Widget build(BuildContext context) {
    final fechas = diasDe(slots);
    final diaActual = dia ?? (fechas.isNotEmpty ? fechas.first : null);
    if (diaActual == null) {
      return const _Aviso(
        mensaje: 'Esta cancha todavía no tiene horarios cargados.',
        icono: Icons.event_busy_outlined,
      );
    }

    final delDia = slotsDeDia(slots, diaActual);
    if (delDia.isEmpty) {
      return _Aviso(
        mensaje: 'No hay horarios para ${etiquetaFecha(diaActual)}. Elige otro día.',
        icono: Icons.event_busy_outlined,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: delDia.length,
      itemBuilder: (context, index) {
        final slot = delDia[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SlotTile(
            slot: slot,
            seleccionado: slot.horarioId == seleccionado,
            onSelected: (elegido) => alElegir(elegido),
          ),
        );
      },
    );
  }
}

class _BarraConfirmar extends StatelessWidget {
  const _BarraConfirmar({
    required this.texto,
    required this.activo,
    required this.alConfirmar,
  });

  final String texto;
  final bool activo;
  final VoidCallback? alConfirmar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: FilledButton(
        onPressed: activo ? alConfirmar : null,
        child: Text(texto),
      ),
    );
  }
}

/// Confirmación de la reserva recién creada. Muestra el mismo precio que el backend
/// cobró y da el paso al pago sin salir de la tarea.
class _DialogoTicket extends StatelessWidget {
  const _DialogoTicket({
    required this.resumen,
    required this.monto,
    required this.nombreCancha,
    required this.alPagar,
    required this.alCerrar,
  });

  final String resumen;
  final double monto;
  final String? nombreCancha;
  final VoidCallback alPagar;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Reserva creada'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quedó apartada y falta el pago para confirmarla.'),
          const SizedBox(height: 12),
          if (nombreCancha != null) Text(nombreCancha!, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(resumen),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Total a pagar', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                formatoMonto(monto),
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: alCerrar, child: const Text('Ahora no')),
        FilledButton(onPressed: alPagar, child: const Text('Pagar ahora')),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.texto, required this.icono, required this.alCerrar});

  final String texto;
  final IconData icono;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icono, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: TextStyle(color: scheme.onErrorContainer)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: scheme.onErrorContainer,
            tooltip: 'Cerrar',
            onPressed: alCerrar,
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje, this.alReintentar, this.icono = Icons.cloud_off});

  final String mensaje;
  final VoidCallback? alReintentar;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(icono, size: 48, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text(mensaje, textAlign: TextAlign.center),
        if (alReintentar != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonal(
              onPressed: alReintentar,
              child: const Text('Reintentar'),
            ),
          ),
        ],
      ],
    );
  }
}

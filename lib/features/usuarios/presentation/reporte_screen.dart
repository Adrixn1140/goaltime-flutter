import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/format.dart';
import '../../auth/auth_state.dart' show mensajeDeError;
import '../../cliente/data/models.dart' show EstadoReserva, EstadoReservaX;
import '../../gestion/presentation/widgets/aviso_gestion.dart';
import '../data/models.dart';
import '../state/admin_provider.dart';

/// Reporte agregado (`GET /api/reporte`).
///
/// El backend ya mandó los agregados, así que la app no trae reservas a sumar: dibuja lo
/// que le llega. Tres bloques en el orden en que se responde una pregunta de negocio —
/// cuánto entró, cuántas reservas hubo, cuánta gente hay— y la gráfica de barras la hace
/// un `CustomPaint` en vez de una librería: son cinco barras, y meter una dependencia
/// para eso sería más riesgo de versiones que código (HEUR-8).
class ReporteScreen extends ConsumerWidget {
  const ReporteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reporte = ref.watch(reporteProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reporte')),
      body: RefreshIndicator(
        // Se espera al `future` del provider para que "deslizar para actualizar" no
        // quite el indicador antes de tener los datos nuevos.
        onRefresh: () => ref.refresh(reporteProvider.future),
        child: reporte.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AvisoGestion(
            icono: Icons.cloud_off,
            mensaje: mensajeDeError(error),
            accion: FilledButton.tonal(
              onPressed: () => ref.invalidate(reporteProvider),
              child: const Text('Reintentar'),
            ),
          ),
          data: (datos) => _Cuerpo(reporte: datos),
        ),
      ),
    );
  }
}

class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.reporte});

  final ReporteAdmin reporte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sinActividad = reporte.ingresosTotal == 0 && reporte.reservasTotal == 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: _Metrica(
                etiqueta: 'Ingresos cobrados',
                valor: formatoMonto(reporte.ingresosTotal),
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metrica(
                etiqueta: 'Reservas',
                valor: '${reporte.reservasTotal}',
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metrica(
                etiqueta: 'Usuarios',
                valor: '${reporte.usuariosTotal}',
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
        ),
        if (sinActividad) ...[
          const SizedBox(height: 24),
          Text(
            'Todavía no hay reservas cobradas.\nEl reporte se llena solo en cuanto entre '
            'el primer pago aprobado.',
            style: theme.textTheme.bodyLarge,
          ),
        ],
        if (reporte.ingresosPorCancha.isNotEmpty) ...[
          const SizedBox(height: 32),
          _Titulo('Ingresos por cancha'),
          const SizedBox(height: 12),
          _Barras(
            barras: reporte.ingresosPorCancha
                .map((c) => _Barra(etiqueta: c.nombre, valor: c.monto, pie: '${c.reservas} res.'))
                .toList(growable: false),
            formato: formatoMonto,
          ),
        ],
        if (reporte.ingresosPorDia.isNotEmpty) ...[
          const SizedBox(height: 32),
          _Titulo('Ingresos por día'),
          const SizedBox(height: 12),
          _Barras(
            barras: reporte.ingresosPorDia
                .map(
                  (d) => _Barra(
                    etiqueta: _diaCorto(d.fecha),
                    valor: d.monto,
                    pie: '${d.reservas} res.',
                  ),
                )
                .toList(growable: false),
            formato: formatoMonto,
          ),
        ],
        if (reporte.reservasPorEstado.isNotEmpty) ...[
          const SizedBox(height: 32),
          _Titulo('Reservas por estado'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final estado in reporte.estadosPresentes)
                Chip(
                  avatar: Icon(_iconoDe(estado), size: 18),
                  label: Text('${estado.etiqueta}: ${reporte.reservasDe(estado)}'),
                ),
              if (reporte.usuariosInactivos > 0)
                const Chip(
                  avatar: Icon(Icons.person_off_outlined, size: 18),
                  label: Text('Cuentas desactivadas'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 32),
        // Si el desglose no suma el total, la gráfica está mintiendo y hay que decirlo en
        // vez de dejarla pasar: el backend lo garantiza y aquí se avisa si algún día no.
        if (!reporte.desgloseCuadra)
          Text(
            'Atención: el desglose por cancha no suma el total de ingresos.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        Text(
          'Actualizado: ${_actualizado(reporte.generadoEn)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

IconData _iconoDe(EstadoReserva estado) => switch (estado) {
  EstadoReserva.pendientePago => Icons.schedule,
  EstadoReserva.confirmada => Icons.check_circle_outline,
  EstadoReserva.cancelada => Icons.cancel_outlined,
};

/// `2026-09-20T14:03:11+00:00` → `20 sep`. Si el backend no manda hora, se devuelve tal
/// cual: un `—` silencioso sería peor que una fecha cruda.
String _actualizado(String iso) {
  if (iso.length < 10) return iso;
  return etiquetaDiaCorto(DateTime.parse(iso).toLocal());
}

/// La etiqueta del día sale de `format.dart` y no de una lista de mesescopiada aquí: dos
/// tablas de abreviaturas son dos tablas que un día se contradicen.
String _diaCorto(String iso) {
  final fecha = parseFechaIso(iso);
  return fecha == null ? iso : etiquetaDiaCorto(fecha);
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) =>
      Text(texto, style: Theme.of(context).textTheme.titleMedium);
}

class _Metrica extends StatelessWidget {
  const _Metrica({required this.etiqueta, required this.valor, required this.color});

  final String etiqueta;
  final String valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            // El color de la cifra va con el título de arriba, pero el número es texto
            // grande y no sólo una barra: se lee de un vistazo (HEUR-1).
            Text(
              valor,
              style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _Barra {
  const _Barra({required this.etiqueta, required this.valor, required this.pie});

  final String etiqueta;
  final double valor;
  final String pie;
}

/// Barras horizontales dibujadas a mano, con la etiqueta a la izquierda y el valor a la
/// derecha. La barra es la comparación y el número es la lectura exacta: una gráfica sin
/// cifras obliga al admin a estimar a ojo cuánto entró en cada cancha (HEUR-1).
class _Barras extends StatelessWidget {
  const _Barras({required this.barras, required this.formato});

  final List<_Barra> barras;
  final String Function(double) formato;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximo = barras.fold<double>(0, (m, b) => math.max(m, b.valor));

    return Column(
      children: [
        for (final barra in barras)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Text(barra.etiqueta, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CustomPaint(
                      painter: _BarraPainter(
                        fraccion: maximo == 0 ? 0 : barra.valor / maximo,
                        color: theme.colorScheme.primary,
                        fondo: theme.colorScheme.surfaceContainerHighest,
                      ),
                      child: const SizedBox(height: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: Text(
                    '${formato(barra.valor)} · ${barra.pie}',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarraPainter extends CustomPainter {
  const _BarraPainter({required this.fraccion, required this.color, required this.fondo});

  final double fraccion;
  final Color color;
  final Color fondo;

  @override
  void paint(Canvas canvas, Size size) {
    final alto = size.height;
    final pinturaFondo = Paint()..color = fondo;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, alto), pinturaFondo);

    if (fraccion <= 0) return;
    // Mínimo un par de píxeles: un valor de 0 frente a uno de 1 se verían igual de vacíos
    // sin esto, y el admin concluiría que no reservar.
    final ancho = math.max(2.0, size.width * fraccion.clamp(0.0, 1.0));
    canvas.drawRect(Rect.fromLTWH(0, 0, ancho, alto), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BarraPainter anterior) =>
      anterior.fraccion != fraccion || anterior.color != color || anterior.fondo != fondo;
}

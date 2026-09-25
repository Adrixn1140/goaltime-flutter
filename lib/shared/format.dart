/// Formateo para la interfaz: pesos colombianos y fechas en español.
///
/// Se hace a mano en vez de con `intl` porque `DateFormat` exige inicializar los símbolos
/// de cada locale (`initializeDateFormatting`) y esa inicialización es asíncrona: con
/// una lista constante el resultado es determinista y testeable sin más ceremonia.
library;

const List<String> _dias = [
  'lun',
  'mar',
  'mié',
  'jue',
  'vie',
  'sáb',
  'dom',
];

const List<String> _diasLargos = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

const List<String> _meses = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

const List<String> _mesesLargos = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Monto en pesos: `$ 60.000` (punto de miles, sin decimales cuando es redondo).
///
/// El backend manda `tarifa` y `monto` como número; el formato cop es el que espera el
/// usuario colombiano y evita que el precio se lea como si fuera dólares.
String formatoMonto(num? valor) {
  if (valor == null) return '—';
  final negativo = valor < 0;
  final entero = valor.abs().round();
  final miles = entero.toString();
  final conSeparadores = StringBuffer();
  for (var i = 0; i < miles.length; i++) {
    if (i > 0 && (miles.length - i) % 3 == 0) conSeparadores.write('.');
    conSeparadores.write(miles[i]);
  }
  return '${negativo ? '-' : ''}\$ $conSeparadores';
}

/// `DateTime` → `DateTime` a medianoche local, para no sumar horas al comparar fechas.
DateTime soloFecha(DateTime fecha) => DateTime(fecha.year, fecha.month, fecha.day);

/// Etiqueta corta de día: `vie 25 sep`.
String etiquetaDiaCorto(DateTime fecha) =>
    '${_dias[fecha.weekday - 1]} ${fecha.day} ${_meses[fecha.month - 1]}';

/// Etiqueta larga: `Viernes 25 de septiembre`.
String etiquetaDiaLargo(DateTime fecha) =>
    '${_diasLargos[fecha.weekday - 1]} ${fecha.day} de ${_mesesLargos[fecha.month - 1]}';

/// Convierte `YYYY-MM-DD` en [DateTime] local. Devuelve `null` si no parsea.
DateTime? parseFechaIso(String? iso) {
  if (iso == null) return null;
  final partes = iso.split('-');
  if (partes.length != 3) return null;
  final anio = int.tryParse(partes[0]);
  final mes = int.tryParse(partes[1]);
  final dia = int.tryParse(partes[2]);
  if (anio == null || mes == null || dia == null) return null;
  return DateTime(anio, mes, dia);
}

/// "Hoy", "Mañana" o la fecha corta, para no obligar a leer el calendario.
String etiquetaFecha(String iso) {
  final fecha = parseFechaIso(iso);
  if (fecha == null) return iso;
  final hoy = soloFecha(DateTime.now());
  final dias = fecha.difference(hoy).inDays;
  if (dias == 0) return 'Hoy';
  if (dias == 1) return 'Mañana';
  return etiquetaDiaCorto(fecha);
}

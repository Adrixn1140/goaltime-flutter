/// Desactiva el reintento automático de Riverpod para los providers de red del cliente.
///
/// Por defecto Riverpod reintenta un provider que falla con espera exponencial. En este
/// caso eso es lo contrario de lo que pide la interfaz: el usuario vería un spinner
/// durante varios segundos en vez de un mensaje con el motivo y un botón "Reintentar"
/// (HEUR-1, HEUR-9). Además, un reintento automático sobre `POST /api/reservas` podría
/// volver a intentar una reserva que el backend sí llegó a crear.
///
/// Devolver `null` cancela el reintento; el que reintenta es el usuario.
Duration? sinReintento(int intento, Object error) => null;

/// Desactiva el reintento automático de Riverpod para los providers de red.
///
/// Por defecto Riverpod reintenta un provider que falla con espera exponencial. En este
/// caso eso es lo contrario de lo que pide la interfaz: el usuario vería un spinner
/// durante varios segundos en vez de un mensaje con el motivo y un botón "Reintentar"
/// (HEUR-1, HEUR-9). Además, un reintento automático sobre un `POST` —una reserva, un
/// horario nuevo— podría volver a intentar algo que el backend sí llegó a crear.
///
/// Vive en `core` y no en un módulo porque es política de la app, no del cliente: lo usan
/// igual los providers de reservas y los de gestión del dueño.
///
/// Devolver `null` cancela el reintento; el que reintenta es el usuario.
Duration? sinReintento(int intento, Object error) => null;

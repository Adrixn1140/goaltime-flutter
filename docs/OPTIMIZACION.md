# Optimización mínima — 6 de noviembre de 2026

## Catálogo de canchas

- Las actualizaciones simultáneas comparten una misma petición HTTP. Por ejemplo,
  varias llamadas a actualizar durante una descarga ya iniciada no vuelven a consultar
  el backend: esperan el mismo resultado.
- El botón Actualizar se desactiva mientras carga el catálogo.
- Una petición fallida libera el bloqueo y permite reintentar.
- Las respuestas de una actualización anterior se descartan si el catálogo se invalida
  o el provider se cierra, para no sobrescribir el estado nuevo.

Es una reducción de trabajo redundante, no una caché nueva ni un modo sin conexión.
No cambia reservas, pagos, equipos, árbitros ni la dirección del servidor. Tampoco
resuelve un backend apagado o la pérdida del enlace USB.

## Pruebas

`test/canchas_provider_test.dart` comprueba concurrencia, recuperación tras error y
descarte de respuestas antiguas. El contador verifica una petición para varias
actualizaciones simultáneas, además de la carga inicial. No se atribuye una mejora
porcentual de velocidad sin medir el rendimiento en un dispositivo.

Verificación local: `flutter analyze` sin incidencias y 9 pruebas aprobadas al ejecutar
`flutter test test/canchas_provider_test.dart test/reserva_flow_test.dart`.

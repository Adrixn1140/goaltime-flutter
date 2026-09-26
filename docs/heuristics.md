# GoalTime — Evaluación Heurística (Nielsen) y Guía de Diseño

> Las 10 heurísticas de Nielsen (1994). Este documento tiene dos partes:
> **1)** evaluación del sistema original que ya no está disponible, **2)** guía de diseño
> de la app Flutter, donde cada pantalla es trazable a una o más heurísticas.
>
> La evaluación de la Parte 1 se conserva como **línea base histórica** del proyecto:
> documenta los problemas de diseño que había que corregir, y varios de ellos nacieron
> justamente de la falta de feedback y de validación en el backend.

## Parte 1 — Evaluación del sistema original (web GoalTime, no disponible)

| # | Heurística | Problema detectado | Gravedad |
|---|---|---|---|
| 1 | Visibilidad del estado del sistema | No hay feedback durante el POST /api/reservas (sin spinner/interceptor de estado) | Media |
| 2 | Coincidencia sistema-mundo real | Errores mostrados como texto técnico plano, no en lenguaje del usuario | Baja |
| 3 | Control y libertad del usuario | No hay cancelación de reservas desde el cliente | Alta |
| 4 | Consistencia y estándares | Máxima/minúsculas inconsistentes y confirmaciones irregulares entre pantallas | Media |
| 5 | Prevención de errores | Se puede reservar sobre un slot que otro ya pidió (sin bloqueo/rebote visible hasta el 409) | Alta |
| 6 | Reconocer antes que recordar | El panel no indica al usuario qué puede hacer según su rol | Media |
| 7 | Flexibilidad y eficiencia | Sin atajos ni persistencia de selección (re-tipear la cancha cada vez) | Baja |
| 8 | Diseño estético y minimalista | Hay información redundante; jerarquía visual débil | Baja |
| 9 | Ayuda a recuperarse de errores | Los mensajes de error no sugieren siguiente paso | Media |
| 10 | Ayuda y documentación | Sin ayuda en contexto ni aclaración de la regla de reserva | Baja |

## Parte 2 — Guía de diseño de la app Flutter

| Pantalla | Heurísticas aplicadas | Decisión de diseño |
|---|---|---|
| **Splash / Login / Registro** | 1 Visibilidad de estado · 2 Coincidencia | Indicador de progreso en submit; mensajes en español claros; validación inline en campos |
| **Catálogo de canchas** | 6 Reconocer > recordar · 4 Consistencia | Cards uniformes con nombre/foto/precio base; estado vacío claro; filtros visibles |
| **Disponibilidad (6 días)** | 1 Estado · 5 Prevención · 8 Minimalista | Vista por día tipo calendario; slots ocupados deshabilitados con rojo y tooltip "ocupado" |
| **Reserva + Checkout** | 5 Prevención · 7 Flexibilidad | Paso de confirmación con resumen (cancha/fecha/hora/tarifa); botón destacado; se conserva la selección al volver |
| **Pago (Stripe)** | 1 Estado · 9 Recuperación | Estado del pago mostrado (pendiente/aprobado/rechazado); reintento cuando la reserva vuelve a `pendiente_pago` |
| **Mis reservas** | 3 Control y libertad · 9 Recuperación | Lista con estados visibles; acciones claras (ver ticket, cancelar con confirmación) |
| **Panel Dueño (CRUD canchas/horarios)** | 4 Consistencia · 5 Prevención · 3 Control | Formularios coherentes; validación de solapamiento de horarios; confirmaciones en borrado |
| **Panel Admin (usuarios/reporte)** | 6 Reconocer · 1 Estado | Tabla de usuarios con filtros; gráficas con loading y estados vacíos |

### Trazabilidad de la Sesión 4 (módulo Cliente, ya implementado)

Decisiones que no aparecen en la tabla anterior porque se tomaron al escribir el código:

| Decisión | Heurística | Dónde vive |
|---|---|---|
| Pantalla de bienvenida mientras se lee la sesión guardada; sin ella, cada arranque expulsaba al usuario al login | 1 Visibilidad de estado | `core/routing/splash_screen.dart`, `AuthState.restaurando` |
| El precio se muestra antes de confirmar y lo calcula el backend; la app nunca envía monto | 5 Prevención de errores | `_DialogoTicket` en `cliente/presentation/reserva_screen.dart` |
| Un `409` muestra el mensaje del backend **y** refresca la disponibilidad en el mismo momento | 9 Recuperación de errores | `reserva_screen.dart:_confirmar` |
| Los slots no disponibles se muestran tachados con su motivo ("Ocupado", "Ya pasó") en vez de desaparecer | 5 Prevención de errores | `widgets/slot_tile.dart` |
| Tira horizontal de 6 días con el día escrito, sin obligar a abrir un calendario | 7 Flexibilidad y eficiencia | `widgets/dia_selector.dart` |
| La ficha de la reserva pendiente ofrece pagar/reintentar sin repetir el flujo de reserva | 9 Recuperación de errores | `mis_reservas_screen.dart` |
| Cierre de sesión con confirmación y borrado de toda la sesión local (token, rol, nombre, correo) | 3 Control y libertad | `perfil_screen.dart`, `TokenStorage.clear` |
| El estado siempre se acompaña de texto, nunca sólo de color | 4 Consistencia y estándares | `widgets/estado_chip.dart` |
| Reintento de red **manual**: el error trae la siguiente acción, no un spinner que se prolonga solo | 1 Visibilidad · 9 Recuperación | `cliente/state/retry.dart` |
| Si el navegador no abre el checkout, se ofrece copiar el enlace | 9 Recuperación de errores | `pago_sheet.dart:_abrirExterno` |
| Un `401` con token cierra la sesión y avisa; un `401` en el login no, porque ahí el error se explica | 1 Visibilidad · 3 Control y libertad | `core/network/auth_interceptor.dart`, `AuthNotifier._cerrarSesionPorExpiracion` |

### Trazabilidad de la Sesión 5 (Dueño)

| Decisión | Heurística | Dónde vive |
|---|---|---|
| Gestión en `/api/gestion/*` y no sobre `/api/canchas`: el catálogo público no debe cambiar de forma según quién pregunte | 4 Consistencia y estándares | `backend/blueprints/gestion.py`, `spec.md 3.4` |
| La cancha de otro dueño responde `404` y el rol insuficiente `403`: un `403` confirmaría que el id existe | 5 Prevención de errores | `gestion.py:_no_existe_o_no_es_tuya` |
| El `dueno_id` sale del token y el del cuerpo se ignora | 5 Prevención de errores | `gestion.py:crear_cancha` |
| Canchas y horarios se dan de baja, nunca se borran: el histórico manda y las FK son `RESTRICT` | 4 Consistencia | `gestion.py:bajar_cancha` |
| Un horario con reservas no se borra ni se mueve, canceladas incluidas; la tarifa sí se cambia, porque el precio de una reserva ya cerrada está en su pago | 4 Consistencia · 5 Prevención | `gestion.py:_tiene_reservas` |
| Horario duplicado (`409`) y horario solapado (`422`) son mensajes distintos: son dos hechos distintos | 9 Recuperación de errores | `gestion.py:_existe_exacto`, `_solapa` |
| Confirmar exige pago aprobado: el botón no está, el estado del sistema es el que habilita la acción | 1 Visibilidad de estado | `gestion.py:cambiar_estado_reserva` |
| La lista de reservas dice quién reservó, pero no su correo: el dato que el dueño necesita no es el dato que el contrato expone | 5 Prevención de errores | `models.py:Reserva.to_dict_gestion` |
| Un `409`/`422` se muestra con el mensaje del backend y sin dejar la pantalla a medias: el dueño decide qué hacer, no adivina | 9 Recuperación de errores | `api_exception.dart` (sugerencias genéricas por rol), `gestion_repository.dart` |
| "Confirmar" sólo aparece con pago aprobado y reserva pendiente, y el motivo de la ausencia se explica | 1 Visibilidad de estado | `models.dart:ReservaGestion.puedeConfirmar` / `motivoSinConfirmar` |
| Toda acción destructiva (baja de cancha, borrado de horario, cancelación) pide confirmación diciendo qué se conserva | 5 Prevención de errores · 3 Control y libertad | `aviso_gestion.dart` (reutilizado en los tres diálogos) |
| Las hojas de acciones y los formularios se desplazan: en una pantalla baja con el teclado abierto nada queda inaccesible | 8 Estética y minimalista · 7 Flexibilidad | `gestion_canchas_screen.dart:_HojaAcciones`, `form_cancha_sheet.dart`, `form_horario_sheet.dart` |
| El día de la semana se traduce con una tabla explícita (0 = lunes) en vez de confiar en el `weekday` de Dart | 5 Prevención de errores | `format.dart:etiquetaDiaSemana` + `format_test.dart` (confrontado con `DateTime.weekday`) |
| La pantalla de detalle pide el nombre de la cancha al provider, no lo vuelve a pedir al backend | 7 Flexibilidad y eficiencia | `horarios_screen.dart:nombreCancha` |

## Parte 3 — Mapeo código ↔ heurística

En el código se añaden referencias ligeras para trazabilidad:
`// HEUR-1: spinner al hacer submit (visibilidad del estado del sistema)`

Convención de anotación:
- `HEUR-1` Visibilidad del estado
- `HEUR-2` Coincidencia sistema-mundo
- `HEUR-3` Control y libertad del usuario
- `HEUR-4` Consistencia y estándares
- `HEUR-5` Prevención de errores
- `HEUR-6` Reconocer antes que recordar
- `HEUR-7` Flexibilidad y eficiencia de uso
- `HEUR-8` Diseño estético y minimalista
- `HEUR-9` Ayudar a los usuarios a reconocer, diagnosticar y recuperarse de errores
- `HEUR-10` Ayuda y documentación
# GoalTime — Evaluación Heurística (Nielsen) y Guía de Diseño

> Las 10 heurísticas de Nielsen (1994). Este documento tiene dos partes:
> **1)** evaluación del sistema actual (web HTML/JS), **2)** guía de diseño de la app Flutter,
> donde cada pantalla es trazable a una o más heurísticas.

## Parte 1 — Evaluación del sistema actual (web GoalTime)

| # | Heurística | Problema detectado | Gravedad |
|---|---|---|---|
| 1 | Visibilidad del estado del sistema | No hay feedback durante el POST /api/reservar (sin spinner/interceptor de estado) | Media |
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
| **Pago** | 1 Estado · 9 Recuperación | Estado del pago mostrado (pendiente/aprobado/rechazado); opción de reintentar |
| **Mis reservas** | 3 Control y libertad · 9 Recuperación | Lista con estados visibles; acciones claras (ver ticket, cancelar con confirmación) |
| **Panel Dueño (CRUD canchas/horarios)** | 4 Consistencia · 5 Prevención · 3 Control | Formularios coherentes; validación de solapamiento de horarios; confirmaciones en borrado |
| **Panel Admin (usuarios/reporte)** | 6 Reconocer · 1 Estado | Tabla de usuarios con filtros; gráficas con loading y estados vacíos |

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
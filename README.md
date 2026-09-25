# GoalTime — App Flutter (Android/iOS)

Sistema de **reservas de canchas sintéticas** (Riohacha, Colombia).
App móvil Flutter que consume la **API Flask** existente. Proyecto de asignatura de
**desarrollo móvil**.

**Multi-rol**: `Cliente` (reservar), `Dueño` (gestiona sus canchas) y `Admin` (gestión global).

## Stack

| Capa | Tecnología |
|---|---|
| App | Flutter (Android/iOS) — Material 3 |
| Estado | Riverpod |
| Navegación | go_router (shells por rol) |
| Red | dio + interceptor JWT |
| Backend (existe) | Flask + SQLAlchemy + PostgreSQL |
| Async de pago | Stripe (checkout + webhook, pendiente backend) |

## Documentación (entregables del curso)

- [`docs/spec.md`](docs/spec.md) — Especificación *spec-driven*: contrato de API v1 + criterios de aceptación
- [`docs/heuristics.md`](docs/heuristics.md) — Evaluación heurística (Nielsen) + guía de diseño trazable

## Estructura

```
lib/
  core/     dio client + interceptor, tema M3, router, storage seguro
  features/ auth · canchas · reservas · pago · gestion (dueño) · usuarios (admin)
  shared/   widgets, extensiones, utilidades
```

## Estado del proyecto

- [x] Repo + scaffolding Flutter (Android/iOS)
- [x] Spec API v1 (contract-first) y evaluación heurística
- [ ] Autenticación (JWT) — requiere añadir endpoint al backend
- [ ] Módulo Cliente (canchas, disponibilidad, reserva, mis reservas)
- [ ] Módulo Dueño (CRUD canchas/horarios, reservas propias)
- [ ] Módulo Admin (usuarios, reporte)
- [ ] Pago por pasarela (Stripe) — pendiente de backend

> La especificación de endpoints se validará contra el código Flask real cuando esté disponible.

## Ejecutar

```sh
flutter pub get
flutter run
```
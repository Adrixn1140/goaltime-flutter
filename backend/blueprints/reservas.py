"""Reservas del cliente (spec.md 3.2).

Dos invariantes sostienen este módulo:

1. **Atomicidad**: la reserva y su pago se crean en una sola transacción. Si el pago no
   puede insertarse, la reserva tampoco se persiste; nunca queda una reserva sin pago.
2. **El monto lo decide el backend**: sale de `horario.tarifa`, nunca del cuerpo. El
   `409` del slot ocupado no se comprueba con un `SELECT`: se intenta el `INSERT` y el
   índice UNIQUE parcial `uq_reserva_slot_fecha` es el árbitro, de modo que dos
   peticiones simultáneas no puedan colarse entre la comprobación y la escritura.
"""

from flask import Blueprint, g, jsonify, request
from sqlalchemy.exc import IntegrityError

from auth_helpers import con_rol
from dominio.disponibilidad import parse_fecha, slot_vencido
from errors import error_response
from extensions import db
from models import (
    ESTADO_CANCELADA,
    ESTADO_PENDIENTE_PAGO,
    PAGO_PENDIENTE,
    ROL_CLIENTE,
    Cancha,
    Horario,
    Pago,
    Reserva,
)
from pasarelas import obtener_pasarela

bp = Blueprint("reservas", __name__)


@bp.post("/reservas")
@con_rol()
def crear_reserva():
    """Reserva el slot y deja la reserva `pendiente_pago` con su pago `pendiente`."""
    # `con_rol()` sin roles a propósito: filtra la sesión (incluida la cuenta desactivada)
    # y el filtro por rol se hace aquí para poder decir *por qué* en el 403. Si el rol
    # fuera al decorador, el `403` sería el genérico y se perdería el motivo.
    cliente = g.usuario
    if cliente.rol != ROL_CLIENTE:
        return error_response(403, "Sólo los clientes pueden reservar canchas")

    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return error_response(400, "El cuerpo debe ser JSON con los campos requeridos")
    try:
        cancha_id = int(datos["cancha_id"])
        horario_id = int(datos["horario_id"])
    except (KeyError, TypeError, ValueError):
        return error_response(400, "cancha_id, horario_id y fecha son obligatorios")

    fecha = parse_fecha(datos.get("fecha"))
    if fecha is None:
        return error_response(400, "fecha debe tener el formato YYYY-MM-DD")

    cancha = db.session.get(Cancha, cancha_id)
    if cancha is None or not cancha.activo:
        return error_response(404, "La cancha solicitada no existe")
    horario = db.session.get(Horario, horario_id)
    if horario is None:
        return error_response(404, "El horario no existe")
    if horario.cancha_id != cancha.id:
        return error_response(422, "El horario no pertenece a la cancha indicada")
    if horario.dia != fecha.weekday():
        return error_response(422, "La cancha no tiene horario disponible ese día")
    # Misma regla que `/api/disponibilidad` marca como `transcurrido`: la app puede
    # deshabilitar el slot antes, pero el backend no confía en que lo haga.
    if slot_vencido(fecha, horario.hora_inicio):
        return error_response(422, "Ese horario ya no está disponible")

    reserva = Reserva(
        cliente_id=cliente.id,
        cancha_id=cancha.id,
        horario_id=horario.id,
        fecha=fecha,
        estado=ESTADO_PENDIENTE_PAGO,
    )
    db.session.add(reserva)
    try:
        # El INSERT de la reserva ocurre aquí, y es también aquí donde el índice
        # `uq_reserva_slot_fecha` rechaza el slot ocupado: por eso el `try` empieza
        # antes del flush y no sólo alrededor del commit.
        db.session.flush()
        pago = Pago(
            reserva_id=reserva.id,
            monto=horario.tarifa,
            metodo=obtener_pasarela().metodo,
            estado=PAGO_PENDIENTE,
        )
        db.session.add(pago)
        db.session.commit()
    except IntegrityError:
        # El rollback deshace reserva y pago a la vez: nunca queda una reserva sin pago.
        db.session.rollback()
        if _slot_ocupado(cancha.id, horario.id, fecha):
            return error_response(409, "Ese horario ya está reservado para esa fecha")
        # Otra restricción (pago duplicado, referencia corrida): no es un conflicto de
        # disponibilidad, así que no se disfraza de 409.
        return error_response(500, "No fue posible registrar la reserva, inténtalo de nuevo")

    return (
        jsonify(
            {
                "reserva_id": reserva.id,
                "estado": reserva.estado,
                "pago": {
                    "id": pago.id,
                    "monto": float(pago.monto),
                    "metodo": pago.metodo,
                    "estado": pago.estado,
                },
            }
        ),
        201,
    )


def _slot_ocupado(cancha_id, horario_id, fecha):
    """¿Existe una reserva viva para este slot? Sólo se consulta tras un `IntegrityError`."""
    return (
        db.session.execute(
            db.select(db.func.count(Reserva.id)).where(
                Reserva.cancha_id == cancha_id,
                Reserva.horario_id == horario_id,
                Reserva.fecha == fecha,
                Reserva.estado != ESTADO_CANCELADA,
            )
        ).scalar_one()
        > 0
    )


@bp.get("/mis-reservas")
@con_rol()
def mis_reservas():
    """Reservas del cliente autenticado, de la más reciente a la más antigua.

    El filtro es siempre `cliente_id = identidad del token`: el cliente nunca puede
    pedir las reservas de otro ni pasarlo por parámetro.
    """
    cliente = g.usuario
    if cliente.rol != ROL_CLIENTE:
        return error_response(403, "Este recurso es sólo para clientes")

    reservas = db.session.execute(
        db.select(Reserva)
        .where(Reserva.cliente_id == cliente.id)
        .order_by(Reserva.fecha.desc(), Reserva.id.desc())
    ).scalars().all()

    return jsonify([reserva.to_dict() for reserva in reservas])

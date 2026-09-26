"""Disponibilidad de slots (spec.md 3.2).

Entrega los slots de los 6 días siguientes a `fecha_inicio` y explica por qué un slot
no es seleccionable (`motivo`), para que la app pueda deshabilitarlo con un mensaje
en lugar de dejar que el usuario descubra el `409` o `422` al reservar (HEUR-5).

`parse_fecha` y `slot_vencido` se reutilizan en la Sesión 3 (`POST /api/reservas`):
el endpoint de reserva aplica exactamente la misma regla. `parse_hora` se reutiliza en la
Sesión 5, cuando el dueño define sus propios horarios (§3.4).
"""

import re
from datetime import date, datetime, timedelta

from flask import Blueprint, jsonify, request

from errors import error_response
from extensions import db
from models import ESTADO_CANCELADA, Cancha, Horario, Reserva

bp = Blueprint("disponibilidad", __name__)

DIAS_VENTANA = 6
FORMATO_FECHA = "%Y-%m-%d"
FORMATO_HORA = "%H:%M"
PATRON_FECHA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
PATRON_HORA = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")

MOTIVO_OCUPADO = "ocupado"
MOTIVO_TRANSCURRIDO = "transcurrido"


def parse_fecha(texto):
    """Devuelve `date` o `None` si el texto no es una fecha ISO válida.

    El formato es estricto (`YYYY-MM-DD`): `strptime` por sí solo acepta `2026-9-4`
    y la app debe poder fiarse de que receives siempre el mismo formato.
    """
    if not isinstance(texto, str) or not PATRON_FECHA.match(texto):
        return None
    try:
        return datetime.strptime(texto, FORMATO_FECHA).date()
    except ValueError:
        return None


def slot_vencido(fecha, hora_inicio, ahora=None):
    """True si el slot ya no es seleccionable por hora: fecha pasada, o la hora de
    inicio del día en curso ya pasó."""
    ahora = ahora or datetime.now()
    if fecha < ahora.date():
        return True
    return fecha == ahora.date() and hora_inicio <= ahora.time()


def parse_hora(texto):
    """Devuelve un `time` o `None` si el texto no es una hora `HH:MM` válida.

    Comparte la forma estricta de `parse_fecha` porque la usa la gestión del dueño
    (§3.4): un `int` como `8` o un `8:00` se rechazarían en la base pero pasarían un
    `strptime` mal usado, y el dueño vería el error a la hora de reservar, no al crear
    el horario.
    """
    if not isinstance(texto, str) or not PATRON_HORA.match(texto):
        return None
    try:
        return datetime.strptime(texto, FORMATO_HORA).time()
    except ValueError:
        return None


def _slot(horario, fecha, disponible, motivo):
    return {
        "horario_id": horario.id,
        "fecha": fecha.isoformat(),
        "hora_inicio": horario.hora_inicio.strftime("%H:%M"),
        "hora_fin": horario.hora_fin.strftime("%H:%M"),
        "tarifa": float(horario.tarifa),
        "disponible": disponible,
        "motivo": motivo,
    }


@bp.get("/disponibilidad")
def disponibilidad():
    crudo_cancha = request.args.get("cancha_id")
    crudo_fecha = request.args.get("fecha_inicio")

    if crudo_cancha is None or crudo_fecha is None:
        return error_response(400, "Se requieren los parámetros cancha_id y fecha_inicio")
    try:
        cancha_id = int(crudo_cancha)
    except (TypeError, ValueError):
        return error_response(400, "cancha_id debe ser un número entero")

    fecha_inicio = parse_fecha(crudo_fecha)
    if fecha_inicio is None:
        return error_response(400, "fecha_inicio debe tener el formato YYYY-MM-DD")

    cancha = db.session.get(Cancha, cancha_id)
    if cancha is None or not cancha.activo:
        return error_response(404, "La cancha solicitada no existe")

    fechas = [fecha_inicio + timedelta(days=dias) for dias in range(DIAS_VENTANA)]

    horarios = db.session.execute(
        db.select(Horario)
        .where(Horario.cancha_id == cancha.id, Horario.dia.in_({f.weekday() for f in fechas}))
        .order_by(Horario.hora_inicio)
    ).scalars().all()

    if not horarios:
        return jsonify([])

    # Una reserva cancelada libera el slot, así que no cuenta como ocupada.
    ocupados = {
        (horario_id, fecha)
        for horario_id, fecha in db.session.execute(
            db.select(Reserva.horario_id, Reserva.fecha).where(
                Reserva.cancha_id == cancha.id,
                Reserva.fecha.in_(fechas),
                Reserva.estado != ESTADO_CANCELADA,
            )
        ).all()
    }

    ahora = datetime.now()
    slots = []
    for fecha in fechas:
        for horario in horarios:
            if horario.dia != fecha.weekday():
                continue
            if (horario.id, fecha) in ocupados:
                slots.append(_slot(horario, fecha, False, MOTIVO_OCUPADO))
            elif slot_vencido(fecha, horario.hora_inicio, ahora):
                slots.append(_slot(horario, fecha, False, MOTIVO_TRANSCURRIDO))
            else:
                slots.append(_slot(horario, fecha, True, None))

    return jsonify(slots)

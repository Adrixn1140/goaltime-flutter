"""Disponibilidad de slots (spec.md 3.2).

Blueprint delgado: la regla vive en [`dominio.disponibilidad`](../dominio/disponibilidad.py).
Aquí sólo se traduce HTTP, y lo que queda es el trabajo que el dominio no debe hacer —
saber qué parámetro falta, si es un número, y qué código va en la respuesta.

El módulo **no** reexporta `parse_fecha`, `slot_vencido` ni los motivos: antes lo hacía, y
lo hacía porque `reservas.py` y `gestion.py` los tomaban de aquí para usar reglas que no
tienen nada de HTTP. Esas reglas viven ahora en el dominio, y esos dos módulos las importan
de allí. Reexportarlas otra vez dejaría viva la puerta por la que se coló esa dependencia.
"""

from flask import Blueprint, jsonify, request

from dominio.disponibilidad import calcular_slots, parse_fecha, resolver_cancha_por_id
from errors import error_response

bp = Blueprint("disponibilidad", __name__)


@bp.get("/disponibilidad")
def disponibilidad():
    crudo_cancha = request.args.get("cancha_id")
    crudo_fecha = request.args.get("fecha_inicio")

    if crudo_cancha is None or crudo_fecha is None:
        return error_response(400, "Se requieren los parámetros cancha_id y fecha_inicio")

    # El `int()` va aquí y no en el resolutor a propósito: distinguir "esto no es un
    # número" de "este número no existe" es un `400` contra un `404`, y es una distinción
    # de HTTP, no de disponibilidad. `resolver_cancha_por_id` devuelve `None` para los dos
    # casos porque para el dominio son lo mismo, y porque el asistente también lo usa.
    try:
        cancha_id = int(crudo_cancha)
    except (TypeError, ValueError):
        return error_response(400, "cancha_id debe ser un número entero")

    fecha_inicio = parse_fecha(crudo_fecha)
    if fecha_inicio is None:
        return error_response(400, "fecha_inicio debe tener el formato YYYY-MM-DD")

    cancha = resolver_cancha_por_id(cancha_id)
    if cancha is None:
        return error_response(404, "La cancha solicitada no existe")

    return jsonify(calcular_slots(cancha, fecha_inicio))

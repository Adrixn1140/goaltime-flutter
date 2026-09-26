"""Pagos (spec.md 3.3).

El flujo es siempre el mismo, sea Stripe o la pasarela simulada:

    POST /api/pagos/checkout  ->  el cliente paga fuera  ->  el backend confirma

`checkout` y `/simular` y el webhook terminan en `_aplicar`, que es el único sitio
donde un pago cambia de estado. Así la idempotencia se demuestra en un solo lugar:

    UPDATE pago SET estado = ? WHERE id = ? AND estado = 'pendiente'

De las dos peticiones que intenten confirmar el mismo pago, sólo una cambia filas; la
otra recibe `200 {"aplicado": false}` sin reescribir nada. Un `SELECT` previo habría
permitido que ambas escribieran.
"""

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import func, update

from auth_helpers import usuario_del_token
from errors import error_response
from extensions import db
from models import (
    ESTADO_CONFIRMADA,
    ESTADO_PENDIENTE_PAGO,
    PAGO_APROBADO,
    PAGO_PENDIENTE,
    PAGO_RECHAZADO,
    ROL_ADMIN,
    Pago,
    Reserva,
)
from pasarelas import obtener_pasarela
from pasarelas.base import (
    TIPO_APROBADO,
    DatosCheckout,
    EventoDesconocido,
    EventoPago,
    FirmaInvalida,
)
from pasarelas.mock_pasarela import MockPasarela

bp = Blueprint("pagos", __name__)


@bp.post("/pagos/checkout")
@jwt_required()
def checkout():
    """Abre la sesión de pago de una reserva pendiente y devuelve la URL de la pasarela."""
    cliente = usuario_del_token()
    if cliente is None:
        return error_response(401, "La sesión no es válida")

    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return error_response(400, "El cuerpo debe ser JSON con los campos requeridos")
    try:
        reserva_id = int(datos["reserva_id"])
    except (KeyError, TypeError, ValueError):
        return error_response(400, "reserva_id es obligatorio")

    reserva = db.session.get(Reserva, reserva_id)
    if reserva is None or reserva.pago is None:
        return error_response(404, "La reserva solicitada no existe")
    # El dueño administra sus canchas (§3.4), pero la plata la pone quien reservó: por eso
    # el checkout no acepta a un `dueno` ajeno. El admin sí puede, por soporte.
    if reserva.cliente_id != cliente.id and cliente.rol != ROL_ADMIN:
        return error_response(403, "Esta reserva pertenece a otro cliente")
    if reserva.estado != ESTADO_PENDIENTE_PAGO:
        return error_response(409, "La reserva no está pendiente de pago")

    pasarela = obtener_pasarela()
    url_base = current_app.config["APP_URL_BASE"].rstrip("/")
    checkout_url = pasarela.crear_checkout(
        DatosCheckout(
            pago_id=reserva.pago.id,
            monto=float(reserva.pago.monto),
            moneda=current_app.config["STRIPE_CURRENCY"],
            descripcion=_descripcion(reserva),
            correo=reserva.cliente.email,
            url_exito=f"{url_base}/pago/exito",
            url_cancelacion=f"{url_base}/pago/cancelado",
        )
    )

    return jsonify({"pago_id": reserva.pago.id, "checkout_url": checkout_url}), 201


@bp.post("/pagos/webhook")
def webhook():
    """Confirmación de la pasarela. Sin JWT: la autenticidad es la firma."""
    pasarela = obtener_pasarela()
    try:
        evento = pasarela.verificar_evento(request.get_data(cache=True), request.headers)
    except FirmaInvalida as exc:
        return error_response(400, f"Evento no verificable: {exc}")
    except EventoDesconocido as exc:
        return error_response(400, str(exc))

    if evento is None:
        # Evento auténtico que no nos interesa (`invoice.paid`, por ejemplo): 200 para
        # que la pasarela deje de reintentarlo, sin tocar ningún pago.
        return jsonify({"aplicado": False, "motivo": "evento no relevante"})

    if evento.pago_id is None:
        return error_response(400, "El evento no identifica un pago")
    pago = db.session.get(Pago, evento.pago_id)
    if pago is None:
        return error_response(400, "El evento no corresponde a ningún pago")

    return jsonify(_aplicar(pago, evento))


@bp.get("/pagos/<int:pago_id>")
@jwt_required()
def ver_pago(pago_id):
    """Consulta el pago de una reserva (dueño o admin)."""
    cliente = usuario_del_token()
    if cliente is None:
        return error_response(401, "La sesión no es válida")

    pago = db.session.get(Pago, pago_id)
    if pago is None or pago.reserva is None:
        return error_response(404, "El pago solicitado no existe")
    if pago.reserva.cliente_id != cliente.id and cliente.rol != ROL_ADMIN:
        return error_response(403, "Este pago pertenece a otro cliente")

    return jsonify(pago.to_dict())


@bp.post("/pagos/<int:pago_id>/simular")
@jwt_required()
def simular(pago_id):
    """Endpoint de demostración: cierra el pago sin pasarela externa.

    Sólo existe con `PAGADORA=mock`; con Stripe real se responde `403` para que nadie
    confunda una aprobación de mentira con una verdadera.
    """
    pasarela = obtener_pasarela()
    if not isinstance(pasarela, MockPasarela):
        return error_response(403, "La pasarela activa no admite pagos simulados")

    cliente = usuario_del_token()
    if cliente is None:
        return error_response(401, "La sesión no es válida")
    pago = db.session.get(Pago, pago_id)
    if pago is None or pago.reserva is None:
        return error_response(404, "El pago solicitado no existe")
    if pago.reserva.cliente_id != cliente.id and cliente.rol != ROL_ADMIN:
        return error_response(403, "Este pago pertenece a otro cliente")

    datos = request.get_json(silent=True) or {}
    resultado = str(datos.get("resultado") or "").strip().lower()
    if resultado not in ("aprobado", "rechazado"):
        return error_response(400, "resultado debe ser 'aprobado' o 'rechazado'")

    return jsonify(_aplicar(pago, pasarela.evento(pago.id, resultado)))


def _aplicar(pago, evento: EventoPago):
    """Confirma o rechaza el pago y deja la reserva en el estado que le corresponde.

    Devuelve el cuerpo de la respuesta; el `aplicado` es False cuando el pago ya no
    estaba `pendiente` (evento repetido o fuera de orden).
    """
    aprobado = evento.tipo == TIPO_APROBADO
    nuevo_estado = PAGO_APROBADO if aprobado else PAGO_RECHAZADO
    referencia = evento.referencia or pago.gateway_ref

    cambios = db.session.execute(
        update(Pago)
        .where(Pago.id == pago.id, Pago.estado == PAGO_PENDIENTE)
        .values(estado=nuevo_estado, gateway_ref=referencia, actualizado_en=func.now())
    ).rowcount

    if not cambios:
        db.session.rollback()
        return {"aplicado": False, "pago": pago.to_dict()}

    pago.estado = nuevo_estado
    pago.gateway_ref = referencia
    # Un rechazo reabre el intento: la reserva vuelve a `pendiente_pago` para que el
    # cliente pueda pagar otra vez en lugar de quedarse con un slot inútil (§5).
    pago.reserva.estado = ESTADO_CONFIRMADA if aprobado else ESTADO_PENDIENTE_PAGO
    db.session.commit()

    return {"aplicado": True, "pago": pago.to_dict(), "estado_reserva": pago.reserva.estado}


def _descripcion(reserva):
    horario = reserva.horario
    return (
        f"Reserva {reserva.cancha.nombre} · {reserva.fecha.isoformat()} "
        f"{horario.hora_inicio.strftime('%H:%M')}"
    )

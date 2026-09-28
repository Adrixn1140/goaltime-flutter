"""Gestión del dueño sobre sus canchas (spec.md 3.4).

Vive en `/api/gestion/*` y no en `/api/canchas` porque `GET /api/canchas` es el catálogo
público: sin token, sólo canchas activas y sin `dueno_id`. Si la gestión compartiera
ruta con el catálogo, la misma llamada devolvería dos cosas distintas según quién pregunte.

Tres reglas atraviesan todo el módulo:

1. **El `dueno_id` sale del token.** Un dueño nunca crea una cancha a nombre de otro, ni
   aunque lo mande en el cuerpo: el `POST` ignora cualquier `dueno_id` recibido.
2. **La cancha de otro dueño es `404`, no `403`.** Un `403` confirmaría que el id existe,
   y saber qué canchas ajenas hay también es información. El `403` queda para el rol
   insuficiente (un `cliente` que entra por aquí).
3. **Nada se borra de verdad.** Canchas y horarios se dan de baja y se liberan; el
   histórico manda. Las FK son `ON DELETE RESTRICT` y hay reservas que los apuntan.
"""

from flask import Blueprint, g, jsonify, request
from sqlalchemy import func, true
from sqlalchemy.exc import IntegrityError

from auth_helpers import con_rol, dueno_o_admin
from dominio.disponibilidad import parse_hora
from errors import error_response
from extensions import db
from limites import FOTO, NOMBRE, TARIFA_MAXIMA, UBICACION
from models import (
    ESTADO_CANCELADA,
    ESTADO_CONFIRMADA,
    ESTADO_PENDIENTE_PAGO,
    PAGO_APROBADO,
    ROL_ADMIN,
    ROL_DUENO,
    Cancha,
    Horario,
    Reserva,
)

bp = Blueprint("gestion", __name__)


# --- canchas -------------------------------------------------------------------


@bp.get("/gestion/canchas")
@con_rol(ROL_DUENO, ROL_ADMIN)
def listar_canchas():
    """Canchas del dueño. El admin ve todas, y las ve también inactivas."""
    consulta = db.select(Cancha).order_by(Cancha.nombre)
    if not dueno_o_admin(g.usuario):
        consulta = consulta.where(Cancha.dueno_id == g.usuario.id)
    canchas = db.session.execute(consulta).scalars().all()

    # Un `COUNT` agrupado en vez de una consulta por cancha: con 50 canchas son dos
    # viajes a la base, no 51.
    totales = dict(
        db.session.execute(
            db.select(Horario.cancha_id, func.count(Horario.id)).group_by(Horario.cancha_id)
        ).all()
    )
    minimos = dict(
        db.session.execute(
            db.select(Horario.cancha_id, func.min(Horario.tarifa)).group_by(Horario.cancha_id)
        ).all()
    )

    return jsonify(
        [
            _cancha_gestion(cancha, totales.get(cancha.id, 0), minimos.get(cancha.id))
            for cancha in canchas
        ]
    )


@bp.post("/gestion/canchas")
@con_rol(ROL_DUENO, ROL_ADMIN)
def crear_cancha():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return error_response(400, "El cuerpo debe ser JSON con los campos requeridos")

    nombre, error = _texto(datos, "nombre", NOMBRE)
    if error:
        return error
    ubicacion, error = _texto(datos, "ubicacion", UBICACION)
    if error:
        return error
    foto, error = _texto(datos, "foto", 500, obligatorio=False)
    if error:
        return error

    cancha = Cancha(
        nombre=nombre,
        ubicacion=ubicacion,
        foto=foto,
        # El dueño es el del token. Si es un admin, crea para sí mismo: la reasignación
        # es una operación de Admin (§3.5) y no un campo que llegue por el cuerpo.
        dueno_id=g.usuario.id,
    )
    db.session.add(cancha)
    db.session.commit()

    return jsonify(_cancha_gestion(cancha, 0, None)), 201


@bp.patch("/gestion/canchas/<int:cancha_id>")
@con_rol(ROL_DUENO, ROL_ADMIN)
def actualizar_cancha(cancha_id):
    cancha = _cancha_del_usuario(cancha_id)
    if cancha is None:
        return _no_existe_o_no_es_tuya()

    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return error_response(400, "El cuerpo debe ser JSON con los campos requeridos")

    for campo, limite in (("nombre", NOMBRE), ("ubicacion", UBICACION), ("foto", FOTO)):
        if campo not in datos:
            continue
        valor, error = _texto(datos, campo, limite, obligatorio=campo != "foto")
        if error:
            return error
        setattr(cancha, campo, valor)
    if "activo" in datos:
        if not isinstance(datos["activo"], bool):
            return error_response(400, "activo debe ser true o false")
        cancha.activo = datos["activo"]

    db.session.commit()
    return jsonify(_cancha_gestion(cancha, _total_horarios(cancha.id), _tarifa_minima(cancha.id)))


@bp.delete("/gestion/canchas/<int:cancha_id>")
@con_rol(ROL_DUENO, ROL_ADMIN)
def bajar_cancha(cancha_id):
    """Baja lógica. Repetirla no es un error: desactivar algo ya desactivado es un no-op."""
    cancha = _cancha_del_usuario(cancha_id)
    if cancha is None:
        return _no_existe_o_no_es_tuya()
    cancha.activo = False
    db.session.commit()
    return "", 204


# --- horarios ------------------------------------------------------------------


@bp.get("/gestion/canchas/<int:cancha_id>/horarios")
@con_rol(ROL_DUENO, ROL_ADMIN)
def listar_horarios(cancha_id):
    cancha = _cancha_del_usuario(cancha_id)
    if cancha is None:
        return _no_existe_o_no_es_tuya()
    horarios = db.session.execute(
        db.select(Horario).where(Horario.cancha_id == cancha.id).order_by(Horario.dia, Horario.hora_inicio)
    ).scalars().all()
    return jsonify([horario.to_dict() for horario in horarios])


@bp.post("/gestion/canchas/<int:cancha_id>/horarios")
@con_rol(ROL_DUENO, ROL_ADMIN)
def crear_horario(cancha_id):
    cancha = _cancha_del_usuario(cancha_id)
    if cancha is None:
        return _no_existe_o_no_es_tuya()

    datos, error = _horario_desde_cuerpo()
    if error:
        return error
    if _existe_exacto(cancha.id, datos):
        return error_response(409, "Esa cancha ya tiene un horario que empieza a esa hora")
    if _solapa(cancha.id, datos):
        return _error_solapa()

    horario = Horario(cancha_id=cancha.id, **datos)
    db.session.add(horario)
    try:
        db.session.commit()
    except IntegrityError:
        # La carrera —dos POST simultáneos con el mismo inicio— la arbitra el índice
        # UNIQUE, no la comprobación previa.
        db.session.rollback()
        return error_response(409, "Ese horario ya existe en esta cancha")
    return jsonify(horario.to_dict()), 201


@bp.patch("/gestion/canchas/<int:cancha_id>/horarios/<int:horario_id>")
@con_rol(ROL_DUENO, ROL_ADMIN)
def actualizar_horario(cancha_id, horario_id):
    cancha = _cancha_del_usuario(cancha_id)
    if cancha is None:
        return _no_existe_o_no_es_tuya()
    horario = db.session.get(Horario, horario_id)
    if horario is None or horario.cancha_id != cancha.id:
        return error_response(404, "El horario no existe en esta cancha")

    cuerpo = request.get_json(silent=True)
    if not isinstance(cuerpo, dict):
        return error_response(400, "El cuerpo debe ser JSON con los campos requeridos")

    dato, error = _horario_desde_cuerpo(cuerpo, horario)
    if error:
        return error
    if _existe_exacto(cancha.id, dato, excluir=horario.id):
        return error_response(409, "Esa cancha ya tiene un horario que empieza a esa hora")
    if _solapa(cancha.id, dato, excluir=horario.id):
        return _error_solapa()
    cambia_momento = any(
        campo in cuerpo for campo in ("dia", "hora_inicio", "hora_fin")
    )
    if cambia_momento and _tiene_reservas(horario.id):
        # Mover el slot dejaría las reservas ya vendidas en un horario que ya no
        # corresponde. La tarifa sí se puede tocar: el precio de una reserva cerrada
        # quedó en su pago, no se recalcula.
        return error_response(
            409, "No se puede cambiar el día ni la hora de un horario con reservas"
        )
    for campo, valor in dato.items():
        setattr(horario, campo, valor)

    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return error_response(409, "Ese horario ya existe en esta cancha")
    return jsonify(horario.to_dict())


@bp.delete("/gestion/canchas/<int:cancha_id>/horarios/<int:horario_id>")
@con_rol(ROL_DUENO, ROL_ADMIN)
def borrar_horario(cancha_id, horario_id):
    cancha = _cancha_del_usuario(cancha_id)
    if cancha is None:
        return _no_existe_o_no_es_tuya()
    horario = db.session.get(Horario, horario_id)
    if horario is None or horario.cancha_id != cancha.id:
        return error_response(404, "El horario no existe en esta cancha")
    if _tiene_reservas(horario.id):
        return error_response(409, "El horario tiene reservas y no se puede eliminar")

    db.session.delete(horario)
    try:
        db.session.commit()
    except IntegrityError:
        # Una reserva entró entre la comprobación y el `DELETE`. La FK es
        # `ON DELETE RESTRICT`, así que la base decide y el `409` evita el `500`.
        db.session.rollback()
        return error_response(409, "El horario tiene reservas y no se puede eliminar")
    return "", 204


# --- reservas de la cancha -----------------------------------------------------


@bp.get("/gestion/canchas/<int:cancha_id>/reservas")
@con_rol(ROL_DUENO, ROL_ADMIN)
def listar_reservas(cancha_id):
    """Reservas de la cancha, con quién reservó, para que el dueño sepa a quién responde."""
    cancha = _cancha_del_usuario(cancha_id)
    if cancha is None:
        return _no_existe_o_no_es_tuya()
    reservas = db.session.execute(
        db.select(Reserva)
        .where(Reserva.cancha_id == cancha.id)
        .order_by(Reserva.fecha.desc(), Reserva.id.desc())
    ).scalars().all()
    return jsonify([reserva.to_dict_gestion() for reserva in reservas])


@bp.patch("/gestion/reservas/<int:reserva_id>")
@con_rol(ROL_DUENO, ROL_ADMIN)
def cambiar_estado_reserva(reserva_id):
    reserva = db.session.get(Reserva, reserva_id)
    if reserva is None:
        return error_response(404, "La reserva no existe")
    if _cancha_del_usuario(reserva.cancha_id) is None:
        return _no_existe_o_no_es_tuya()

    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return error_response(400, "El cuerpo debe ser JSON con los campos requeridos")
    accion = str(datos.get("accion") or "").strip().lower()

    if accion == "confirmar":
        if reserva.estado != ESTADO_PENDIENTE_PAGO:
            return error_response(422, "Sólo se confirma una reserva pendiente de pago")
        if reserva.pago is None or reserva.pago.estado != PAGO_APROBADO:
            return error_response(422, "No se puede confirmar una reserva sin pago aprobado")
        reserva.estado = ESTADO_CONFIRMADA
    elif accion == "cancelar":
        if reserva.estado == ESTADO_CANCELADA:
            return error_response(422, "La reserva ya está cancelada")
        if reserva.estado not in (ESTADO_PENDIENTE_PAGO, ESTADO_CONFIRMADA):
            return error_response(422, "Esa reserva no se puede cancelar")
        # No se toca el pago: la regla de reembolso está fuera de alcance (§6). Cancelar
        # libera el slot porque el índice UNIQUE de `reserva` es parcial.
        reserva.estado = ESTADO_CANCELADA
    else:
        return error_response(400, "accion debe ser 'confirmar' o 'cancelar'")

    db.session.commit()
    return jsonify(reserva.to_dict_gestion())


# --- ayudas --------------------------------------------------------------------


def _cancha_del_usuario(cancha_id):
    """La cancha si el usuario puede gestionarla; `None` si no existe o es de otro.

    El admin puede todas, así que la comprobación es "existe y es mía, o soy admin".
    """
    cancha = db.session.get(Cancha, cancha_id)
    if cancha is None:
        return None
    if dueno_o_admin(g.usuario):
        return cancha
    return cancha if cancha.dueno_id == g.usuario.id else None


def _no_existe_o_no_es_tuya():
    # Un mismo 404 para "no existe" y "es de otro dueño": responder distinto confirmaría
    # la existencia de la cancha ajena.
    return error_response(404, "La cancha solicitada no existe")


def _texto(datos, campo, limite, obligatorio=True):
    """Valida un campo de texto. Devuelve `(valor, None)` o `(None, respuesta de error)`."""
    if campo not in datos:
        if obligatorio:
            return None, error_response(400, f"{campo} es obligatorio")
        return "", None
    valor = str(datos.get(campo) or "").strip()
    if obligatorio and not valor:
        return None, error_response(400, f"{campo} es obligatorio")
    if len(valor) > limite:
        return None, error_response(400, f"{campo} no puede superar {limite} caracteres")
    return valor, None


def _horario_desde_cuerpo(cuerpo=None, actual=None):
    """Valida día, horas y tarifa. Con `actual` completa lo que no venga en el `PATCH`.

    El solapamiento se comprueba aquí porque el `CHECK` de la base cubre orden y rango,
    no que dos slots del mismo día se pisen entre sí.
    """
    cuerpo = request.get_json(silent=True) if cuerpo is None else cuerpo
    if not isinstance(cuerpo, dict):
        return None, error_response(400, "El cuerpo debe ser JSON con los campos requeridos")

    try:
        dia = int(cuerpo.get("dia", actual.dia if actual else -1))
    except (TypeError, ValueError):
        return None, error_response(400, "dia debe ser un número entre 0 (lunes) y 6 (domingo)")
    if not 0 <= dia <= 6:
        return None, error_response(
            400, f"dia debe estar entre 0 (lunes) y 6 (domingo); {dia} no es un día"
        )

    inicio = _hora(cuerpo.get("hora_inicio"), actual.hora_inicio if actual else None)
    if inicio is None:
        return None, error_response(400, "hora_inicio debe tener el formato HH:MM")
    fin = _hora(cuerpo.get("hora_fin"), actual.hora_fin if actual else None)
    if fin is None:
        return None, error_response(400, "hora_fin debe tener el formato HH:MM")
    if fin <= inicio:
        return None, error_response(422, "hora_fin debe ser posterior a hora_inicio")

    tarifa = cuerpo.get("tarifa", actual.tarifa if actual else None)
    try:
        tarifa = round(float(tarifa), 2)
    except (TypeError, ValueError):
        return None, error_response(400, "tarifa debe ser un número")
    if tarifa <= 0:
        return None, error_response(422, "La tarifa debe ser mayor que cero")
    if tarifa > TARIFA_MAXIMA:
        # Sin esto PostgreSQL responde 500 con `numeric field overflow`; SQLite guardaba
        # el valor sin quejarse. El tope sale de la columna (spec.md 7.6).
        return None, error_response(422, f"La tarifa no puede superar {_pesos(TARIFA_MAXIMA)}")

    return {"dia": dia, "hora_inicio": inicio, "hora_fin": fin, "tarifa": tarifa}, None


def _pesos(valor):
    """Un número como lo escribe un dueño: 99.999.999,99.

    El mensaje de la API se muestra tal cual en la app, que formatea el dinero con puntos
    de miles y coma decimal. Poner `99999999.99` en un mensaje sería poner algo que nadie entiende.
    """
    entero, decimales = f"{valor:,.2f}".split(".")
    return f"{entero.replace(',', '.')},{decimales}"


def _hora(valor, por_defecto=None):
    if valor is None:
        return por_defecto
    return parse_hora(valor)


def _existe_exacto(cancha_id, datos, excluir=None):
    """¿Ya hay un horario que empiece exactamente a la misma hora y día?

    Es un caso de uso distinto del solapamiento y merece otro código: aquí el mensaje
    correcto es «ese horario ya existe», no «se solapa con otro». El `409` también es el
    que devuelve el índice UNIQUE cuando dos `POST` llegan a la vez (§ IntegrityError).
    """
    return db.session.execute(
        db.select(Horario.id).where(
            Horario.cancha_id == cancha_id,
            Horario.dia == datos["dia"],
            Horario.hora_inicio == datos["hora_inicio"],
            Horario.id != excluir if excluir is not None else true(),
        ).limit(1)
    ).first() is not None


def _solapa(cancha_id, datos, excluir=None):
    """¿El slot choca con otro de la misma cancha y el mismo día?

    Se compara `inicio < otro_fin AND fin > otro_inicio`, que es solapamiento real: dos
    horarios que sólo se tocan (10:00-12:00 y 12:00-14:00) pueden convivir. El `CHECK` de
    la base no cubre esto, así que la regla vive aquí.
    """
    candidatos = db.session.execute(
        db.select(Horario).where(
            Horario.cancha_id == cancha_id,
            Horario.dia == datos["dia"],
        )
    ).scalars().all()
    return any(
        horario.id != excluir
        and horario.hora_inicio < datos["hora_fin"]
        and datos["hora_inicio"] < horario.hora_fin
        for horario in candidatos
    )


def _error_solapa():
    return error_response(
        422, "Ese horario se solapa con otro de la misma cancha en ese día"
    )


def _tiene_reservas(horario_id):
    """¿El horario tiene reservas, incluso canceladas?

    Cancelada o no: la FK es `ON DELETE RESTRICT` y, aunque no lo fuera, una reserva
    apunta a un día y una hora que dejarían de ser ciertos si se moviera el horario.
    Borrar o reubicar un horario con historial es un `409`, no un borrado que deja
    registros de reserva hablando de un slot que ya no existe.
    """
    return (
        db.session.execute(
            db.select(func.count(Reserva.id)).where(Reserva.horario_id == horario_id)
        ).scalar_one()
        or 0
    ) > 0


def _total_horarios(cancha_id):
    return (
        db.session.execute(
            db.select(func.count(Horario.id)).where(Horario.cancha_id == cancha_id)
        ).scalar_one()
        or 0
    )


def _tarifa_minima(cancha_id):
    return db.session.execute(
        db.select(func.min(Horario.tarifa)).where(Horario.cancha_id == cancha_id)
    ).scalar_one()


def _cancha_gestion(cancha, total_horarios, tarifa_minima):
    datos = cancha.to_dict(con_dueno=True)
    datos["total_horarios"] = total_horarios
    datos["tarifa_base"] = float(tarifa_minima) if tarifa_minima is not None else None
    return datos

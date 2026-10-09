"""Equipos privados del cliente: contrato demostrativo en docs/EQUIPOS.md."""

import re

from flask import Blueprint, g, jsonify, request
from sqlalchemy.exc import IntegrityError

from auth_helpers import con_rol
from errors import error_response
from extensions import db
from models import ROL_CLIENTE, Equipo, Jugador

bp = Blueprint("equipos", __name__)


def _equipo_propio(equipo_id):
    return db.session.execute(
        db.select(Equipo).where(Equipo.id == equipo_id, Equipo.cliente_id == g.usuario.id)
    ).scalar_one_or_none()


def _texto(datos, campo, minimo, maximo):
    valor = datos.get(campo)
    if not isinstance(valor, str) or not minimo <= len(valor.strip()) <= maximo:
        return None
    return valor.strip()


@bp.get("/equipos")
@con_rol(ROL_CLIENTE)
def listar():
    equipos = db.session.execute(
        db.select(Equipo).where(Equipo.cliente_id == g.usuario.id).order_by(Equipo.id.desc())
    ).scalars().all()
    return jsonify([e.to_dict() for e in equipos])


@bp.post("/equipos")
@con_rol(ROL_CLIENTE)
def crear():
    datos = request.get_json(silent=True)
    nombre = _texto(datos, "nombre", 3, 80) if isinstance(datos, dict) else None
    if nombre is None:
        return error_response(400, "El nombre del equipo debe tener entre 3 y 80 caracteres")
    equipo = Equipo(nombre=nombre, cliente_id=g.usuario.id)
    db.session.add(equipo)
    db.session.commit()
    return jsonify(equipo.to_dict()), 201


@bp.get("/equipos/<int:equipo_id>")
@con_rol(ROL_CLIENTE)
def detalle(equipo_id):
    equipo = _equipo_propio(equipo_id)
    if equipo is None:
        return error_response(404, "No encontramos ese equipo")
    return jsonify(equipo.to_dict())


@bp.post("/equipos/<int:equipo_id>/jugadores")
@con_rol(ROL_CLIENTE)
def agregar_jugador(equipo_id):
    equipo = _equipo_propio(equipo_id)
    if equipo is None:
        return error_response(404, "No encontramos ese equipo")
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return error_response(400, "El cuerpo debe ser JSON con los campos requeridos")
    nombre = _texto(datos, "nombre", 2, 80)
    apellido = _texto(datos, "apellido", 2, 80)
    documento = _texto(datos, "documento", 5, 20)
    celular = _texto(datos, "celular", 10, 15)
    if nombre is None or apellido is None:
        return error_response(400, "Nombre y apellido deben tener entre 2 y 80 caracteres")
    if documento is None or not re.fullmatch(r"[0-9]{5,20}", documento):
        return error_response(400, "El documento debe tener entre 5 y 20 dígitos")
    if celular is None or not re.fullmatch(r"[0-9]{10,15}", celular):
        return error_response(400, "El celular debe tener entre 10 y 15 dígitos, sin espacios ni +")
    jugador = Jugador(equipo_id=equipo.id, nombre=nombre, apellido=apellido,
                      documento=documento, celular=celular)
    db.session.add(jugador)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return error_response(409, "Ese documento ya está registrado en este equipo")
    return jsonify(jugador.to_dict()), 201

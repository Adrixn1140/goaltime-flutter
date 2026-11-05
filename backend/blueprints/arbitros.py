"""Perfiles privados y directorio con publicación voluntaria (docs/ARBITROS.md)."""

import re
from decimal import Decimal, InvalidOperation

from flask import Blueprint, g, jsonify, request
from sqlalchemy.exc import IntegrityError

from auth_helpers import con_rol
from dominio.arbitros import perfiles_publicados
from errors import error_response
from extensions import db
from models import PerfilArbitro, ROL_ARBITRO

bp = Blueprint("arbitros", __name__)


@bp.get("/arbitros")
@con_rol()
def listar():
    q = request.args.get("q", "").strip()
    estado = request.args.get("disponible")
    if len(q) > 100 or estado not in (None, "true", "false"):
        return error_response(400, "Búsqueda de hasta 100 caracteres; disponible debe ser true o false")
    perfiles = db.session.execute(perfiles_publicados(q, None if estado is None else estado == "true")).scalars().all()
    return jsonify([p.to_dict() for p in perfiles])


@bp.get("/arbitros/mi-perfil")
@con_rol(ROL_ARBITRO)
def mi_perfil():
    perfil = db.session.execute(db.select(PerfilArbitro).where(PerfilArbitro.cliente_id == g.usuario.id)).scalar_one_or_none()
    return jsonify(perfil.to_dict() if perfil else None)


@bp.put("/arbitros/mi-perfil")
@con_rol(ROL_ARBITRO)
def guardar():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return error_response(400, "El cuerpo debe ser JSON con los campos del perfil")
    textos = {}
    for campo, minimo, maximo in (("ciudad", 2, 100), ("celular", 10, 15), ("biografia", 0, 500)):
        valor = datos.get(campo)
        if not isinstance(valor, str) or not minimo <= len(valor.strip()) <= maximo:
            return error_response(400, f"{campo}: escribe entre {minimo} y {maximo} caracteres")
        textos[campo] = valor.strip()
    if not re.fullmatch(r"[0-9]{10,15}", textos["celular"]):
        return error_response(400, "El celular debe tener entre 10 y 15 dígitos, sin espacios ni +")
    experiencia = datos.get("experiencia")
    if type(experiencia) is not int or not 0 <= experiencia <= 60:
        return error_response(400, "Experiencia debe ser un número entero entre 0 y 60 años")
    if any(type(datos.get(c)) is not bool for c in ("disponible", "publicado")):
        return error_response(400, "Disponible y publicado deben ser true o false")
    try:
        tarifa = Decimal(str(datos.get("tarifa")))
        if not tarifa.is_finite() or not 0 < tarifa <= 10000000 or tarifa != tarifa.quantize(Decimal("0.01")):
            raise ValueError()
    except (InvalidOperation, ValueError):
        return error_response(400, "La tarifa por partido debe ser mayor que 0, hasta $10.000.000 y con máximo dos decimales")
    perfil = db.session.execute(db.select(PerfilArbitro).where(PerfilArbitro.cliente_id == g.usuario.id)).scalar_one_or_none()
    if perfil is None:
        perfil = PerfilArbitro(cliente_id=g.usuario.id)
        db.session.add(perfil)
    for campo, valor in textos.items():
        setattr(perfil, campo, valor)
    perfil.experiencia, perfil.tarifa = experiencia, tarifa
    perfil.disponible, perfil.publicado = datos["disponible"], datos["publicado"]
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return error_response(409, "El perfil cambió mientras lo guardabas. Actualiza e inténtalo de nuevo")
    return jsonify(perfil.to_dict())

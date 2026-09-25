"""Catálogo público de canchas (spec.md 3.2).

Sólo expone canchas activas y nunca `dueno_id` ni `activo`: el catálogo es público y
`tarifa_base` se calcula en una sola consulta agregada (sin N+1).
"""

from flask import Blueprint, jsonify
from sqlalchemy import func

from extensions import db
from models import Cancha, Horario

bp = Blueprint("canchas", __name__)


@bp.get("/canchas")
def listar_canchas():
    precios = (
        db.select(Horario.cancha_id, func.min(Horario.tarifa).label("tarifa_base"))
        .group_by(Horario.cancha_id)
        .subquery()
    )
    filas = db.session.execute(
        db.select(Cancha, precios.c.tarifa_base)
        .outerjoin(precios, Cancha.id == precios.c.cancha_id)
        .where(Cancha.activo.is_(True))
        .order_by(Cancha.nombre)
    ).all()

    canchas = []
    for cancha, tarifa_base in filas:
        item = cancha.to_dict()
        item["tarifa_base"] = float(tarifa_base) if tarifa_base is not None else None
        canchas.append(item)

    return jsonify(canchas)

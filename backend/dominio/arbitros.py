"""Consulta compartida del directorio: nunca expone borradores ni cuentas inactivas."""

from sqlalchemy import or_

from extensions import db
from models import Cliente, Maestra, PerfilArbitro, ROL_ARBITRO


def perfiles_publicados(q="", disponible=None):
    consulta = (db.select(PerfilArbitro).join(Cliente, Cliente.id == PerfilArbitro.cliente_id)
                .join(Maestra, Maestra.id == Cliente.rol_id)
                .where(PerfilArbitro.publicado.is_(True), Cliente.activo.is_(True),
                       Maestra.tipo == "rol", Maestra.codigo == ROL_ARBITRO))
    if q:
        consulta = consulta.where(or_(Cliente.nombre.icontains(q, autoescape=True),
                                      PerfilArbitro.ciudad.icontains(q, autoescape=True)))
    if disponible is not None:
        consulta = consulta.where(PerfilArbitro.disponible.is_(disponible))
    return consulta.order_by(PerfilArbitro.tarifa, PerfilArbitro.id)

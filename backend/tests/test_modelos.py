"""Tests del modelo y de las restricciones que sostienen las reglas de negocio.

Estas restricciones son la base de los `409` y del aislamiento por `dueno_id`
descritos en spec.md 2, así que se verifican a nivel de base de datos y no sólo
a través de los endpoints.
"""

from datetime import date, time

import pytest
from sqlalchemy.exc import IntegrityError

from extensions import db
from models import (
    ROL_CLIENTE,
    Cancha,
    Cliente,
    Horario,
    Maestra,
    Pago,
    Reserva,
)


def test_catalogos_cargados(app):
    assert Maestra.codigos("rol") == {"cliente", "dueno", "admin"}
    assert Maestra.codigos("estado_reserva") == {"pendiente_pago", "confirmada", "cancelada"}
    assert Maestra.codigos("estado_pago") == {"pendiente", "aprobado", "rechazado"}


def test_horario_unico_por_cancha_dia_hora(app, cancha, horario):
    """No se pueden duplicar slots que arranquen a la misma hora."""
    db.session.add(
        Horario(
            cancha_id=cancha.id, dia=0, hora_inicio=time(8, 0), hora_fin=time(9, 0), tarifa=50000
        )
    )
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()


@pytest.mark.parametrize("dia", [-1, 7])
def test_horario_rechaza_dia_fuera_de_iso(app, cancha, dia):
    db.session.add(
        Horario(cancha_id=cancha.id, dia=dia, hora_inicio=time(8, 0), hora_fin=time(10, 0), tarifa=1)
    )
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()


def test_horario_rechaza_hora_fin_anterior(app, cancha):
    db.session.add(
        Horario(cancha_id=cancha.id, dia=1, hora_inicio=time(18, 0), hora_fin=time(10, 0), tarifa=1)
    )
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()


def test_reserva_unica_por_slot_y_fecha(app, cancha, horario, cliente):
    """Origen del `409`: un slot sólo admite una reserva por día."""
    hoy = date.today()
    db.session.add(Reserva(cliente_id=cliente.id, cancha_id=cancha.id, horario_id=horario.id, fecha=hoy))
    db.session.commit()

    db.session.add(Reserva(cliente_id=cliente.id, cancha_id=cancha.id, horario_id=horario.id, fecha=hoy))
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()


def test_reserva_admite_otro_dia_en_el_mismo_slot(app, cancha, horario, cliente):
    hoy = date.today()
    db.session.add_all(
        [
            Reserva(cliente_id=cliente.id, cancha_id=cancha.id, horario_id=horario.id, fecha=hoy),
            Reserva(
                cliente_id=cliente.id,
                cancha_id=cancha.id,
                horario_id=horario.id,
                fecha=date.fromordinal(hoy.toordinal() + 1),
            ),
        ]
    )
    db.session.commit()
    assert len(db.session.execute(db.select(Reserva)).scalars().all()) == 2


def test_pago_unico_por_reserva(app, cancha, horario, cliente):
    reserva = Reserva(
        cliente_id=cliente.id, cancha_id=cancha.id, horario_id=horario.id, fecha=date.today()
    )
    db.session.add(reserva)
    db.session.flush()
    db.session.add(Pago(reserva_id=reserva.id, monto=60000, metodo="mock", estado="pendiente"))
    db.session.commit()

    db.session.add(Pago(reserva_id=reserva.id, monto=60000, metodo="mock", estado="pendiente"))
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()


def test_claves_foraneas_son_aplicadas(app, horario):
    """La PRAGMA de SQLite está activa: un cliente inexistente no puede reservarse."""
    db.session.add(
        Reserva(cliente_id=99999, cancha_id=horario.cancha_id, horario_id=horario.id, fecha=date.today())
    )
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()


def test_no_se_puede_borrar_un_dueno_con_canchas(app, dueno, cancha):
    """`ondelete=RESTRICT` protege la trazabilidad de las canchas."""
    db.session.commit()  # los fixtures sólo hacen flush
    db.session.delete(dueno)
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()
    assert db.session.get(Cancha, cancha.id) is not None


def test_cancha_oculta_dueno_en_la_respuesta_publica(app, dueno, cancha):
    assert "dueno_id" not in cancha.to_dict()
    assert "dueno_id" in cancha.to_dict(con_dueno=True)


def test_rol_se_expone_como_codigo(app, cliente):
    assert cliente.rol == ROL_CLIENTE
    assert cliente.to_dict() == {
        "id": cliente.id,
        "nombre": cliente.nombre,
        "email": cliente.email,
        "rol": ROL_CLIENTE,
        "activo": True,
    }

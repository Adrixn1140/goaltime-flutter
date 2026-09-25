"""Tests del catálogo público de canchas (spec.md 3.2)."""

from extensions import db
from models import Cancha, Horario


def test_lista_solo_canchas_activas(app, client, dueno):
    activa = Cancha(nombre="Cancha Activa", ubicacion="Cra 1", dueno_id=dueno.id)
    inactiva = Cancha(nombre="Cancha Inactiva", ubicacion="Cra 2", dueno_id=dueno.id, activo=False)
    db.session.add_all([activa, inactiva])
    db.session.commit()

    cuerpo = client.get("/api/canchas").get_json()
    assert [c["nombre"] for c in cuerpo] == ["Cancha Activa"]


def test_orden_por_nombre(app, client, dueno):
    db.session.add_all(
        [
            Cancha(nombre="Zeta", ubicacion="Cra 1", dueno_id=dueno.id),
            Cancha(nombre="Alfa", ubicacion="Cra 2", dueno_id=dueno.id),
            Cancha(nombre="Media", ubicacion="Cra 3", dueno_id=dueno.id),
        ]
    )
    db.session.commit()

    cuerpo = client.get("/api/canchas").get_json()
    assert [c["nombre"] for c in cuerpo] == ["Alfa", "Media", "Zeta"]


def test_tarifa_base_es_el_horario_mas_barato(app, client, dueno):
    from datetime import time

    cancha = Cancha(nombre="Con precios", ubicacion="Cra 1", dueno_id=dueno.id)
    db.session.add(cancha)
    db.session.flush()
    db.session.add_all(
        [
            Horario(cancha_id=cancha.id, dia=0, hora_inicio=time(8, 0), hora_fin=time(10, 0), tarifa=80000),
            Horario(cancha_id=cancha.id, dia=1, hora_inicio=time(8, 0), hora_fin=time(10, 0), tarifa=45000),
            Horario(cancha_id=cancha.id, dia=2, hora_inicio=time(8, 0), hora_fin=time(10, 0), tarifa=60000),
        ]
    )
    db.session.commit()

    cuerpo = client.get("/api/canchas").get_json()
    assert cuerpo[0]["tarifa_base"] == 45000.0


def test_tarifa_base_null_sin_horarios(app, client, dueno):
    db.session.add(Cancha(nombre="Sin horarios", ubicacion="Cra 1", dueno_id=dueno.id))
    db.session.commit()

    cuerpo = client.get("/api/canchas").get_json()
    assert cuerpo[0]["tarifa_base"] is None


def test_no_expone_dueno_ni_activo(app, client, cancha, dueno):
    """El catálogo es público: nada de `dueno_id` ni del flag `activo`."""
    cuerpo = client.get("/api/canchas").get_json()
    assert cuerpo == [
        {
            "id": cancha.id,
            "nombre": "Cancha Prueba",
            "ubicacion": "Cra 1 #2-3",
            "foto": "",
            "tarifa_base": None,
        }
    ]
    assert dueno.id not in [c.get("dueno_id") for c in cuerpo]


def test_catalogo_vacio_sin_canchas(client):
    r = client.get("/api/canchas")
    assert r.status_code == 200
    assert r.get_json() == []


def test_catalogo_no_exige_autenticacion(app, client):
    """Ni token ni credenciales: es público por contrato."""
    assert client.get("/api/canchas").status_code == 200


def test_tarifa_base_solo_considera_horarios_de_la_cancha(app, client, dueno):
    """La agregación no puede mezclar precios entre canchas."""
    from datetime import time

    barata = Cancha(nombre="Barata", ubicacion="Cra 1", dueno_id=dueno.id)
    cara = Cancha(nombre="Cara", ubicacion="Cra 2", dueno_id=dueno.id)
    db.session.add_all([barata, cara])
    db.session.flush()
    db.session.add_all(
        [
            Horario(cancha_id=barata.id, dia=0, hora_inicio=time(8, 0), hora_fin=time(10, 0), tarifa=30000),
            Horario(cancha_id=cara.id, dia=0, hora_inicio=time(8, 0), hora_fin=time(10, 0), tarifa=99000),
        ]
    )
    db.session.commit()

    cuerpo = {c["nombre"]: c["tarifa_base"] for c in client.get("/api/canchas").get_json()}
    assert cuerpo == {"Barata": 30000.0, "Cara": 99000.0}

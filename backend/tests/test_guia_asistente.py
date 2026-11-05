import pytest
from flask_jwt_extended import create_access_token

from extensions import db
from models import Equipo, Jugador
from test_arbitros import PERFIL, auth


def test_guia_funciona_sin_proveedor_y_no_modifica(client, cliente, monkeypatch):
    def no_llamar():
        raise AssertionError("La guía no debe llamar al proveedor")
    monkeypatch.setattr("blueprints.asistente.obtener_motor", no_llamar)
    r = client.post("/api/asistente", headers=auth(cliente), json={"mensaje": "¿Cómo añadir jugadores a mi equipo?"})
    assert r.status_code == 200
    assert r.json["motor"] == "guia-local"
    assert r.json["acciones"][0]["destino"] == "equipos"
    assert "5–20" in r.json["respuesta"]
    assert db.session.query(Equipo).count() == 0


def test_resumen_solo_equipos_propios_sin_datos_personales(client, cliente, dueno):
    e = Equipo(nombre="Propio", cliente_id=cliente.id)
    ajeno = Equipo(nombre="Secreto ajeno", cliente_id=dueno.id)
    db.session.add_all([e, ajeno])
    db.session.flush()
    db.session.add(Jugador(equipo_id=e.id, nombre="Privado", apellido="Prueba", documento="999999999", celular="3333333333"))
    db.session.commit()
    r = client.post("/api/asistente", headers=auth(cliente), json={"mensaje": "Muéstrame mis equipos"})
    assert "Propio" in r.json["respuesta"] and "1 jugadores" in r.json["respuesta"]
    for secreto in ("Secreto ajeno", "999999999", "3333333333", "Privado"):
        assert secreto not in r.json["respuesta"]


def test_consulta_arbitros_solo_publicados_y_disponibles(client, cliente, arbitro):
    client.put("/api/arbitros/mi-perfil", headers=auth(arbitro), json={**PERFIL, "publicado": True})
    r = client.post("/api/asistente", headers=auth(cliente), json={"mensaje": "Busca árbitros disponibles en Riohacha"})
    assert arbitro.nombre in r.json["respuesta"] and "55,000" in r.json["respuesta"]
    assert r.json["acciones"][0]["destino"] == "arbitros"
    client.put("/api/arbitros/mi-perfil", headers=auth(arbitro), json=PERFIL)
    r = client.post("/api/asistente", headers=auth(cliente), json={"mensaje": "Árbitros disponibles"})
    assert arbitro.nombre not in r.json["respuesta"]
    assert "No encontré" in r.json["respuesta"]


@pytest.mark.parametrize("mensaje", ["Cómo publicar mi perfil de árbitro", "Quiero ser árbitro", "Qué funciones puedes hacer", "Organiza un torneo"])
def test_orientacion_sin_promesas_de_operaciones(client, cliente, mensaje):
    r = client.post("/api/asistente", headers=auth(cliente), json={"mensaje": mensaje})
    assert r.status_code == 200 and r.json["sugerencias"] == []
    assert r.json["acciones"]


@pytest.mark.parametrize("cuerpo", [[], ["hola"], {"mensaje": "x" * 1001}])
def test_mensaje_invalido_no_da_500(client, cliente, cuerpo):
    assert client.post("/api/asistente", headers=auth(cliente), json=cuerpo).status_code == 400

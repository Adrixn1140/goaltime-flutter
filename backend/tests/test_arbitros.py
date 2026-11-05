import pytest
from flask_jwt_extended import create_access_token

from extensions import db
from models import PerfilArbitro, Cliente, ROL_CLIENTE, Maestra

PERFIL = {"ciudad": "Riohacha", "celular": "3000000000", "experiencia": 3,
          "biografia": "Árbitro de fútbol aficionado", "tarifa": "55000.50", "disponible": True, "publicado": False}


def auth(usuario):
    return {"Authorization": "Bearer " + create_access_token(identity=str(usuario.id))}


def test_registro_arbitro_login_y_perfil_privado(client):
    datos = {"nombre": "Ana Árbitra", "email": "arbitra@test.co", "password": "Goaltime123!", "tipo_cuenta": "arbitro", "rol": "admin"}
    r = client.post("/api/register", json=datos)
    assert r.status_code == 201
    assert r.json["rol"] == "arbitro"
    headers = {"Authorization": "Bearer " + r.json["access_token"]}
    assert client.get("/api/arbitros/mi-perfil", headers=headers).json is None
    assert client.put("/api/arbitros/mi-perfil", headers=headers, json=PERFIL).status_code == 200
    assert client.get("/api/arbitros", headers=headers).json == []
    assert client.post("/api/login", json=datos).json["rol"] == "arbitro"
    assert client.get("/api/equipos", headers=headers).status_code == 403


@pytest.mark.parametrize("tipo", ["admin", "dueno", "otro", None, {}, []])
def test_no_registra_privilegios(client, tipo):
    r = client.post("/api/register", json={"name": "Nombre", "email": "a@test.co", "password": "Goaltime123!", "tipo_cuenta": tipo})
    assert r.status_code == 400


def test_publicar_buscar_ocultar_y_no_disponible(client, arbitro, cliente):
    headers = auth(arbitro)
    publico = {**PERFIL, "publicado": True}
    assert client.put("/api/arbitros/mi-perfil", headers=headers, json=publico).status_code == 200
    lista = client.get("/api/arbitros?q=Rioh&disponible=true", headers=auth(cliente)).json
    assert len(lista) == 1 and lista[0]["tarifa"] == 55000.5
    assert "cliente_id" not in lista[0] and "email" not in lista[0]
    assert client.get("/api/arbitros?q=inexistente", headers=headers).json == []
    assert client.get("/api/arbitros?q=%", headers=headers).json == []
    client.put("/api/arbitros/mi-perfil", headers=headers, json={**publico, "disponible": False})
    assert client.get("/api/arbitros?disponible=true", headers=headers).json == []
    assert len(client.get("/api/arbitros?disponible=false", headers=headers).json) == 1
    client.put("/api/arbitros/mi-perfil", headers=headers, json=PERFIL)
    assert client.get("/api/arbitros", headers=headers).json == []
    assert db.session.query(PerfilArbitro).count() == 1


@pytest.mark.parametrize("cambios", [{"ciudad": "a"}, {"biografia": "a" * 501}, {"celular": "abc1234567"},
    {"experiencia": True}, {"experiencia": 61}, {"experiencia": 1.5}, {"tarifa": "NaN"}, {"tarifa": "Infinity"},
    {"tarifa": "1.001"}, {"tarifa": 0}, {"tarifa": -2}, {"tarifa": 10000001}, {"tarifa": True},
    {"publicado": "false"}, {"disponible": 1}])
def test_valida_perfil_y_no_persiste(client, arbitro, cambios):
    assert client.put("/api/arbitros/mi-perfil", headers=auth(arbitro), json={**PERFIL, **cambios}).status_code == 400
    assert db.session.query(PerfilArbitro).count() == 0


def test_perfil_no_expuesto_al_desactivar_o_cambiar_rol(client, arbitro, admin):
    client.put("/api/arbitros/mi-perfil", headers=auth(arbitro), json={**PERFIL, "publicado": True})
    arbitro.activo = False
    db.session.commit()
    assert client.get("/api/arbitros", headers=auth(admin)).json == []
    arbitro.activo = True
    db.session.commit()
    assert client.patch(f"/api/usuarios/{arbitro.id}/rol", headers=auth(admin), json={"rol": "cliente"}).status_code == 200
    assert client.get("/api/arbitros", headers=auth(admin)).json == []
    assert db.session.query(PerfilArbitro).one().publicado is False


def test_identidad_sale_del_token_y_solo_arbitro_edita(client, arbitro, cliente):
    r = client.put("/api/arbitros/mi-perfil", headers=auth(arbitro), json={**PERFIL, "cliente_id": cliente.id, "nombre": "Falso"})
    assert r.json["nombre"] == arbitro.nombre
    assert db.session.query(PerfilArbitro).one().cliente_id == arbitro.id
    assert client.put("/api/arbitros/mi-perfil", headers=auth(cliente), json=PERFIL).status_code == 403
    assert client.get("/api/arbitros/mi-perfil", headers=auth(cliente)).status_code == 403
    assert client.get("/api/arbitros").status_code == 401


def test_otro_arbitro_no_hereda_perfil(client, arbitro):
    client.put("/api/arbitros/mi-perfil", headers=auth(arbitro), json=PERFIL)
    otro = Cliente(nombre="Otro", email="otro@test.co", rol_id=arbitro.rol_id)
    otro.set_password("Goaltime123!")
    db.session.add(otro)
    db.session.commit()
    assert client.get("/api/arbitros/mi-perfil", headers=auth(otro)).json is None


@pytest.mark.parametrize("cuerpo", [[], None, {}])
def test_perfil_requiere_cuerpo_completo(client, arbitro, cuerpo):
    assert client.put("/api/arbitros/mi-perfil", headers=auth(arbitro), json=cuerpo).status_code == 400


def test_filtros_invalidos(client, cliente):
    assert client.get("/api/arbitros?disponible=si", headers=auth(cliente)).status_code == 400
    assert client.get("/api/arbitros?q=" + "x" * 101, headers=auth(cliente)).status_code == 400


def test_dueno_con_canchas_no_puede_convertirse_en_arbitro(client, cancha, dueno, admin):
    assert client.patch(f"/api/usuarios/{dueno.id}/rol", headers=auth(admin), json={"rol": "arbitro"}).status_code == 422

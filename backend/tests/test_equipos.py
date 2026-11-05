import pytest
from flask_jwt_extended import create_access_token

from extensions import db
from models import Cliente, Equipo, Jugador

JUGADOR = {"nombre": "Ana", "apellido": "Prueba", "documento": "0001234567", "celular": "3000000000"}


def _headers(usuario):
    return {"Authorization": f"Bearer {create_access_token(identity=str(usuario.id))}"}


def _crear(client, usuario):
    return client.post("/api/equipos", json={"nombre": "Los del barrio", "cliente_id": 999}, headers=_headers(usuario))


def test_equipo_y_jugador_persisten(client, cliente):
    respuesta = _crear(client, cliente)
    assert respuesta.status_code == 201
    equipo = respuesta.get_json()
    assert equipo["jugadores"] == []
    assert db.session.get(Equipo, equipo["id"]).cliente_id == cliente.id
    ruta = f"/api/equipos/{equipo['id']}"
    assert client.post(ruta + "/jugadores", json=JUGADOR, headers=_headers(cliente)).status_code == 201
    db.session.expire_all()
    detalle = client.get(ruta, headers=_headers(cliente)).get_json()
    assert detalle["jugadores"][0]["documento"] == "0001234567"
    assert detalle["jugadores"][0]["celular"] == JUGADOR["celular"]
    assert client.get("/api/equipos", headers=_headers(cliente)).get_json() == [detalle]


def test_no_se_repite_documento_y_rollback_no_pierde_datos(client, cliente):
    equipo = _crear(client, cliente).get_json()
    ruta = f"/api/equipos/{equipo['id']}/jugadores"
    assert client.post(ruta, json=JUGADOR, headers=_headers(cliente)).status_code == 201
    assert client.post(ruta, json=JUGADOR, headers=_headers(cliente)).status_code == 409
    assert client.post(ruta, json={**JUGADOR, "documento": "9876543210"}, headers=_headers(cliente)).status_code == 201
    assert db.session.query(Jugador).count() == 2


def test_aislamiento_entre_clientes(client, cliente):
    equipo = _crear(client, cliente).get_json()
    otro = Cliente(nombre="Otro Cliente", email="otro@test.co", rol_id=cliente.rol_id)
    otro.set_password("Goaltime123!")
    db.session.add(otro)
    db.session.commit()
    ruta = f"/api/equipos/{equipo['id']}"
    assert client.get("/api/equipos", headers=_headers(otro)).get_json() == []
    assert client.get(ruta, headers=_headers(otro)).status_code == 404
    assert client.post(ruta + "/jugadores", json=JUGADOR, headers=_headers(otro)).status_code == 404


@pytest.mark.parametrize("rol", ["dueno", "admin"])
def test_otro_rol_no_tiene_acceso(client, request, rol):
    usuario = request.getfixturevalue(rol)
    for metodo, ruta in [("GET", "/api/equipos"), ("POST", "/api/equipos"),
                         ("GET", "/api/equipos/1"), ("POST", "/api/equipos/1/jugadores")]:
        assert client.open(ruta, method=metodo, json={}, headers=_headers(usuario)).status_code == 403


def test_sin_sesion_o_cuenta_desactivada(client, cliente):
    for metodo, ruta in [("GET", "/api/equipos"), ("POST", "/api/equipos"),
                         ("GET", "/api/equipos/1"), ("POST", "/api/equipos/1/jugadores")]:
        assert client.open(ruta, method=metodo, json={}).status_code == 401
    headers = _headers(cliente)
    cliente.activo = False
    db.session.commit()
    assert client.get("/api/equipos", headers=headers).status_code == 401


@pytest.mark.parametrize("datos", [None, [], {}, {"nombre": "ab"}, {"nombre": "x" * 81}, {"nombre": 12}])
def test_valida_nombre_equipo(client, cliente, datos):
    assert client.post("/api/equipos", json=datos, headers=_headers(cliente)).status_code == 400


@pytest.mark.parametrize("campo,valor", [("nombre", "A"), ("apellido", ""), ("nombre", "x" * 81),
    ("documento", 123456789), ("documento", "abcde"), ("documento", "1234"),
    ("documento", "1" * 21), ("celular", "+573001234567"), ("celular", "123"),
    ("celular", "1" * 16), ("celular", "abcdefghij")])
def test_valida_jugador(client, cliente, campo, valor):
    equipo = _crear(client, cliente).get_json()
    assert client.post(f"/api/equipos/{equipo['id']}/jugadores", json={**JUGADOR, campo: valor},
                       headers=_headers(cliente)).status_code == 400
    assert db.session.query(Jugador).count() == 0


def test_editar_retirar_y_eliminar_equipo(client, cliente):
    headers = _headers(cliente)
    equipo = _crear(client, cliente).json
    ruta = f"/api/equipos/{equipo['id']}"
    jugador = client.post(ruta + "/jugadores", headers=headers, json=JUGADOR).json
    jruta = ruta + f"/jugadores/{jugador['id']}"
    assert client.patch(ruta, headers=headers, json={"nombre": "Nuevo equipo"}).json["nombre"] == "Nuevo equipo"
    assert client.patch(jruta, headers=headers, json={"apellido": "Actualizado"}).json["apellido"] == "Actualizado"
    assert client.get(ruta, headers=headers).json["jugadores"][0]["documento"] == JUGADOR["documento"]
    assert client.delete(jruta, headers=headers).status_code == 204
    assert client.get(ruta, headers=headers).json["jugadores"] == []
    client.post(ruta + "/jugadores", headers=headers, json=JUGADOR)
    assert client.delete(ruta, headers=headers).status_code == 204
    assert db.session.query(Jugador).count() == 0
    assert client.get(ruta, headers=headers).status_code == 404


def test_colision_al_editar_hace_rollback(client, cliente):
    headers = _headers(cliente)
    equipo = _crear(client, cliente).json
    ruta = f"/api/equipos/{equipo['id']}/jugadores"
    client.post(ruta, headers=headers, json=JUGADOR)
    otro = client.post(ruta, headers=headers, json={**JUGADOR, "documento": "12345678"}).json
    r = client.patch(ruta + f"/{otro['id']}", headers=headers, json={"documento": JUGADOR["documento"], "nombre": "No guardar"})
    assert r.status_code == 409
    assert db.session.get(Jugador, otro["id"]).nombre == JUGADOR["nombre"]
    assert db.session.get(Jugador, otro["id"]).documento == "12345678"


def test_edicion_y_borrado_no_admiten_ids_ajenos(client, cliente):
    headers = _headers(cliente)
    e1, e2 = _crear(client, cliente).json, _crear(client, cliente).json
    j = client.post(f"/api/equipos/{e1['id']}/jugadores", headers=headers, json=JUGADOR).json
    ruta_cruzada = f"/api/equipos/{e2['id']}/jugadores/{j['id']}"
    assert client.patch(ruta_cruzada, headers=headers, json={"nombre": "Falso"}).status_code == 404
    assert client.delete(ruta_cruzada, headers=headers).status_code == 404
    otro = Cliente(nombre="Otro", email="ajeno@test.co", rol_id=cliente.rol_id)
    otro.set_password("Goaltime123!")
    db.session.add(otro)
    db.session.commit()
    for metodo, ruta in [("PATCH", f"/api/equipos/{e1['id']}"), ("DELETE", f"/api/equipos/{e1['id']}"),
                         ("PATCH", f"/api/equipos/{e1['id']}/jugadores/{j['id']}"), ("DELETE", f"/api/equipos/{e1['id']}/jugadores/{j['id']}")]:
        assert client.open(ruta, method=metodo, headers=_headers(otro), json={"nombre": "Ajeno"}).status_code == 404


def test_no_hay_limite_de_tres_equipos(client, cliente):
    for _ in range(4):
        equipo = _crear(client, cliente).json
        assert client.post(f"/api/equipos/{equipo['id']}/jugadores", headers=_headers(cliente), json=JUGADOR).status_code == 201
    assert len(client.get("/api/equipos", headers=_headers(cliente)).json) == 4

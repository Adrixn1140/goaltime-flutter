"""Tests de auth contra el contrato de spec.md 3.1."""

import pytest
from sqlalchemy.exc import IntegrityError

from extensions import db
from models import ROL_ADMIN, ROL_CLIENTE, Cliente

REGISTRO_VALIDO = {
    "name": "Ana Nueva",
    "email": "Ana.Nueva@Test.co",
    "password": "Goaltime123!",
}


def test_health(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    assert r.get_json()["estado"] == "ok"


def test_register_devuelve_201_con_token_rol_y_usuario(client):
    r = client.post("/api/register", json=REGISTRO_VALIDO)
    assert r.status_code == 201

    cuerpo = r.get_json()
    assert cuerpo["rol"] == ROL_CLIENTE
    assert cuerpo["usuario"]["email"] == "ana.nueva@test.co"  # normalizado a minúsculas
    assert cuerpo["usuario"]["nombre"] == "Ana Nueva"
    assert "password" not in str(cuerpo)  # nunca se filtra el hash
    assert cuerpo["access_token"]


def test_register_normaliza_el_email(client):
    client.post("/api/register", json=REGISTRO_VALIDO)
    duplicado = dict(REGISTRO_VALIDO, email="ANA.NUEVA@TEST.CO")
    r = client.post("/api/register", json=duplicado)
    assert r.status_code == 409


def test_register_email_duplicado_409(client):
    assert client.post("/api/register", json=REGISTRO_VALIDO).status_code == 201
    r = client.post("/api/register", json=REGISTRO_VALIDO)
    assert r.status_code == 409
    assert r.get_json()["error"]["mensaje"] == "El email ya está registrado"


@pytest.mark.parametrize(
    "cambios, esperado",
    [
        ({"name": ""}, 400),
        ({"email": "no-es-un-email"}, 400),
        ({"password": "corta"}, 400),
        ({"password": ""}, 400),
    ],
)
def test_register_valida_campos(client, cambios, esperado):
    r = client.post("/api/register", json={**REGISTRO_VALIDO, **cambios})
    assert r.status_code == esperado


def test_register_ignora_rol_enviado_por_el_cliente(client):
    """El registro público no puede autopromocionarse a admin (spec.md 3.1)."""
    r = client.post("/api/register", json={**REGISTRO_VALIDO, "role": ROL_ADMIN, "rol": ROL_ADMIN})
    assert r.status_code == 201
    assert r.get_json()["rol"] == ROL_CLIENTE


def test_register_rechaza_cuerpo_no_json(client):
    assert client.post("/api/register", data="no json").status_code == 400


def test_login_exito(client, cliente):
    r = client.post("/api/login", json={"email": "cliente@test.co", "password": "Goaltime123!"})
    assert r.status_code == 200
    cuerpo = r.get_json()
    assert cuerpo["rol"] == ROL_CLIENTE
    assert cuerpo["usuario"]["id"] == cliente.id
    assert cuerpo["access_token"]


def test_login_password_incorrecto_401(client, cliente):
    r = client.post("/api/login", json={"email": "cliente@test.co", "password": "incorrecta"})
    assert r.status_code == 401


def test_login_email_inexistente_401_mismo_mensaje(client, cliente):
    """No se revela si el email existe (HEUR-5)."""
    r = client.post("/api/login", json={"email": "nadie@test.co", "password": "Goaltime123!"})
    assert r.status_code == 401
    assert r.get_json()["error"]["mensaje"] == "Credenciales inválidas"


def test_login_cuenta_desactivada_403(app, cliente, client):
    cliente.activo = False
    db.session.commit()
    r = client.post("/api/login", json={"email": "cliente@test.co", "password": "Goaltime123!"})
    assert r.status_code == 403


def test_logout_requiere_token(client):
    assert client.post("/api/logout").status_code == 401


def test_logout_con_token_204(client, cliente):
    token = client.post(
        "/api/login", json={"email": "cliente@test.co", "password": "Goaltime123!"}
    ).get_json()["access_token"]
    r = client.post("/api/logout", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 204


def test_token_invalido_401(client):
    r = client.post("/api/logout", headers={"Authorization": "Bearer token-falso"})
    assert r.status_code == 401
    assert r.get_json()["error"]["codigo"] == 401


def test_password_se_guarda_hasheado(app, cliente):
    assert cliente.password_hash != "Goaltime123!"
    assert cliente.check_password("Goaltime123!")
    assert not cliente.check_password("otra-cosa")


def test_integridad_de_email_unico_en_base(app, cliente):
    """La restricción UNIQUE existe en el esquema, no sólo en el endpoint."""
    otro = Cliente(nombre="Otro", email=cliente.email, rol_id=cliente.rol_id, activo=True)
    db.session.add(otro)
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()

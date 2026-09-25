"""Pruebas de `POST /api/reservas` y `GET /api/mis-reservas` (spec.md 3.2).

Lo que se verifica aquí no es cada rama del código, sino las reglas de negocio:

* el `409` del slot ocupado lo impone la base de datos, no un `SELECT` previo;
* la reserva y su pago se crean juntos o no se crea nada;
* una reserva cancelada libera el slot (índice UNIQUE parcial);
* sólo un `cliente` reserva, y sólo ve sus propias reservas.
"""

from datetime import date, time, timedelta

import pytest
from sqlalchemy import event
from sqlalchemy.exc import IntegrityError

from extensions import db
from models import (
    ESTADO_CANCELADA,
    ESTADO_CONFIRMADA,
    ESTADO_PENDIENTE_PAGO,
    PAGO_APROBADO,
    PAGO_PENDIENTE,
    Cancha,
    Horario,
    Pago,
    Reserva,
)
from tests.conftest import _crear_cliente

PASSWORD = "Goaltime123!"


@pytest.fixture()
def token_cliente(client, cliente):
    return _login(client, cliente.email)


@pytest.fixture()
def token_dueno(client, dueno):
    return _login(client, dueno.email)


@pytest.fixture()
def token_admin(client, admin):
    return _login(client, admin.email)


@pytest.fixture()
def token_otro_cliente(client):
    return _login(client, _crear_cliente("otro@test.co", "cliente", "Otro Cliente").email)


def _login(client, email, password=PASSWORD):
    respuesta = client.post("/api/login", json={"email": email, "password": password})
    assert respuesta.status_code == 200, respuesta.get_json()
    return respuesta.get_json()["access_token"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _proximo_lunes(horario):
    """Primera fecha futura con el día del horario (el fixture usa `dia=0`, lunes)."""
    hoy = date.today()
    dias = (horario.dia - hoy.weekday()) % 7
    return (hoy + timedelta(days=dias or 7)).isoformat()


def _reservar(client, token, cancha_id, horario_id, fecha):
    return client.post(
        "/api/reservas",
        headers=_auth(token),
        json={"cancha_id": cancha_id, "horario_id": horario_id, "fecha": fecha},
    )


# --- autorización -------------------------------------------------------------


def test_reservar_sin_token_401(client):
    respuesta = client.post("/api/reservas", json={"cancha_id": 1, "horario_id": 1, "fecha": "2026-09-28"})

    assert respuesta.status_code == 401
    assert respuesta.get_json()["error"]["codigo"] == 401


def test_dueno_no_puede_reservar_403(client, token_dueno, cancha, horario):
    respuesta = _reservar(client, token_dueno, cancha.id, horario.id, _proximo_lunes(horario))

    assert respuesta.status_code == 403


def test_admin_no_puede_reservar_403(client, token_admin, cancha, horario):
    respuesta = _reservar(client, token_admin, cancha.id, horario.id, _proximo_lunes(horario))

    assert respuesta.status_code == 403
    assert db.session.execute(db.select(db.func.count(Reserva.id))).scalar_one() == 0


# --- validación ---------------------------------------------------------------


@pytest.mark.parametrize(
    "cuerpo",
    [
        {},
        {"cancha_id": 1},
        {"cancha_id": 1, "horario_id": 1},
        {"cancha_id": "x", "horario_id": 1, "fecha": "2026-09-28"},
        {"cancha_id": 1, "horario_id": 1, "fecha": "28-09-2026"},
        {"cancha_id": 1, "horario_id": 1, "fecha": "2026-9-28"},
    ],
)
def test_body_incompleto_o_fecha_mal_formada_400(client, token_cliente, cuerpo):
    respuesta = client.post("/api/reservas", headers=_auth(token_cliente), json=cuerpo)

    assert respuesta.status_code == 400


def test_cancha_inexistente_404(client, token_cliente, horario):
    respuesta = _reservar(client, token_cliente, 999, horario.id, _proximo_lunes(horario))

    assert respuesta.status_code == 404


def test_cancha_inactiva_404(client, token_cliente, cancha, horario):
    cancha.activo = False
    db.session.commit()

    respuesta = _reservar(client, token_cliente, cancha.id, horario.id, _proximo_lunes(horario))

    assert respuesta.status_code == 404


def test_horario_inexistente_404(client, token_cliente, cancha):
    respuesta = _reservar(client, token_cliente, cancha.id, 999, "2026-09-28")

    assert respuesta.status_code == 404


def test_horario_de_otra_cancha_422(client, token_cliente, dueno, cancha, horario):
    otra = Cancha(nombre="Otra cancha", ubicacion="Cra 9 #9-9", dueno_id=dueno.id)
    db.session.add(otra)
    db.session.flush()
    ajeno = Horario(cancha_id=otra.id, dia=0, hora_inicio=time(6, 0), hora_fin=time(8, 0), tarifa=50000)
    db.session.add(ajeno)
    db.session.flush()

    respuesta = _reservar(client, token_cliente, cancha.id, ajeno.id, _proximo_lunes(horario))

    assert respuesta.status_code == 422


def test_dia_sin_horario_422(client, token_cliente, cancha, horario):
    """El slot del fixture es de lunes; un martes la cancha no tiene horario."""
    martes = date.fromisoformat(_proximo_lunes(horario)) + timedelta(days=1)

    respuesta = _reservar(client, token_cliente, cancha.id, horario.id, martes.isoformat())

    assert respuesta.status_code == 422


def test_fecha_pasada_422(client, token_cliente, cancha, horario):
    respuesta = _reservar(client, token_cliente, cancha.id, horario.id, "2020-01-06")

    assert respuesta.status_code == 422


def test_slot_transcurrido_hoy_422(client, token_cliente, cancha):
    """Un horario de hoy cuya hora de inicio ya pasó se rechaza igual que en
    `/api/disponibilidad` (motivo `transcurrido`)."""
    slot = Horario(
        cancha_id=cancha.id,
        dia=date.today().weekday(),
        hora_inicio=time(0, 1),
        hora_fin=time(0, 2),
        tarifa=30000,
    )
    db.session.add(slot)
    db.session.flush()

    respuesta = _reservar(client, token_cliente, cancha.id, slot.id, date.today().isoformat())

    assert respuesta.status_code == 422
    assert "disponible" in respuesta.get_json()["error"]["mensaje"]


# --- creación y atomicidad ----------------------------------------------------


def test_reserva_exitosa_201_crea_reserva_y_pago(client, token_cliente, cliente, cancha, horario):
    fecha = _proximo_lunes(horario)
    respuesta = _reservar(client, token_cliente, cancha.id, horario.id, fecha)
    cuerpo = respuesta.get_json()

    assert respuesta.status_code == 201
    assert cuerpo["estado"] == ESTADO_PENDIENTE_PAGO
    # El monto lo decide el backend a partir de `horario.tarifa`.
    assert cuerpo["pago"]["monto"] == 60000.0
    assert cuerpo["pago"]["estado"] == PAGO_PENDIENTE
    assert cuerpo["pago"]["metodo"] == "mock"

    reserva = db.session.get(Reserva, cuerpo["reserva_id"])
    assert reserva.cliente_id == cliente.id
    assert reserva.cancha_id == cancha.id
    assert reserva.horario_id == horario.id
    assert reserva.fecha == date.fromisoformat(fecha)
    assert reserva.pago.id == cuerpo["pago"]["id"]


def test_el_cliente_no_puede_fijar_monto_ni_estado(client, token_cliente, cancha, horario):
    respuesta = client.post(
        "/api/reservas",
        headers=_auth(token_cliente),
        json={
            "cancha_id": cancha.id,
            "horario_id": horario.id,
            "fecha": _proximo_lunes(horario),
            "monto": 1,
            "estado": ESTADO_CONFIRMADA,
        },
    )

    assert respuesta.status_code == 201
    pago = db.session.get(Pago, respuesta.get_json()["pago"]["id"])
    assert float(pago.monto) == 60000.0
    assert pago.estado == PAGO_PENDIENTE
    assert db.session.get(Reserva, respuesta.get_json()["reserva_id"]).estado == ESTADO_PENDIENTE_PAGO


def test_slot_ocupado_409(client, token_cliente, token_otro_cliente, cancha, horario):
    fecha = _proximo_lunes(horario)

    primera = _reservar(client, token_cliente, cancha.id, horario.id, fecha)
    segunda = _reservar(client, token_otro_cliente, cancha.id, horario.id, fecha)

    assert primera.status_code == 201
    assert segunda.status_code == 409
    assert segunda.get_json()["error"]["codigo"] == 409
    assert db.session.execute(db.select(db.func.count(Reserva.id))).scalar_one() == 1


def test_el_mismo_cliente_tampoco_puede_duplicar_el_slot(client, token_cliente, cancha, horario):
    fecha = _proximo_lunes(horario)

    assert _reservar(client, token_cliente, cancha.id, horario.id, fecha).status_code == 201
    assert _reservar(client, token_cliente, cancha.id, horario.id, fecha).status_code == 409


def test_reserva_cancelada_libera_el_slot(client, token_cliente, token_otro_cliente, cancha, horario):
    """El índice es parcial: al cancelar, el slot vuelve a estar disponible."""
    fecha = _proximo_lunes(horario)
    primera = _reservar(client, token_cliente, cancha.id, horario.id, fecha)
    assert primera.status_code == 201

    reserva = db.session.get(Reserva, primera.get_json()["reserva_id"])
    reserva.estado = ESTADO_CANCELADA
    db.session.commit()

    segunda = _reservar(client, token_otro_cliente, cancha.id, horario.id, fecha)

    assert segunda.status_code == 201
    # El histórico se conserva: cancelar no borra la fila.
    assert db.session.execute(db.select(db.func.count(Reserva.id))).scalar_one() == 2


def test_transaccion_atomica_no_deja_reserva_sin_pago(client, token_cliente, cancha, horario):
    """Si el INSERT del pago falla, la reserva tampoco queda persistida."""

    def _reventar(mapper, connection, target):
        raise IntegrityError("INSERT INTO pago", {}, Exception("pago rechazado"))

    event.listen(Pago, "before_insert", _reventar)
    try:
        respuesta = _reservar(client, token_cliente, cancha.id, horario.id, _proximo_lunes(horario))
    finally:
        event.remove(Pago, "before_insert", _reventar)

    assert respuesta.status_code == 500
    assert db.session.execute(db.select(db.func.count(Reserva.id))).scalar_one() == 0
    assert db.session.execute(db.select(db.func.count(Pago.id))).scalar_one() == 0

    # El rollback no dejó nada a medias: el slot sigue reservable.
    assert _reservar(client, token_cliente, cancha.id, horario.id, _proximo_lunes(horario)).status_code == 201


# --- mis-reservas -------------------------------------------------------------


def test_mis_reservas_solo_muestra_las_propias(client, token_cliente, token_otro_cliente, cancha, horario):
    _reservar(client, token_cliente, cancha.id, horario.id, _proximo_lunes(horario))

    propias = client.get("/api/mis-reservas", headers=_auth(token_cliente))
    ajenas = client.get("/api/mis-reservas", headers=_auth(token_otro_cliente))

    assert propias.status_code == 200
    assert len(propias.get_json()) == 1
    assert propias.get_json()[0]["cancha"]["id"] == cancha.id
    assert propias.get_json()[0]["horario"]["tarifa"] == 60000.0
    assert propias.get_json()[0]["pago"]["estado"] == PAGO_PENDIENTE
    assert ajenas.get_json() == []


def test_mis_reservas_ordenadas_por_fecha_descendente(client, token_cliente, cancha, horario):
    fechas = []
    for offset in (7, 14, 21):
        dia = date.fromisoformat(_proximo_lunes(horario)) + timedelta(days=offset)
        fechas.append(dia)
        assert _reservar(client, token_cliente, cancha.id, horario.id, dia.isoformat()).status_code == 201

    respuesta = client.get("/api/mis-reservas", headers=_auth(token_cliente))
    orden = [item["fecha"] for item in respuesta.get_json()]

    assert orden == [dia.isoformat() for dia in sorted(fechas, reverse=True)]
    assert len(orden) == 3


def test_mis_reservas_refleja_el_pago_confirmado(client, token_cliente, cancha, horario):
    creada = _reservar(client, token_cliente, cancha.id, horario.id, _proximo_lunes(horario))
    pago_id = creada.get_json()["pago"]["id"]

    simulado = client.post(
        f"/api/pagos/{pago_id}/simular",
        headers=_auth(token_cliente),
        json={"resultado": "aprobado"},
    )
    assert simulado.status_code == 200

    reserva = client.get("/api/mis-reservas", headers=_auth(token_cliente)).get_json()[0]
    assert reserva["estado"] == ESTADO_CONFIRMADA
    assert reserva["pago"]["estado"] == PAGO_APROBADO


def test_mis_reservas_403_para_dueno(client, token_dueno):
    respuesta = client.get("/api/mis-reservas", headers=_auth(token_dueno))

    assert respuesta.status_code == 403


def test_mis_reservas_sin_token_401(client):
    assert client.get("/api/mis-reservas").status_code == 401

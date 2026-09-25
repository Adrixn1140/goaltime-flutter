"""Pruebas de pagos (spec.md 3.3).

Tres cosas se comprueban aquí:

* **Quién paga**: el cliente que reservó (o el admin), nunca el dueño de la cancha ni
  un tercero.
* **Idempotencia**: la transición `pendiente → aprobado|rechazado` se aplica una sola
  vez. Un evento repetido o fuera de orden responde `200` sin reescribir, y una firma
  inválida nunca llega a tocar un pago.
* **La firma manda**: el webhook se prueba con una firma HMAC real, calculada con el
  mismo secreto que la pasarela, sin necesidad de red.
"""

import hashlib
import hmac
import json
import time as reloj
from datetime import date, timedelta

import pytest
from flask import current_app

from extensions import db
from models import (
    ESTADO_CONFIRMADA,
    ESTADO_PENDIENTE_PAGO,
    PAGO_APROBADO,
    PAGO_PENDIENTE,
    PAGO_RECHAZADO,
    Cliente,
    Pago,
    Reserva,
)
from pasarelas.base import EventoPago, FirmaInvalida
from tests.conftest import _crear_cliente

PASSWORD = "Goaltime123!"
SECRETO_WEBHOOK = "whsec_test_123"


@pytest.fixture()
def token_cliente(client, cliente):
    return _login(client, cliente.email)


@pytest.fixture()
def token_otro_cliente(client):
    return _login(client, _crear_cliente("otro@test.co", "cliente", "Otro Cliente").email)


@pytest.fixture()
def token_dueno(client, dueno):
    return _login(client, dueno.email)


@pytest.fixture()
def token_admin(client, admin):
    return _login(client, admin.email)


@pytest.fixture()
def pasarela_stripe(app):
    """Activa Stripe con claves de mentira: verificar firmas no requiere red."""
    anteriores = {clave: app.config[clave] for clave in
                  ("PAGADORA", "STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET")}
    app.config.update(
        PAGADORA="stripe",
        STRIPE_SECRET_KEY="sk_test_falsa",
        STRIPE_WEBHOOK_SECRET=SECRETO_WEBHOOK,
    )
    yield
    app.config.update(anteriores)


@pytest.fixture()
def reserva_pendiente(client, token_cliente, cancha, horario):
    """Reserva creada por la API: devuelve `{reserva_id, pago_id}`."""
    hoy = date.today()
    fecha = (hoy + timedelta(days=(horario.dia - hoy.weekday()) % 7 or 7)).isoformat()
    respuesta = client.post(
        "/api/reservas",
        headers=_auth(token_cliente),
        json={"cancha_id": cancha.id, "horario_id": horario.id, "fecha": fecha},
    )
    assert respuesta.status_code == 201, respuesta.get_json()
    cuerpo = respuesta.get_json()
    return {"reserva_id": cuerpo["reserva_id"], "pago_id": cuerpo["pago"]["id"]}


def _login(client, email, password=PASSWORD):
    respuesta = client.post("/api/login", json={"email": email, "password": password})
    assert respuesta.status_code == 200, respuesta.get_json()
    return respuesta.get_json()["access_token"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _firmar(cuerpo, secreto=SECRETO_WEBHOOK, desfase=0):
    """Firma `Stripe-Signature` válida (t=<ts>,v1=<hmac>), como la que envía Stripe."""
    marca = int(reloj.time()) + desfase
    texto = cuerpo.decode() if isinstance(cuerpo, (bytes, bytearray)) else cuerpo
    firma = hmac.new(secreto.encode(), f"{marca}.{texto}".encode(), hashlib.sha256).hexdigest()
    return {"Stripe-Signature": f"t={marca},v1={firma}"}


def _evento(tipo, pago_id, referencia="cs_test_1"):
    return json.dumps(
        {
            "id": "evt_test_1",
            "type": tipo,
            "data": {"object": {"id": referencia, "metadata": {"pago_id": str(pago_id)}}},
        }
    ).encode()


# --- checkout -----------------------------------------------------------------


def test_checkout_sin_token_401(client, reserva_pendiente):
    respuesta = client.post("/api/pagos/checkout", json={"reserva_id": reserva_pendiente["reserva_id"]})

    assert respuesta.status_code == 401


@pytest.mark.parametrize("cuerpo", [{}, {"reserva_id": "abc"}, {"otro": 1}])
def test_checkout_body_invalido_400(client, token_cliente, cuerpo):
    respuesta = client.post("/api/pagos/checkout", headers=_auth(token_cliente), json=cuerpo)

    assert respuesta.status_code == 400


def test_checkout_reserva_inexistente_404(client, token_cliente):
    respuesta = client.post("/api/pagos/checkout", headers=_auth(token_cliente), json={"reserva_id": 999})

    assert respuesta.status_code == 404


def test_checkout_de_otra_reserva_403(client, token_otro_cliente, reserva_pendiente):
    respuesta = client.post(
        "/api/pagos/checkout",
        headers=_auth(token_otro_cliente),
        json={"reserva_id": reserva_pendiente["reserva_id"]},
    )

    assert respuesta.status_code == 403
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_checkout_del_dueno_de_la_cancha_403(client, token_dueno, reserva_pendiente):
    """El dueño administra las canchas, pero no paga las reservas de sus clientes."""
    respuesta = client.post(
        "/api/pagos/checkout",
        headers=_auth(token_dueno),
        json={"reserva_id": reserva_pendiente["reserva_id"]},
    )

    assert respuesta.status_code == 403


def test_checkout_exitoso_201_devuelve_url_de_la_pasarela(client, token_cliente, reserva_pendiente):
    respuesta = client.post(
        "/api/pagos/checkout",
        headers=_auth(token_cliente),
        json={"reserva_id": reserva_pendiente["reserva_id"]},
    )
    cuerpo = respuesta.get_json()

    assert respuesta.status_code == 201
    assert cuerpo["pago_id"] == reserva_pendiente["pago_id"]
    # La URL la construye la pasarela a partir del pago y del monto que fijó el backend.
    assert str(reserva_pendiente["pago_id"]) in cuerpo["checkout_url"]
    assert "60000" in cuerpo["checkout_url"]


def test_checkout_de_reserva_confirmada_409(client, token_cliente, reserva_pendiente):
    _simular(client, token_cliente, reserva_pendiente["pago_id"], "aprobado")

    respuesta = client.post(
        "/api/pagos/checkout",
        headers=_auth(token_cliente),
        json={"reserva_id": reserva_pendiente["reserva_id"]},
    )

    assert respuesta.status_code == 409


def test_checkout_tras_rechazo_permite_reintento(client, token_cliente, reserva_pendiente):
    """Un rechazo devuelve la reserva a `pendiente_pago`: se puede volver a pagar."""
    _simular(client, token_cliente, reserva_pendiente["pago_id"], "rechazado")

    respuesta = client.post(
        "/api/pagos/checkout",
        headers=_auth(token_cliente),
        json={"reserva_id": reserva_pendiente["reserva_id"]},
    )

    assert respuesta.status_code == 201


def test_admin_puede_abrir_el_checkout(client, token_admin, reserva_pendiente):
    respuesta = client.post(
        "/api/pagos/checkout",
        headers=_auth(token_admin),
        json={"reserva_id": reserva_pendiente["reserva_id"]},
    )

    assert respuesta.status_code == 201


# --- simulación (PAGADORA=mock) ----------------------------------------------


def test_simular_sin_token_401(client, reserva_pendiente):
    respuesta = client.post(f"/api/pagos/{reserva_pendiente['pago_id']}/simular", json={"resultado": "aprobado"})

    assert respuesta.status_code == 401


def test_simular_403_con_pasarela_stripe(client, app, token_cliente, reserva_pendiente, pasarela_stripe):
    respuesta = client.post(
        f"/api/pagos/{reserva_pendiente['pago_id']}/simular",
        headers=_auth(token_cliente),
        json={"resultado": "aprobado"},
    )

    assert respuesta.status_code == 403
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_simular_pago_inexistente_404(client, token_cliente):
    respuesta = client.post("/api/pagos/999/simular", headers=_auth(token_cliente), json={"resultado": "aprobado"})

    assert respuesta.status_code == 404


def test_simular_pago_de_otro_cliente_403(client, token_otro_cliente, reserva_pendiente):
    respuesta = client.post(
        f"/api/pagos/{reserva_pendiente['pago_id']}/simular",
        headers=_auth(token_otro_cliente),
        json={"resultado": "aprobado"},
    )

    assert respuesta.status_code == 403


@pytest.mark.parametrize("cuerpo", [{}, {"resultado": "quizá"}, {"resultado": ""}])
def test_simular_resultado_invalido_400(client, token_cliente, reserva_pendiente, cuerpo):
    respuesta = client.post(
        f"/api/pagos/{reserva_pendiente['pago_id']}/simular",
        headers=_auth(token_cliente),
        json=cuerpo,
    )

    assert respuesta.status_code == 400
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_simular_aprobado_confirma_la_reserva(client, token_cliente, reserva_pendiente):
    respuesta = _simular(client, token_cliente, reserva_pendiente["pago_id"], "aprobado")
    cuerpo = respuesta.get_json()

    assert respuesta.status_code == 200
    assert cuerpo["aplicado"] is True
    assert cuerpo["pago"]["estado"] == PAGO_APROBADO
    assert cuerpo["estado_reserva"] == ESTADO_CONFIRMADA
    assert db.session.get(Reserva, reserva_pendiente["reserva_id"]).estado == ESTADO_CONFIRMADA


def test_simular_rechazado_devuelve_la_reserva_a_pendiente_pago(client, token_cliente, reserva_pendiente):
    respuesta = _simular(client, token_cliente, reserva_pendiente["pago_id"], "rechazado")
    cuerpo = respuesta.get_json()

    assert respuesta.status_code == 200
    assert cuerpo["aplicado"] is True
    assert cuerpo["pago"]["estado"] == PAGO_RECHAZADO
    assert cuerpo["estado_reserva"] == ESTADO_PENDIENTE_PAGO


def test_simular_es_idempotente(client, token_cliente, reserva_pendiente):
    primera = _simular(client, token_cliente, reserva_pendiente["pago_id"], "aprobado")
    segunda = _simular(client, token_cliente, reserva_pendiente["pago_id"], "aprobado")

    assert primera.get_json()["aplicado"] is True
    # El segundo intento responde 200 pero no reescribe nada.
    assert segunda.status_code == 200
    assert segunda.get_json()["aplicado"] is False
    assert segunda.get_json()["pago"]["estado"] == PAGO_APROBADO


def test_evento_tardio_no_revierte_un_pago_aprobado(client, token_cliente, reserva_pendiente):
    """Evento fuera de orden: `expired` después de `completed` no degrada el pago."""
    _simular(client, token_cliente, reserva_pendiente["pago_id"], "aprobado")

    respuesta = _simular(client, token_cliente, reserva_pendiente["pago_id"], "rechazado")

    assert respuesta.get_json()["aplicado"] is False
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_APROBADO
    assert db.session.get(Reserva, reserva_pendiente["reserva_id"]).estado == ESTADO_CONFIRMADA


def _simular(client, token, pago_id, resultado):
    return client.post(
        f"/api/pagos/{pago_id}/simular", headers=_auth(token), json={"resultado": resultado}
    )


# --- consulta del pago --------------------------------------------------------


def test_ver_pago_propio_200(client, token_cliente, reserva_pendiente):
    respuesta = client.get(f"/api/pagos/{reserva_pendiente['pago_id']}", headers=_auth(token_cliente))
    cuerpo = respuesta.get_json()

    assert respuesta.status_code == 200
    assert cuerpo["id"] == reserva_pendiente["pago_id"]
    assert cuerpo["reserva_id"] == reserva_pendiente["reserva_id"]
    assert cuerpo["monto"] == 60000.0
    assert cuerpo["estado"] == PAGO_PENDIENTE


def test_ver_pago_de_otro_cliente_403(client, token_otro_cliente, reserva_pendiente):
    respuesta = client.get(f"/api/pagos/{reserva_pendiente['pago_id']}", headers=_auth(token_otro_cliente))

    assert respuesta.status_code == 403


def test_ver_pago_como_admin_200(client, token_admin, reserva_pendiente):
    respuesta = client.get(f"/api/pagos/{reserva_pendiente['pago_id']}", headers=_auth(token_admin))

    assert respuesta.status_code == 200


def test_ver_pago_inexistente_404(client, token_cliente):
    assert client.get("/api/pagos/999", headers=_auth(token_cliente)).status_code == 404


def test_ver_pago_sin_token_401(client, reserva_pendiente):
    assert client.get(f"/api/pagos/{reserva_pendiente['pago_id']}").status_code == 401


# --- webhook ------------------------------------------------------------------


def test_webhook_en_modo_mock_400(client, reserva_pendiente):
    """La pasarela simulada no recibe webhooks: nada puede confirmarse por esa vía."""
    respuesta = client.post("/api/pagos/webhook", data=_evento("checkout.session.completed", reserva_pendiente["pago_id"]))

    assert respuesta.status_code == 400
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_webhook_exige_cabecera_de_firma(client, pasarela_stripe, reserva_pendiente):
    respuesta = client.post("/api/pagos/webhook", data=_evento("checkout.session.completed", reserva_pendiente["pago_id"]))

    assert respuesta.status_code == 400
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_webhook_con_firma_invalida_400(client, pasarela_stripe, reserva_pendiente):
    cuerpo = _evento("checkout.session.completed", reserva_pendiente["pago_id"])

    respuesta = client.post(
        "/api/pagos/webhook",
        data=cuerpo,
        headers={"Stripe-Signature": f"t={int(reloj.time())},v1=deadbeef"},
    )

    assert respuesta.status_code == 400
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_webhook_con_cuerpo_alterado_400(client, pasarela_stripe, reserva_pendiente):
    """La firma cubre el cuerpo: alterar `pago_id` invalida la firma."""
    cuerpo = _evento("checkout.session.completed", reserva_pendiente["pago_id"])
    cabeceras = _firmar(cuerpo)
    alterado = _evento("checkout.session.completed", 999999)

    respuesta = client.post("/api/pagos/webhook", data=alterado, headers=cabeceras)

    assert respuesta.status_code == 400


def test_webhook_fuera_de_la_tolerancia_400(client, pasarela_stripe, reserva_pendiente):
    """La tolerancia por defecto es de 5 minutos: un evento viejo se rechaza."""
    cuerpo = _evento("checkout.session.completed", reserva_pendiente["pago_id"])

    respuesta = client.post(
        "/api/pagos/webhook", data=cuerpo, headers=_firmar(cuerpo, desfase=-600)
    )

    assert respuesta.status_code == 400
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_webhook_firmado_aprueba_el_pago(client, pasarela_stripe, reserva_pendiente):
    cuerpo = _evento("checkout.session.completed", reserva_pendiente["pago_id"])

    respuesta = client.post("/api/pagos/webhook", data=cuerpo, headers=_firmar(cuerpo))
    datos = respuesta.get_json()

    assert respuesta.status_code == 200
    assert datos["aplicado"] is True
    assert datos["pago"]["estado"] == PAGO_APROBADO
    assert datos["estado_reserva"] == ESTADO_CONFIRMADA
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).gateway_ref == "cs_test_1"


def test_webhook_expirado_rechaza_y_reabre_la_reserva(client, pasarela_stripe, reserva_pendiente):
    cuerpo = _evento("checkout.session.expired", reserva_pendiente["pago_id"], referencia="cs_test_2")

    respuesta = client.post("/api/pagos/webhook", data=cuerpo, headers=_firmar(cuerpo))
    datos = respuesta.get_json()

    assert datos["pago"]["estado"] == PAGO_RECHAZADO
    assert datos["estado_reserva"] == ESTADO_PENDIENTE_PAGO


def test_webhook_repetido_es_idempotente(client, pasarela_stripe, reserva_pendiente):
    cuerpo = _evento("checkout.session.completed", reserva_pendiente["pago_id"])
    cabeceras = _firmar(cuerpo)

    primera = client.post("/api/pagos/webhook", data=cuerpo, headers=cabeceras)
    segunda = client.post("/api/pagos/webhook", data=cuerpo, headers=cabeceras)

    assert primera.get_json()["aplicado"] is True
    assert segunda.status_code == 200
    assert segunda.get_json()["aplicado"] is False
    assert segunda.get_json()["pago"]["estado"] == PAGO_APROBADO


def test_webhook_sin_metadata_pago_id_400(client, pasarela_stripe, reserva_pendiente):
    cuerpo = json.dumps(
        {
            "id": "evt_test_2",
            "type": "checkout.session.completed",
            "data": {"object": {"id": "cs_test_1", "metadata": {}}},
        }
    ).encode()

    respuesta = client.post("/api/pagos/webhook", data=cuerpo, headers=_firmar(cuerpo))

    assert respuesta.status_code == 400


def test_webhook_de_pago_desconocido_400(client, pasarela_stripe, reserva_pendiente):
    cuerpo = _evento("checkout.session.completed", 987654)

    respuesta = client.post("/api/pagos/webhook", data=cuerpo, headers=_firmar(cuerpo))

    assert respuesta.status_code == 400


def test_webhook_de_otro_tipo_se_ignora(client, pasarela_stripe, reserva_pendiente):
    """Evento auténtico que no nos interesa: 200 sin tocar el pago, para que la
    pasarela deje de reintentarlo."""
    cuerpo = _evento("invoice.paid", reserva_pendiente["pago_id"])

    respuesta = client.post("/api/pagos/webhook", data=cuerpo, headers=_firmar(cuerpo))

    assert respuesta.status_code == 200
    assert respuesta.get_json()["aplicado"] is False
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_webhook_limita_el_tamano_del_cuerpo(client, pasarela_stripe, reserva_pendiente):
    """`MAX_CONTENT_LENGTH` corta antes de que el body llegue a la verificación."""
    enorme = b"x" * (current_app.config["MAX_CONTENT_LENGTH"] + 1)

    respuesta = client.post("/api/pagos/webhook", data=enorme, headers=_firmar(enorme))

    assert respuesta.status_code == 413
    assert db.session.get(Pago, reserva_pendiente["pago_id"]).estado == PAGO_PENDIENTE


def test_webhook_usa_el_pago_del_metadata_no_el_del_correo(client, pasarela_stripe, reserva_pendiente, cliente):
    """`cliente_email` es Engaña: el pago se resuelve por `metadata.pago_id`."""
    cuerpo = json.dumps(
        {
            "id": "evt_test_3",
            "type": "checkout.session.completed",
            "data": {
                "object": {
                    "id": "cs_test_3",
                    "metadata": {"pago_id": str(reserva_pendiente["pago_id"])},
                    "customer_email": "victima@otro.co",
                    "amount_total": 1,
                }
            },
        }
    ).encode()

    respuesta = client.post("/api/pagos/webhook", data=cuerpo, headers=_firmar(cuerpo))

    assert respuesta.get_json()["aplicado"] is True
    # El monto del evento no cambia lo que el backend calculó desde `horario.tarifa`.
    assert float(db.session.get(Pago, reserva_pendiente["pago_id"]).monto) == 60000.0


# --- la pasarela es intercambiable -------------------------------------------


def test_pasarela_se_elige_segun_config(app, cliente):
    """El blueprint no sabe qué pasarela hay: la resuelve por `PAGADORA`."""
    from pasarelas import obtener_pasarela
    from pasarelas.mock_pasarela import MockPasarela

    with app.app_context():
        assert isinstance(obtener_pasarela(), MockPasarela)
        app.config.update(PAGADORA="stripe", STRIPE_SECRET_KEY="sk_test_falsa")
        from pasarelas.stripe_pasarela import StripePasarela

        assert isinstance(obtener_pasarela(), StripePasarela)
        app.config.update(PAGADORA="inventada")
        with pytest.raises(RuntimeError):
            obtener_pasarela()


def test_mock_no_acepta_webhooks(client):
    from pasarelas.mock_pasarela import MockPasarela

    with client.application.app_context(), pytest.raises(FirmaInvalida):
        MockPasarela("http://x").verificar_evento(b"{}", {})


def test_evento_de_pasarela_conserva_el_pago_id():
    from pasarelas.mock_pasarela import MockPasarela

    evento = MockPasarela("http://x").evento(7, "rechazado")

    assert isinstance(evento, EventoPago)
    assert (evento.pago_id, evento.tipo) == (7, "rechazado")


def test_no_se_puede_crear_otro_cliente_desde_el_token(client, token_cliente, reserva_pendiente):
    """El cliente de la reserva sale del token, no del cuerpo."""
    antes = db.session.execute(db.select(db.func.count(Cliente.id))).scalar_one()

    respuesta = client.post(
        "/api/pagos/checkout",
        headers=_auth(token_cliente),
        json={"reserva_id": reserva_pendiente["reserva_id"], "cliente_id": 999, "monto": 1},
    )
    cuerpo = respuesta.get_json()

    assert respuesta.status_code == 201
    pago = db.session.get(Pago, cuerpo["pago_id"])
    assert db.session.get(Reserva, pago.reserva_id).cliente_id != 999
    assert float(pago.monto) == 60000.0
    assert db.session.execute(db.select(db.func.count(Cliente.id))).scalar_one() == antes

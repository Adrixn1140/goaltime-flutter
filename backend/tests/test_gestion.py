"""Pruebas de la gestión del dueño: `/api/gestion/*` (spec.md 3.4).

El módulo tiene tres reglas que valen más que sus endpoints, y por eso los tests están
organizados por regla y no por método:

* **Aislamiento.** Un dueño no ve ni toca canchas ajenas, y el código de respuesta es
  `404` —no `403`— para que el `404` no confirme que la cancha ajena existe. El `403`
  queda para el rol insuficiente.
* **Integridad del calendario.** Los horarios de una cancha no se solapan entre sí, y
  un horario con reservas no se mueve ni se borra, canceladas incluidas.
* **La reserva es del dueño.** Confirmar exige un pago aprobado; cancelar libera el slot.
"""

from datetime import date, time, timedelta

import pytest

import limites
from extensions import db
from models import (
    ESTADO_CANCELADA,
    ESTADO_CONFIRMADA,
    ESTADO_PENDIENTE_PAGO,
    PAGO_APROBADO,
    PAGO_PENDIENTE,
    PAGO_RECHAZADO,
    Cancha,
    Horario,
    Pago,
    Reserva,
)

PASSWORD = "Goaltime123!"


@pytest.fixture()
def token_dueno(client, dueno):
    return _login(client, dueno.email)


@pytest.fixture()
def token_otro_dueno(client, dueno_otro):
    return _login(client, dueno_otro.email)


@pytest.fixture()
def token_admin(client, admin):
    return _login(client, admin.email)


@pytest.fixture()
def token_cliente(client, cliente):
    return _login(client, cliente.email)


@pytest.fixture()
def cancha_ajena(app, dueno_otro):
    cancha = Cancha(nombre="Cancha Ajena", ubicacion="Cra 9 #9-9", dueno_id=dueno_otro.id)
    db.session.add(cancha)
    db.session.commit()
    return cancha


def _login(client, email, password=PASSWORD):
    respuesta = client.post("/api/login", json={"email": email, "password": password})
    assert respuesta.status_code == 200, respuesta.get_json()
    return respuesta.get_json()["access_token"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _horario(app, cancha, dia=0, inicio=time(8, 0), fin=time(10, 0), tarifa=60000):
    horario = Horario(
        cancha_id=cancha.id, dia=dia, hora_inicio=inicio, hora_fin=fin, tarifa=tarifa
    )
    db.session.add(horario)
    db.session.commit()
    return horario


def _reserva(
    app, cliente, cancha, horario, estado=ESTADO_PENDIENTE_PAGO, pago=None, fecha=None
):
    """Reserva y pago creados directamente, para no depender del checkout en cada test.

    `pago=None` significa «sin pago»; un estado de pago crea el pago con ese valor. La
    fecha admite texto ISO para poder reutilizar la que la API ya validó.
    """
    fecha = date.fromisoformat(fecha) if isinstance(fecha, str) else fecha or date.today() + timedelta(days=1)
    reserva = Reserva(cliente_id=cliente.id, cancha_id=cancha.id, horario_id=horario.id, fecha=fecha)
    db.session.add(reserva)
    db.session.commit()
    if pago is not None:
        db.session.add(
            Pago(
                reserva_id=reserva.id,
                monto=horario.tarifa,
                estado=pago,
                gateway_ref=f"ref-{reserva.id}",
            )
        )
        db.session.commit()
    reserva.estado = estado
    db.session.commit()
    return reserva


def _proxima_fecha_lunes():
    """El fixture usa `dia=0` (lunes); devuelve el próximo lunes como `YYYY-MM-DD`."""
    hoy = date.today()
    return (hoy + timedelta(days=(7 - hoy.weekday()) % 7 or 7)).isoformat()


# --- aislamiento y rol ---------------------------------------------------------


def test_cliente_recibe_403_al_entrar_en_gestion(client, token_cliente):
    respuesta = client.get("/api/gestion/canchas", headers=_auth(token_cliente))
    assert respuesta.status_code == 403


def test_sin_token_recibe_401(client):
    assert client.get("/api/gestion/canchas").status_code == 401


def test_token_valido_de_usuario_borrado_recibe_401(client, app, dueno):
    """El token sigue firmado, pero el usuario ya no está: `401`, igual que en el resto
    de la API. La gestión no puede ser la excepción."""
    token = _login(client, dueno.email)
    db.session.delete(dueno)
    db.session.commit()
    respuesta = client.get("/api/gestion/canchas", headers=_auth(token))
    assert respuesta.status_code == 401


def test_dueno_solo_ve_sus_canchas(client, app, token_dueno, cancha, cancha_ajena):
    respuesta = client.get("/api/gestion/canchas", headers=_auth(token_dueno))
    assert respuesta.status_code == 200
    nombres = [c["nombre"] for c in respuesta.get_json()]
    assert nombres == ["Cancha Prueba"]


def test_admin_ve_las_canchas_de_todos(client, app, token_admin, cancha, cancha_ajena):
    respuesta = client.get("/api/gestion/canchas", headers=_auth(token_admin))
    assert respuesta.status_code == 200
    assert {c["nombre"] for c in respuesta.get_json()} == {"Cancha Prueba", "Cancha Ajena"}


def test_admin_tambien_ve_las_canchas_inactivas(client, app, token_admin, cancha, cancha_ajena):
    cancha_ajena.activo = False
    db.session.commit()
    respuesta = client.get("/api/gestion/canchas", headers=_auth(token_admin))
    assert respuesta.status_code == 200
    inactivas = [c for c in respuesta.get_json() if not c["activo"]]
    assert [c["nombre"] for c in inactivas] == ["Cancha Ajena"]


@pytest.mark.parametrize(
    "metodo,ruta,cuerpo",
    [
        ("patch", "/api/gestion/canchas/{id}", {"nombre": "Robada"}),
        ("delete", "/api/gestion/canchas/{id}", None),
        ("get", "/api/gestion/canchas/{id}/horarios", None),
        ("get", "/api/gestion/canchas/{id}/reservas", None),
    ],
)
def test_cancha_ajena_responde_404_y_no_403(client, app, token_dueno, cancha_ajena, metodo, ruta, cuerpo):
    """`403` confirmaría que el id existe; `404` no revela nada."""
    respuesta = getattr(client, metodo)(
        ruta.format(id=cancha_ajena.id), json=cuerpo, headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 404


def test_cancha_inexistente_tambien_responde_404(client, app, token_dueno):
    respuesta = client.patch(
        "/api/gestion/canchas/9999", json={"nombre": "X"}, headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 404


def test_no_puede_tocar_horarios_de_otra_cancha(client, app, token_dueno, cancha_ajena):
    horario = _horario(app, cancha_ajena)
    respuesta = client.delete(
        f"/api/gestion/canchas/{cancha_ajena.id}/horarios/{horario.id}",
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 404


def test_no_puede_tocar_una_reserva_ajena(
    client, app, token_dueno, cancha_ajena, cliente
):
    horario = _horario(app, cancha_ajena)
    reserva = _reserva(app, cliente, cancha_ajena, horario)
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": "cancelar"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 404
    assert db.session.get(Reserva, reserva.id).estado == ESTADO_PENDIENTE_PAGO


# --- canchas -------------------------------------------------------------------


def test_crear_cancha_toma_el_dueno_del_token(client, app, dueno, token_dueno):
    """El `dueno_id` del cuerpo se ignora: nadie crea una cancha a nombre de otro."""
    respuesta = client.post(
        "/api/gestion/canchas",
        json={
            "nombre": "Cancha Nueva",
            "ubicacion": "Cra 5 #5-5",
            "dueno_id": 9999,
        },
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 201
    datos = respuesta.get_json()
    assert datos["dueno_id"] == dueno.id
    assert datos["total_horarios"] == 0
    assert datos["tarifa_base"] is None
    assert db.session.execute(db.select(Cancha).filter_by(nombre="Cancha Nueva")).scalar_one().dueno_id == dueno.id


def test_cancha_creada_sale_en_el_ges_de_este_dueño(client, app, token_dueno, dueno):
    creada = client.post(
        "/api/gestion/canchas",
        json={"nombre": "Cancha Nueva", "ubicacion": "Cra 5 #5-5"},
        headers=_auth(token_dueno),
    ).get_json()
    listado = client.get("/api/gestion/canchas", headers=_auth(token_dueno)).get_json()
    assert [c["id"] for c in listado] == [creada["id"]]


def test_tarifa_base_es_el_minimo_de_los_horarios(client, app, token_dueno, cancha):
    _horario(app, cancha, inicio=time(8, 0), fin=time(10, 0), tarifa=60000)
    _horario(app, cancha, inicio=time(10, 0), fin=time(12, 0), tarifa=45000.55)
    datos = client.get("/api/gestion/canchas", headers=_auth(token_dueno)).get_json()[0]
    assert datos["tarifa_base"] == 45000.55
    assert datos["total_horarios"] == 2


@pytest.mark.parametrize(
    "cuerpo",
    [
        {"ubicacion": "Cra 5 #5-5"},
        {"nombre": "   ", "ubicacion": "Cra 5"},
        {"nombre": "Cancha", "ubicacion": ""},
        {"nombre": "Cancha" * 30, "ubicacion": "Cra 5"},
        {"nombre": "Cancha", "ubicacion": "Cra " * 60},
    ],
)
def test_crear_cancha_rechaza_datos_invalidos(client, app, token_dueno, cuerpo):
    respuesta = client.post("/api/gestion/canchas", json=cuerpo, headers=_auth(token_dueno))
    assert respuesta.status_code == 400


def test_crear_cancha_exige_json(client, app, token_dueno):
    respuesta = client.post(
        "/api/gestion/canchas", data="no soy json", headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 400


def test_editar_cancha(client, app, token_dueno, cancha):
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha.id}",
        json={"nombre": "Cancha Uno", "ubicacion": "Cra 2 #2-2"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 200
    assert respuesta.get_json()["nombre"] == "Cancha Uno"
    assert db.session.get(Cancha, cancha.id).ubicacion == "Cra 2 #2-2"


def test_editar_cancha_solo_toca_los_campos_enviados(client, app, token_dueno, cancha):
    client.patch(
        f"/api/gestion/canchas/{cancha.id}", json={"nombre": "Solo esto"}, headers=_auth(token_dueno)
    )
    datos = client.get("/api/gestion/canchas", headers=_auth(token_dueno)).get_json()[0]
    assert datos["nombre"] == "Solo esto"
    assert datos["ubicacion"] == "Cra 1 #2-3"


def test_editar_cancha_vacia_el_nombre_da_400(client, app, token_dueno, cancha):
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha.id}", json={"nombre": ""}, headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 400


def test_baja_de_cancha_es_logica(client, app, token_dueno, cancha, horario):
    """No se borra nada: la cancha desaparece del catálogo pero sigue en su gestión."""
    assert client.delete(
        f"/api/gestion/canchas/{cancha.id}", headers=_auth(token_dueno)
    ).status_code == 204

    assert db.session.get(Cancha, cancha.id) is not None
    publicas = client.get("/api/canchas").get_json()
    assert [c["nombre"] for c in publicas] == []

    propias = client.get("/api/gestion/canchas", headers=_auth(token_dueno)).get_json()
    assert propias[0]["activo"] is False
    # El histórico sigue ahí: el horario y su tarifa no se tocan.
    assert db.session.execute(db.select(db.func.count(Horario.id))).scalar_one() == 1
    assert horario.tarifa == 60000


def test_baja_repetida_es_idempotente(client, app, token_dueno, cancha):
    assert client.delete(
        f"/api/gestion/canchas/{cancha.id}", headers=_auth(token_dueno)
    ).status_code == 204
    assert client.delete(
        f"/api/gestion/canchas/{cancha.id}", headers=_auth(token_dueno)
    ).status_code == 204


def test_reactivar_cancha(client, app, token_dueno, cancha):
    client.delete(f"/api/gestion/canchas/{cancha.id}", headers=_auth(token_dueno))
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha.id}", json={"activo": True}, headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 200
    assert db.session.get(Cancha, cancha.id).activo is True
    assert [c["nombre"] for c in client.get("/api/canchas").get_json()] == ["Cancha Prueba"]


def test_activo_debe_ser_booleano(client, app, token_dueno, cancha):
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha.id}", json={"activo": "no"}, headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 400


# --- horarios ------------------------------------------------------------------


def test_listar_horarios(client, app, token_dueno, cancha, horario):
    _horario(app, cancha, dia=0, inicio=time(10, 0), fin=time(12, 0))
    respuesta = client.get(f"/api/gestion/canchas/{cancha.id}/horarios", headers=_auth(token_dueno))
    assert respuesta.status_code == 200
    horarios = respuesta.get_json()
    assert [h["hora_inicio"] for h in horarios] == ["08:00", "10:00"]
    assert horarios[0]["tarifa"] == 60000.0
    assert horarios[0]["dia"] == 0


def test_crear_horario(client, app, token_dueno, cancha):
    respuesta = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios",
        json={"dia": 2, "hora_inicio": "16:00", "hora_fin": "18:30", "tarifa": 55000.5},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 201
    datos = respuesta.get_json()
    assert datos["hora_inicio"] == "16:00"
    assert datos["hora_fin"] == "18:30"
    assert datos["dia"] == 2
    assert datos["tarifa"] == 55000.5
    assert datos["cancha_id"] == cancha.id


@pytest.mark.parametrize(
    "cuerpo",
    [
        {"dia": 0, "hora_inicio": "08:00", "hora_fin": "10:00"},  # sin tarifa
        {"dia": "lunes", "hora_inicio": "08:00", "hora_fin": "10:00", "tarifa": 1000},
        {"dia": 7, "hora_inicio": "08:00", "hora_fin": "10:00", "tarifa": 1000},
        {"dia": -1, "hora_inicio": "08:00", "hora_fin": "10:00", "tarifa": 1000},
        {"dia": 0, "hora_inicio": "8:00", "hora_fin": "10:00", "tarifa": 1000},
        {"dia": 0, "hora_inicio": "08:00", "hora_fin": "24:00", "tarifa": 1000},
        {"dia": 0, "hora_inicio": "08:00", "hora_fin": "10:00", "tarifa": "gratis"},
    ],
)
def test_crear_horario_rechaza_datos_invalidos(client, app, token_dueno, cancha, cuerpo):
    respuesta = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios", json=cuerpo, headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 400


@pytest.mark.parametrize(
    "cuerpo",
    [
        {"dia": 0, "hora_inicio": "08:00", "hora_fin": "08:00", "tarifa": 1000},
        {"dia": 0, "hora_inicio": "08:00", "hora_fin": "07:00", "tarifa": 1000},
        {"dia": 0, "hora_inicio": "08:00", "hora_fin": "10:00", "tarifa": 0},
        {"dia": 0, "hora_inicio": "08:00", "hora_fin": "10:00", "tarifa": -5},
    ],
)
def test_crear_horario_rechaza_orden_y_tarifa(client, app, token_dueno, cancha, cuerpo):
    """Datos que son «horas válidas» pero no un horario posible: `422`."""
    respuesta = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios", json=cuerpo, headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 422


def test_horarios_que_se_solapan_dan_422(client, app, token_dueno, cancha, horario):
    """`08:00-10:00` ya existe; un `09:00-11:00` se pisa con él."""
    respuesta = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios",
        json={"dia": 0, "hora_inicio": "09:00", "hora_fin": "11:00", "tarifa": 40000},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 422
    assert "solapa" in respuesta.get_json()["error"]["mensaje"]
    assert db.session.execute(db.select(db.func.count(Horario.id))).scalar_one() == 1


def test_horarios_que_solo_se_tocan_pueden_convivir(client, app, token_dueno, cancha, horario):
    """`10:00` es el final del horario anterior y el inicio del nuevo: no hay solape."""
    respuesta = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios",
        json={"dia": 0, "hora_inicio": "10:00", "hora_fin": "12:00", "tarifa": 40000},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 201


def test_horario_duplicado_da_409(client, app, token_dueno, cancha, horario):
    """Mismo día y misma hora de inicio: el mensaje es «ya existe», no «se solapa»."""
    respuesta = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios",
        json={"dia": 0, "hora_inicio": "08:00", "hora_fin": "09:00", "tarifa": 40000},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 409
    assert db.session.execute(db.select(db.func.count(Horario.id))).scalar_one() == 1


def test_solape_solo_se_mira_en_el_mismo_dia(client, app, token_dueno, cancha, horario):
    respuesta = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios",
        json={"dia": 1, "hora_inicio": "08:00", "hora_fin": "10:00", "tarifa": 40000},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 201


def test_editar_horario(client, app, token_dueno, cancha, horario):
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}",
        json={"hora_fin": "11:00", "tarifa": 70000},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 200
    datos = respuesta.get_json()
    assert datos["hora_fin"] == "11:00"
    assert datos["tarifa"] == 70000.0
    assert datos["hora_inicio"] == "08:00"


def test_editar_horario_ignora_su_propio_solape(client, app, token_dueno, cancha, horario):
    """Un horario no se solapa consigo mismo: sin `excluir` esto daría `422` siempre."""
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}",
        json={"hora_fin": "12:00", "tarifa": 60000},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 200
    assert respuesta.get_json()["hora_fin"] == "12:00"


def test_editar_horario_no_puede_solaparse_con_otro(client, app, token_dueno, cancha, horario):
    _horario(app, cancha, inicio=time(10, 0), fin=time(12, 0))
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}",
        json={"hora_fin": "11:00"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 422
    assert db.session.get(Horario, horario.id).hora_fin == time(10, 0)


def test_horario_de_otra_cancha_da_404(client, app, token_dueno, cancha_ajena):
    horario = _horario(app, cancha_ajena)
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha_ajena.id}/horarios/{horario.id}",
        json={"tarifa": 1},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 404


def test_no_se_puede_mover_un_horario_con_reservas(
    client, app, token_dueno, cancha, horario, cliente
):
    """Mover el slot dejaría la reserva vendida en un horario que ya no le corresponde."""
    _reserva(app, cliente, cancha, horario, pago=PAGO_APROBADO)

    mover = client.patch(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}",
        json={"dia": 1},
        headers=_auth(token_dueno),
    )
    assert mover.status_code == 409
    assert "reservas" in mover.get_json()["error"]["mensaje"]

    acortar = client.patch(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}",
        json={"hora_fin": "09:00"},
        headers=_auth(token_dueno),
    )
    assert acortar.status_code == 409
    assert db.session.get(Horario, horario.id).hora_fin == time(10, 0)


def test_si_se_puede_cambiar_la_tarifa_de_un_horario_con_reservas(
    client, app, token_dueno, cancha, horario, cliente
):
    """El precio de una reserva ya cerrada está en su pago: no se recalcula."""
    _reserva(app, cliente, cancha, horario, estado=ESTADO_CONFIRMADA, pago=PAGO_APROBADO)
    respuesta = client.patch(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}",
        json={"tarifa": 80000},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 200
    assert db.session.get(Horario, horario.id).tarifa == 80000


def test_borrar_horario_libre(client, app, token_dueno, cancha, horario):
    respuesta = client.delete(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}", headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 204
    assert db.session.execute(db.select(db.func.count(Horario.id))).scalar_one() == 0


def test_borrar_horario_con_reservas_da_409(client, app, token_dueno, cancha, horario, cliente):
    _reserva(app, cliente, cancha, horario, pago=PAGO_APROBADO)
    respuesta = client.delete(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}", headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 409
    assert db.session.execute(db.select(db.func.count(Horario.id))).scalar_one() == 1


def test_borrar_horario_con_reserva_cancelada_tambien_da_409(
    client, app, token_dueno, cancha, horario, cliente
):
    """Cancelada o no, la reserva es historial: el horario no se borra.

    La FK es `ON DELETE RESTRICT`, así que permitirlo dejaría un `500` en vez de una
    respuesta entendible. Y aunque no la hubiera, un registro de reserva apuntaría a un
    slot que ya no existe.
    """
    _reserva(app, cliente, cancha, horario, estado=ESTADO_CANCELADA, pago=PAGO_RECHAZADO)
    respuesta = client.delete(
        f"/api/gestion/canchas/{cancha.id}/horarios/{horario.id}", headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 409
    assert db.session.execute(db.select(db.func.count(Horario.id))).scalar_one() == 1


# --- reservas de la cancha -----------------------------------------------------


def test_listar_reservas_de_la_cancha(client, app, token_dueno, cancha, horario, cliente):
    _reserva(app, cliente, cancha, horario, estado=ESTADO_CONFIRMADA, pago=PAGO_APROBADO)
    respuesta = client.get(f"/api/gestion/canchas/{cancha.id}/reservas", headers=_auth(token_dueno))
    assert respuesta.status_code == 200
    reserva = respuesta.get_json()[0]
    assert reserva["estado"] == ESTADO_CONFIRMADA
    assert reserva["cliente"]["nombre"] == "Carla Cliente"
    assert reserva["pago"]["estado"] == PAGO_APROBADO
    assert reserva["cancha"]["id"] == cancha.id
    # El dueño necesita saber a quién le prestó la cancha, no su correo.
    assert "email" not in str(reserva)


def test_listar_reservas_solo_de_esa_cancha(
    client, app, token_dueno, cancha, cancha_ajena, cliente, dueno_otro
):
    horario_propio = _horario(app, cancha)
    horario_ajeno = _horario(app, cancha_ajena)
    _reserva(app, cliente, cancha, horario_propio, pago=PAGO_APROBADO)
    _reserva(app, dueno_otro, cancha_ajena, horario_ajeno, pago=PAGO_APROBADO)

    propias = client.get(
        f"/api/gestion/canchas/{cancha.id}/reservas", headers=_auth(token_dueno)
    ).get_json()
    assert len(propias) == 1
    assert propias[0]["cancha"]["id"] == cancha.id


def test_confirmar_reserva_con_pago_aprobado(client, app, token_dueno, cancha, horario, cliente):
    reserva = _reserva(app, cliente, cancha, horario, pago=PAGO_APROBADO)
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": "confirmar"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 200
    assert respuesta.get_json()["estado"] == ESTADO_CONFIRMADA
    assert db.session.get(Reserva, reserva.id).estado == ESTADO_CONFIRMADA


def test_confirmar_sin_pago_aprobado_da_422(client, app, token_dueno, cancha, horario, cliente):
    """El punto de la regla: confirmar no es un botón, es consecuencia del pago."""
    reserva = _reserva(app, cliente, cancha, horario, pago=PAGO_PENDIENTE)
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": "confirmar"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 422
    assert "pago" in respuesta.get_json()["error"]["mensaje"]
    assert db.session.get(Reserva, reserva.id).estado == ESTADO_PENDIENTE_PAGO


def test_confirmar_reserva_sin_pago_registrado_da_422(
    client, app, token_dueno, cancha, horario, cliente
):
    reserva = _reserva(app, cliente, cancha, horario, pago=None)
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": "confirmar"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 422
    assert db.session.get(Reserva, reserva.id).estado == ESTADO_PENDIENTE_PAGO


def test_no_se_confirma_dos_veces(client, app, token_dueno, cancha, horario, cliente):
    reserva = _reserva(
        app, cliente, cancha, horario, estado=ESTADO_CONFIRMADA, pago=PAGO_APROBADO
    )
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": "confirmar"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 422


def test_cancelar_reserva(client, app, token_dueno, cancha, horario, cliente):
    reserva = _reserva(
        app, cliente, cancha, horario, estado=ESTADO_CONFIRMADA, pago=PAGO_APROBADO
    )
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": "cancelar"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 200
    assert db.session.get(Reserva, reserva.id).estado == ESTADO_CANCELADA
    # Cancelar no devuelve el pago: la política de reembolso está fuera de alcance (§6).
    assert db.session.execute(db.select(Pago).filter_by(reserva_id=reserva.id)).scalar_one().estado == PAGO_APROBADO


def test_cancelar_libera_el_slot_para_otro_cliente(
    client, app, token_dueno, token_cliente, cancha, horario, cliente
):
    """La consecuencia real de cancelar: el horario vuelve a estar disponible."""
    fecha = _proxima_fecha_lunes()
    _reserva(
        app, cliente, cancha, horario, estado=ESTADO_CONFIRMADA, pago=PAGO_APROBADO, fecha=fecha
    )
    creada = client.post(
        "/api/reservas",
        json={"cancha_id": cancha.id, "horario_id": horario.id, "fecha": fecha},
        headers=_auth(token_cliente),
    )
    assert creada.status_code == 409

    reservas = client.get(
        f"/api/gestion/canchas/{cancha.id}/reservas", headers=_auth(token_dueno)
    ).get_json()
    client.patch(
        f"/api/gestion/reservas/{reservas[0]['reserva_id']}",
        json={"accion": "cancelar"},
        headers=_auth(token_dueno),
    )

    reintento = client.post(
        "/api/reservas",
        json={"cancha_id": cancha.id, "horario_id": horario.id, "fecha": fecha},
        headers=_auth(token_cliente),
    )
    assert reintento.status_code == 201


def test_no_se_cancela_dos_veces(client, app, token_dueno, cancha, horario, cliente):
    reserva = _reserva(
        app, cliente, cancha, horario, estado=ESTADO_CANCELADA, pago=PAGO_RECHAZADO
    )
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": "cancelar"},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 422


@pytest.mark.parametrize("accion", ["", "eliminar", "CONFIRMAR_EXTRA", None, 5])
def test_accion_invalida_da_400(client, app, token_dueno, cancha, horario, cliente, accion):
    reserva = _reserva(app, cliente, cancha, horario, pago=PAGO_APROBADO)
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": accion},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 400
    assert db.session.get(Reserva, reserva.id).estado == ESTADO_PENDIENTE_PAGO


def test_acciones_en_distinto_uso_de_mayusculas_son_equivalentes(
    client, app, token_dueno, cancha, horario, cliente
):
    """La app puede mandar el verbo como venga; el servidor no debería fallar por eso."""
    reserva = _reserva(app, cliente, cancha, horario, pago=PAGO_APROBADO)
    respuesta = client.patch(
        f"/api/gestion/reservas/{reserva.id}",
        json={"accion": " Confirmar "},
        headers=_auth(token_dueno),
    )
    assert respuesta.status_code == 200
    assert respuesta.get_json()["estado"] == ESTADO_CONFIRMADA


def test_reserva_inexistente_da_404(client, app, token_dueno):
    respuesta = client.patch(
        "/api/gestion/reservas/9999", json={"accion": "cancelar"}, headers=_auth(token_dueno)
    )
    assert respuesta.status_code == 404


# --- Tope de la tarifa (spec.md 7.6) --------------------------------------------------
# `Numeric(10, 2)` en PostgreSQL lanza `numeric field overflow` y la API devolvía 500;
# en SQLite el valor entraba sin rechistar. El tope sale de la columna, como los textos.

def test_tarifa_mas_alta_que_la_columna_no_revienta(client, token_dueno, cancha):
    r = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios",
        json={
            "dia": 6,
            "hora_inicio": "20:00",
            "hora_fin": "22:00",
            "tarifa": limites.TARIFA_MAXIMA + 1,
        },
        headers={"Authorization": f"Bearer {token_dueno}"},
    )
    assert r.status_code == 422
    assert "99.999.999,99" in r.get_json()["error"]["mensaje"]


def test_tarifa_justo_en_el_limite_de_la_columna(client, token_dueno, cancha):
    """Como con el email: el valor que llega justo al tope tiene que entrar."""
    r = client.post(
        f"/api/gestion/canchas/{cancha.id}/horarios",
        json={
            "dia": 6,
            "hora_inicio": "20:00",
            "hora_fin": "22:00",
            "tarifa": limites.TARIFA_MAXIMA,
        },
        headers={"Authorization": f"Bearer {token_dueno}"},
    )
    assert r.status_code == 201


def test_tarifa_maxima_es_el_de_la_columna(app):
    assert limites.TARIFA_MAXIMA == 99_999_999.99

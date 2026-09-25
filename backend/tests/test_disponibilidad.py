"""Tests de disponibilidad (spec.md 3.2).

Las pruebas de HTTP usan fechas futuras para no depender de la hora de ejecución; la
regla de "slot transcurrido" se verifica de forma determinista sobre el helper.
"""

from datetime import date, datetime, time, timedelta

import pytest

from blueprints.disponibilidad import (
    DIAS_VENTANA,
    MOTIVO_OCUPADO,
    MOTIVO_TRANSCURRIDO,
    parse_fecha,
    slot_vencido,
)
from extensions import db
from models import (
    ESTADO_CANCELADA,
    ESTADO_CONFIRMADA,
    ESTADO_PENDIENTE_PAGO,
    Cancha,
    Cliente,
    Horario,
    Reserva,
)

#: Lunes de una semana futura: todas las fechas de la ventana quedan en el futuro.
LUNES = date.today() + timedelta(days=7 - date.today().weekday() + 7)


def _horario(cancha, dia, inicio, fin, tarifa=60000):
    horario = Horario(cancha_id=cancha.id, dia=dia, hora_inicio=inicio, hora_fin=fin, tarifa=tarifa)
    db.session.add(horario)
    db.session.flush()
    return horario


def _reserva(cliente, cancha, horario, fecha, estado=ESTADO_PENDIENTE_PAGO):
    reserva = Reserva(
        cliente_id=cliente.id, cancha_id=cancha.id, horario_id=horario.id, fecha=fecha, estado=estado
    )
    db.session.add(reserva)
    db.session.flush()
    return reserva


def _url(cancha_id, fecha=None):
    return f"/api/disponibilidad?cancha_id={cancha_id}&fecha_inicio={(fecha or LUNES).isoformat()}"


# --- validación de parámetros -------------------------------------------------


@pytest.mark.parametrize(
    "url",
    [
        "/api/disponibilidad",
        "/api/disponibilidad?cancha_id=1",
        "/api/disponibilidad?fecha_inicio=2026-09-24",
    ],
)
def test_exige_ambos_parametros(app, client, url):
    r = client.get(url)
    assert r.status_code == 400
    assert r.get_json()["error"]["codigo"] == 400


def test_cancha_id_no_numerico_400(app, client, cancha):
    assert client.get(_url("abc")).status_code == 400


@pytest.mark.parametrize("fecha", ["24-09-2026", "2026-13-01", "hoy", ""])
def test_fecha_invalida_400(app, client, cancha, fecha):
    assert client.get(f"/api/disponibilidad?cancha_id={cancha.id}&fecha_inicio={fecha}").status_code == 400


def test_cancha_inexistente_404(app, client):
    assert client.get(_url(9999)).status_code == 404


def test_cancha_inactiva_404(app, client, dueno):
    inactiva = Cancha(nombre="Fuera", ubicacion="Cra 9", dueno_id=dueno.id, activo=False)
    db.session.add(inactiva)
    db.session.flush()
    assert client.get(_url(inactiva.id)).status_code == 404


# --- ventana y calendario -----------------------------------------------------


def test_entrega_seis_dias(app, client, cancha):
    for dia in range(7):
        _horario(cancha, dia, time(8, 0), time(10, 0))

    slots = client.get(_url(cancha.id)).get_json()
    fechas = sorted({s["fecha"] for s in slots})
    assert len(fechas) == DIAS_VENTANA
    assert fechas[0] == LUNES.isoformat()
    assert fechas[-1] == (LUNES + timedelta(days=DIAS_VENTANA - 1)).isoformat()


def test_la_ventana_de_seis_dias_llega_hasta_el_sabado(app, client, cancha):
    """Documenta la ventana: 6 días desde el lunes = lunes..sábado (sin domingo)."""
    sabado = _horario(cancha, 5, time(9, 0), time(11, 0))
    domingo = _horario(cancha, 6, time(9, 0), time(11, 0))

    slots = client.get(_url(cancha.id)).get_json()
    assert [s["fecha"] for s in slots] == [(LUNES + timedelta(days=5)).isoformat()]
    assert slots[0]["horario_id"] == sabado.id
    assert domingo.id not in [s["horario_id"] for s in slots]


def test_solo_devuelve_slots_del_dia_que_corresponde(app, client, cancha):
    """`dia` es el día ISO de la fecha: lunes=0 ... domingo=6.

    La ventana de 6 días desde un lunes cubre lunes..sábado, así que el horario del
    domingo (dia 6) no debe aparecer.
    """
    lunes = _horario(cancha, 0, time(8, 0), time(10, 0))
    domingo = _horario(cancha, 6, time(8, 0), time(10, 0))
    db.session.commit()

    slots = client.get(_url(cancha.id)).get_json()
    assert [s["horario_id"] for s in slots] == [lunes.id]
    assert [s["fecha"] for s in slots] == [LUNES.isoformat()]


def test_cancha_sin_horarios_para_la_ventana_devuelve_lista_vacia(app, client, cancha):
    _horario(cancha, 0, time(8, 0), time(10, 0))  # sólo lunes
    assert client.get(_url(cancha.id, fecha=LUNES + timedelta(days=1))).get_json() == []


def test_orden_por_fecha_y_hora(app, client, cancha):
    tarde = _horario(cancha, LUNES.weekday(), time(16, 0), time(18, 0))
    temprano = _horario(cancha, LUNES.weekday(), time(8, 0), time(10, 0))
    db.session.commit()

    slots = client.get(_url(cancha.id)).get_json()
    assert [s["horario_id"] for s in slots] == [temprano.id, tarde.id]
    assert slots[0]["hora_inicio"] == "08:00"
    assert slots[0]["hora_fin"] == "10:00"
    assert slots[0]["tarifa"] == 60000.0


def test_no_expone_id_de_reserva(app, client, cancha, cliente):
    """El calendario es público: sólo el estado, nunca quién reservó."""
    for dia in range(7):
        _horario(cancha, dia, time(8, 0), time(10, 0))
    horario = db.session.execute(db.select(Horario)).scalars().first()
    _reserva(cliente, cancha, horario, LUNES)

    slot = client.get(_url(cancha.id)).get_json()[0]
    assert set(slot) == {
        "horario_id",
        "fecha",
        "hora_inicio",
        "hora_fin",
        "tarifa",
        "disponible",
        "motivo",
    }


# --- disponibilidad y motivos -------------------------------------------------


def test_slot_libre_disponible_sin_motivo(app, client, cancha):
    for dia in range(7):
        _horario(cancha, dia, time(8, 0), time(10, 0))

    slots = client.get(_url(cancha.id)).get_json()
    assert all(s["disponible"] is True and s["motivo"] is None for s in slots)


@pytest.mark.parametrize("estado", [ESTADO_PENDIENTE_PAGO, ESTADO_CONFIRMADA, "otro_estado"])
def test_reserva_no_cancelada_ocupa_el_slot(app, client, cancha, cliente, estado):
    for dia in range(7):
        _horario(cancha, dia, time(8, 0), time(10, 0))
    horario = db.session.execute(db.select(Horario)).scalars().first()
    _reserva(cliente, cancha, horario, LUNES, estado=estado)

    slot = client.get(_url(cancha.id)).get_json()[0]
    assert slot["disponible"] is False
    assert slot["motivo"] == MOTIVO_OCUPADO


def test_reserva_cancelada_libera_el_slot(app, client, cancha, cliente):
    for dia in range(7):
        _horario(cancha, dia, time(8, 0), time(10, 0))
    horario = db.session.execute(db.select(Horario)).scalars().first()
    _reserva(cliente, cancha, horario, LUNES, estado=ESTADO_CANCELADA)

    slot = client.get(_url(cancha.id)).get_json()[0]
    assert slot["disponible"] is True
    assert slot["motivo"] is None


def test_ocupar_un_slot_no_afecta_a_los_demas_del_mismo_dia(app, client, cancha, cliente):
    """La ocupación se indexa por `(horario_id, fecha)`, no por fecha."""
    temprano = _horario(cancha, LUNES.weekday(), time(8, 0), time(10, 0))
    tarde = _horario(cancha, LUNES.weekday(), time(16, 0), time(18, 0))
    _reserva(cliente, cancha, temprano, LUNES)

    slots = client.get(_url(cancha.id)).get_json()
    por_id = {s["horario_id"]: s for s in slots if s["fecha"] == LUNES.isoformat()}
    assert por_id[temprano.id]["motivo"] == MOTIVO_OCUPADO
    assert por_id[tarde.id]["disponible"] is True
    assert por_id[tarde.id]["motivo"] is None


def test_no_mezcla_ocupaciones_de_otra_cancha(app, client, dueno, cliente):
    """El filtro por `cancha_id` debe bastar: el aislamiento multi-dueño."""
    dueno2 = Cliente(nombre="Otro", email="otro@test.co", rol_id=dueno.rol_id, activo=True)
    dueno2.set_password("Goaltime123!")
    db.session.add(dueno2)
    db.session.flush()
    mia = Cancha(nombre="Mía", ubicacion="Cra 1", dueno_id=dueno.id)
    ajena = Cancha(nombre="Ajena", ubicacion="Cra 2", dueno_id=dueno2.id)
    db.session.add_all([mia, ajena])
    db.session.flush()
    for dia in range(7):
        _horario(mia, dia, time(8, 0), time(10, 0))
        _horario(ajena, dia, time(8, 0), time(10, 0))
    horario_ajeno = db.session.execute(
        db.select(Horario).filter_by(cancha_id=ajena.id)
    ).scalars().first()
    _reserva(cliente, ajena, horario_ajeno, LUNES)

    slots = client.get(_url(mia.id)).get_json()
    assert all(s["disponible"] is True for s in slots)


# --- helpers deterministas ----------------------------------------------------


def test_parse_fecha_acepta_iso():
    assert parse_fecha("2026-09-24") == date(2026, 9, 24)


@pytest.mark.parametrize("texto", ["2026-9-4", "24/09/2026", "", None, "2026-02-30"])
def test_parse_fecha_rechaza_invalidos(texto):
    assert parse_fecha(texto) is None


@pytest.mark.parametrize(
    "fecha, inicio, esperado",
    [
        (date(2026, 9, 24), time(8, 0), True),    # fecha pasada
        (date(2026, 9, 25), time(8, 0), True),    # hoy, la hora de inicio ya pasó
        (date(2026, 9, 25), time(10, 0), True),   # hoy, empieza justo ahora
        (date(2026, 9, 25), time(10, 1), False),  # hoy, empieza en un minuto
        (date(2026, 9, 25), time(23, 0), False),  # hoy, más tarde
        (date(2026, 9, 26), time(8, 0), False),   # mañana
    ],
)
def test_slot_vencido(fecha, inicio, esperado):
    ahora = datetime(2026, 9, 25, 10, 0)
    assert slot_vencido(fecha, inicio, ahora) is esperado


def test_slots_de_hoy_ya_transcurridos_son_no_disponibles(app, client, cancha):
    """Regla aplicada por el endpoint con el reloj real, sin depender del test."""
    if datetime.now().time() < time(0, 2):
        pytest.skip("la suite arrancó dentro del propio slot de prueba")

    hoy = date.today()
    _horario(cancha, hoy.weekday(), time(0, 0), time(0, 1))   # ya vencido
    _horario(cancha, hoy.weekday(), time(23, 58), time(23, 59))  # todavía por empezar
    db.session.commit()

    slots = client.get(_url(cancha.id, fecha=hoy)).get_json()
    por_hora = {s["hora_inicio"]: s for s in slots if s["fecha"] == hoy.isoformat()}
    assert por_hora["00:00"]["disponible"] is False
    assert por_hora["00:00"]["motivo"] == MOTIVO_TRANSCURRIDO
    assert por_hora["23:58"]["disponible"] is True
    assert por_hora["23:58"]["motivo"] is None

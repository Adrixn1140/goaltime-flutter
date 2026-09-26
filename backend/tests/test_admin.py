"""Pruebas de Admin: `/api/usuarios` y `/api/reporte` (spec.md 3.5).

El admin es el único rol que ve la plataforma entera, así que sus tests se centran en
las tres cosas que pueden romper de verdad:

* **Que sólo entre admin.** Un `cliente` o un `dueño` reciben `403`.
* **Que el admin no pueda dejar la plataforma sin administración.** Cambiarse a sí mismo
  el rol o desactivarse es `422`; bajar de dueño a cliente con canchas activas es `422`,
  con el número en el mensaje para que el admin sepa qué tiene que bajar antes.
* **Que el reporte sume lo que el negocio llama dinero.** Ingresos = pagos aprobados
  (una reserva cancelada cuenta porque cancelar no reembolsa), y los conteos de reservas
  salen por estado, incluidas las canceladas.
"""

from datetime import date, time, timedelta

import pytest

from extensions import db
from models import (
    ESTADO_CANCELADA,
    ESTADO_CONFIRMADA,
    ESTADO_PENDIENTE_PAGO,
    PAGO_APROBADO,
    PAGO_PENDIENTE,
    PAGO_RECHAZADO,
    ROL_CLIENTE,
    ROL_DUENO,
    Cancha,
    Cliente,
    Horario,
    Pago,
    Reserva,
)

PASSWORD = "Goaltime123!"


@pytest.fixture()
def token_admin(client, admin):
    return _login(client, admin.email)


@pytest.fixture()
def token_dueno(client, dueno):
    return _login(client, dueno.email)


@pytest.fixture()
def token_cliente(client, cliente):
    return _login(client, cliente.email)


@pytest.fixture()
def dueno_con_canchas(app, dueno, dueno_otro):
    """Un dueño con dos canchas: una activa y una ya dada de baja."""
    _cancha(dueno, "Cancha Activa", activa=True)
    _cancha(dueno, "Cancha De Baja", activa=False)
    _cancha(dueno_otro, "Cancha De Otro", activa=True)
    return dueno


def _login(client, email, password=PASSWORD):
    respuesta = client.post("/api/login", json={"email": email, "password": password})
    assert respuesta.status_code == 200, respuesta.get_json()
    return respuesta.get_json()["access_token"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _cancha(dueno, nombre, activa=True):
    cancha = Cancha(nombre=nombre, ubicacion="Cra 1 #2-3", dueno_id=dueno.id, activo=activa)
    db.session.add(cancha)
    db.session.commit()
    return cancha


def _reserva(cliente, cancha, fecha, estado, pago_estado=None, monto=60000, hora=14):
    """Reserva con horario propio: los horarios no se comparten entre canchas.

    `hora` es la hora de inicio porque `(cancha_id, dia, hora_inicio)` es único: dos
    reservas en la misma cancha necesitan horas distintas, igual que en la vida real. Por
    omisión usa las 14:00 porque el fixture `cancha` ya trae un horario a las 08:00.
    """
    horario = Horario(
        cancha_id=cancha.id,
        dia=0,
        hora_inicio=time(hora, 0),
        hora_fin=time(hora + 2, 0),
        tarifa=monto,
    )
    db.session.add(horario)
    db.session.commit()
    reserva = Reserva(
        cliente_id=cliente.id,
        cancha_id=cancha.id,
        horario_id=horario.id,
        fecha=fecha,
        estado=estado,
    )
    db.session.add(reserva)
    db.session.commit()
    if pago_estado:
        db.session.add(Pago(reserva_id=reserva.id, monto=monto, estado=pago_estado))
        db.session.commit()
    return reserva


# --------------------------------------------------------------------------- acceso
class TestAcceso:
    def test_sin_token_responde_401(self, client):
        assert client.get("/api/usuarios").status_code == 401
        assert client.get("/api/reporte").status_code == 401

    def test_un_cliente_recibe_403(self, client, token_cliente):
        respuesta = client.get("/api/usuarios", headers=_auth(token_cliente))
        assert respuesta.status_code == 403
        assert respuesta.get_json()["error"]["codigo"] == 403

    def test_un_dueno_recibe_403(self, client, token_dueno):
        assert client.get("/api/reporte", headers=_auth(token_dueno)).status_code == 403
        assert (
            client.patch(
                "/api/usuarios/1/rol", json={"rol": "admin"}, headers=_auth(token_dueno)
            ).status_code
            == 403
        )

    def test_el_admin_entra(self, client, token_admin):
        respuesta = client.get("/api/usuarios", headers=_auth(token_admin))
        assert respuesta.status_code == 200


# ------------------------------------------------------------------------ usuarios
class TestListarUsuarios:
    def test_lista_todos_los_usuarios_con_rol_y_activo(self, client, token_admin, cliente, dueno):
        respuesta = client.get("/api/usuarios", headers=_auth(token_admin))
        assert respuesta.status_code == 200

        usuarios = {u["email"]: u for u in respuesta.get_json()["usuarios"]}
        assert set(usuarios) >= {cliente.email, dueno.email, "admin@test.co"}
        assert usuarios[cliente.email]["rol"] == ROL_CLIENTE
        assert usuarios[dueno.email]["rol"] == ROL_DUENO
        assert all(u["activo"] is True for u in usuarios.values())

    def test_trae_los_conteos_de_canchas_y_reservas(
        self, client, token_admin, cliente, dueno_con_canchas, cancha, horario
    ):
        _reserva(cliente, cancha, date(2026, 9, 20), ESTADO_CONFIRMADA, PAGO_APROBADO)

        respuesta = client.get("/api/usuarios", headers=_auth(token_admin))
        usuarios = {u["email"]: u for u in respuesta.get_json()["usuarios"]}
        dueno = usuarios[dueno_con_canchas.email]

        # El dueño ve 3 canchas suyas (2 + la del fixture `cancha`).
        assert dueno["canchas"] == 3
        # Las reservas se cuentan por quien reservó, no por quién posee la cancha: el
        # dueño prestó la cancha, no la reservó.
        assert dueno["reservas"] == 0
        assert usuarios[cliente.email]["reservas"] == 1
        assert usuarios[cliente.email]["canchas"] == 0

    def test_no_filtra_por_rol(self, client, token_admin, cliente, dueno):
        respuesta = client.get("/api/usuarios", headers=_auth(token_admin))
        roles = {u["rol"] for u in respuesta.get_json()["usuarios"]}
        assert {"cliente", "dueno", "admin"} <= roles


# -------------------------------------------------------------------------- rol/activo
class TestCambiarRol:
    def test_promueve_un_cliente_a_dueno(self, client, token_admin, cliente, app):
        respuesta = client.patch(
            f"/api/usuarios/{cliente.id}/rol", json={"rol": ROL_DUENO}, headers=_auth(token_admin)
        )
        assert respuesta.status_code == 200
        assert respuesta.get_json()["rol"] == ROL_DUENO

        guardado = db.session.get(Cliente, cliente.id)
        assert guardado.rol == ROL_DUENO

    def test_desactiva_y_reactiva_un_usuario(self, client, token_admin, cliente, app):
        respuesta = client.patch(
            f"/api/usuarios/{cliente.id}/rol", json={"activo": False}, headers=_auth(token_admin)
        )
        assert respuesta.status_code == 200
        assert respuesta.get_json()["activo"] is False
        assert db.session.get(Cliente, cliente.id).activo is False

        de_vuelta = client.patch(
            f"/api/usuarios/{cliente.id}/rol", json={"activo": True}, headers=_auth(token_admin)
        )
        assert de_vuelta.get_json()["activo"] is True

    def test_el_admin_no_se_cambia_a_si_mismo(self, client, token_admin, admin):
        respuesta = client.patch(
            f"/api/usuarios/{admin.id}/rol", json={"rol": ROL_CLIENTE}, headers=_auth(token_admin)
        )
        assert respuesta.status_code == 422
        assert "tu propia cuenta" in respuesta.get_json()["error"]["mensaje"]
        assert db.session.get(Cliente, admin.id).rol == "admin"

    def test_el_admin_no_se_desactiva(self, client, token_admin, admin):
        respuesta = client.patch(
            f"/api/usuarios/{admin.id}/rol", json={"activo": False}, headers=_auth(token_admin)
        )
        assert respuesta.status_code == 422
        assert db.session.get(Cliente, admin.id).activo is True

    def test_bajar_de_dueno_con_canchas_activas_da_422_con_el_numero(self, client, token_admin, dueno_con_canchas):
        respuesta = client.patch(
            f"/api/usuarios/{dueno_con_canchas.id}/rol",
            json={"rol": ROL_CLIENTE},
            headers=_auth(token_admin),
        )
        assert respuesta.status_code == 422
        # Sólo cuenta la activa: la que ya está de baja no bloquea el cambio.
        assert "1 cancha activa" in respuesta.get_json()["error"]["mensaje"]
        assert db.session.get(Cliente, dueno_con_canchas.id).rol == ROL_DUENO

    def test_bajar_de_dueno_solo_con_canchas_inactivas_si_se_puede(self, client, token_admin, dueno):
        vieja = _cancha(dueno, "Cancha Vieja", activa=False)

        respuesta = client.patch(
            f"/api/usuarios/{dueno.id}/rol", json={"rol": ROL_CLIENTE}, headers=_auth(token_admin)
        )
        assert respuesta.status_code == 200
        assert respuesta.get_json()["rol"] == ROL_CLIENTE
        # La cancha inactiva se queda con el usuario: si vuelve a ser dueño, la recupera.
        assert vieja.dueno_id == dueno.id
        assert db.session.get(Cliente, dueno.id).rol == ROL_CLIENTE

    def test_usuario_inexistente_da_404(self, client, token_admin):
        respuesta = client.patch(
            "/api/usuarios/9999/rol", json={"rol": ROL_DUENO}, headers=_auth(token_admin)
        )
        assert respuesta.status_code == 404

    @pytest.mark.parametrize(
        "cuerpo",
        [
            {},
            {"rol": "otro"},
            {"rol": None},
            {"activo": "quizá"},
        ],
    )
    def test_cuerpo_invalido_da_400(self, client, token_admin, cliente, cuerpo):
        respuesta = client.patch(
            f"/api/usuarios/{cliente.id}/rol", json=cuerpo, headers=_auth(token_admin)
        )
        assert respuesta.status_code == 400

    def test_sin_cuerpo_da_400(self, client, token_admin, cliente):
        respuesta = client.patch(f"/api/usuarios/{cliente.id}/rol", headers=_auth(token_admin))
        assert respuesta.status_code == 400


# ------------------------------------------------------------------ usuario inactivo
class TestUsuarioInactivo:
    def test_no_puede_iniciar_sesion(self, client, cliente, token_admin):
        client.patch(
            f"/api/usuarios/{cliente.id}/rol", json={"activo": False}, headers=_auth(token_admin)
        )

        respuesta = client.post("/api/login", json={"email": cliente.email, "password": PASSWORD})
        assert respuesta.status_code == 403
        assert "desactivada" in respuesta.get_json()["error"]["mensaje"]

    def test_contrasena_incorrecta_sigue_siendo_401(self, client, cliente, token_admin):
        """El 403 de cuenta desactivada sólo se dice con la contraseña correcta: si no,
        el login confirmaría que el email existe."""
        client.patch(
            f"/api/usuarios/{cliente.id}/rol", json={"activo": False}, headers=_auth(token_admin)
        )

        respuesta = client.post(
            "/api/login", json={"email": cliente.email, "password": "OtraClave!"}
        )
        assert respuesta.status_code == 401

    def test_un_token_ya_emitido_deja_de_servir(self, client, cliente, token_cliente, token_admin):
        # Se usa una ruta que exige sesión y no el catálogo público, que es público a
        # propósito: desactivar la cuenta no puede cerrar la puerta de ver el catálogo.
        antes = client.get("/api/gestion/canchas", headers=_auth(token_cliente))
        assert antes.status_code == 403  # el cliente es un cliente: le falta el rol

        client.patch(
            f"/api/usuarios/{cliente.id}/rol", json={"activo": False}, headers=_auth(token_admin)
        )

        despues = client.get("/api/gestion/canchas", headers=_auth(token_cliente))
        assert despues.status_code == 401
        assert "desactivada" in despues.get_json()["error"]["mensaje"]


# --------------------------------------------------------------------------- reporte
class TestReporte:
    def test_sin_datos_devuelve_ceros_no_error(self, client, token_admin):
        respuesta = client.get("/api/reporte", headers=_auth(token_admin))
        assert respuesta.status_code == 200

        reporte = respuesta.get_json()
        assert reporte["ingresos"]["total"] == 0
        assert reporte["reservas"]["total"] == 0
        assert reporte["usuarios"]["total"] > 0  # el admin mismo cuenta

    def test_suma_solo_pagos_aprobados(
        self, client, token_admin, cliente, dueno_con_canchas, cancha
    ):
        _reserva(cliente, cancha, date(2026, 9, 20), ESTADO_CONFIRMADA, PAGO_APROBADO, 60000, hora=8)
        _reserva(
            cliente, cancha, date(2026, 9, 21), ESTADO_PENDIENTE_PAGO, PAGO_PENDIENTE, 60000, hora=10
        )
        _reserva(
            cliente, cancha, date(2026, 9, 22), ESTADO_PENDIENTE_PAGO, PAGO_RECHAZADO, 60000, hora=12
        )

        ingresos = client.get("/api/reporte", headers=_auth(token_admin)).get_json()["ingresos"]
        assert ingresos["total"] == 60000

    def test_una_reserva_cancelada_con_pago_aprobado_sigue_siendo_ingreso(
        self, client, token_admin, cliente, dueno_con_canchas, cancha
    ):
        """Cancelar no reembolsa (§3.2): el dinero entró y el reporte no lo borra."""
        _reserva(cliente, cancha, date(2026, 9, 20), ESTADO_CANCELADA, PAGO_APROBADO, 60000)

        reporte = client.get("/api/reporte", headers=_auth(token_admin)).get_json()
        assert reporte["ingresos"]["total"] == 60000
        assert reporte["reservas"]["por_estado"][ESTADO_CANCELADA] == 1

    def test_agrupa_por_cancha_con_el_nombre_para_la_grafica(
        self, client, token_admin, cliente, dueno_con_canchas, cancha
    ):
        _reserva(cliente, cancha, date(2026, 9, 20), ESTADO_CONFIRMADA, PAGO_APROBADO, 60000)

        reporte = client.get("/api/reporte", headers=_auth(token_admin)).get_json()
        por_cancha = {c["nombre"]: c for c in reporte["ingresos"]["por_cancha"]}

        assert por_cancha["Cancha Prueba"]["monto"] == 60000
        assert por_cancha["Cancha Prueba"]["reservas"] == 1
        assert por_cancha["Cancha Prueba"]["cancha_id"] == cancha.id
        # Una cancha sin reservas no aparece: el admin no necesita etiquetas de ceros.
        assert "Cancha De Otro" not in por_cancha

    def test_agrupa_por_dia_de_reserva(self, client, token_admin, cliente, dueno_con_canchas, cancha):
        hoy = date.today()
        _reserva(cliente, cancha, hoy, ESTADO_CONFIRMADA, PAGO_APROBADO, 60000, hora=8)
        _reserva(cliente, cancha, hoy - timedelta(days=1), ESTADO_CONFIRMADA, PAGO_APROBADO, 40000, hora=12)

        reporte = client.get("/api/reporte", headers=_auth(token_admin)).get_json()
        por_dia = reporte["ingresos"]["por_dia"]
        por_fecha = {d["fecha"]: d for d in por_dia}

        assert por_fecha[hoy.isoformat()] == {
            "fecha": hoy.isoformat(),
            "monto": 60000,
            "reservas": 1,
        }
        assert por_fecha[(hoy - timedelta(days=1)).isoformat()]["monto"] == 40000

    def test_los_conteos_de_reservas_salen_por_estado(
        self, client, token_admin, cliente, dueno_con_canchas, cancha
    ):
        _reserva(cliente, cancha, date(2026, 9, 20), ESTADO_CONFIRMADA, PAGO_APROBADO, hora=8)
        _reserva(cliente, cancha, date(2026, 9, 21), ESTADO_CANCELADA, PAGO_APROBADO, hora=10)
        _reserva(cliente, cancha, date(2026, 9, 22), ESTADO_PENDIENTE_PAGO, PAGO_PENDIENTE, hora=12)

        reservas = client.get("/api/reporte", headers=_auth(token_admin)).get_json()["reservas"]

        assert reservas["total"] == 3
        assert reservas["por_estado"] == {
            ESTADO_CONFIRMADA: 1,
            ESTADO_CANCELADA: 1,
            ESTADO_PENDIENTE_PAGO: 1,
        }

    def test_cuenta_usuarios_por_rol_y_los_inactivos(
        self, client, token_admin, cliente, dueno_con_canchas
    ):
        client.patch(
            f"/api/usuarios/{cliente.id}/rol", json={"activo": False}, headers=_auth(token_admin)
        )

        usuarios = client.get("/api/reporte", headers=_auth(token_admin)).get_json()["usuarios"]

        assert usuarios["por_rol"][ROL_CLIENTE] == 1
        assert usuarios["por_rol"][ROL_DUENO] == 2  # dueno_con_canchas + dueno_otro
        assert usuarios["por_rol"]["admin"] == 1
        assert usuarios["inactivos"] == 1
        assert usuarios["total"] == 4

    def test_el_reporte_conserva_el_historico_de_las_canchas_dadas_de_baja(
        self, client, token_admin, cliente, dueno_con_canchas
    ):
        """Una cancha de baja hizo ingresos igual, y ocultarla haría que la suma de la
        gráfica no cuadrara con el total de arriba: el admin lo leería como un bug."""
        baja = Cancha.query.filter_by(nombre="Cancha De Baja").one()
        horario = Horario(cancha_id=baja.id, dia=1, hora_inicio=time(8, 0), hora_fin=time(10, 0), tarifa=60000)
        db.session.add(horario)
        db.session.commit()
        reserva = Reserva(
            cliente_id=cliente.id,
            cancha_id=baja.id,
            horario_id=horario.id,
            fecha=date(2026, 9, 20),
            estado=ESTADO_CONFIRMADA,
        )
        db.session.add(reserva)
        db.session.commit()
        db.session.add(Pago(reserva_id=reserva.id, monto=60000, estado=PAGO_APROBADO))
        db.session.commit()

        reporte = client.get("/api/reporte", headers=_auth(token_admin)).get_json()
        assert reporte["ingresos"]["total"] == 60000
        assert [c["nombre"] for c in reporte["ingresos"]["por_cancha"]] == ["Cancha De Baja"]
        # El desglose siempre suma el total: es lo que hace confiable la gráfica.
        assert sum(c["monto"] for c in reporte["ingresos"]["por_cancha"]) == reporte["ingresos"]["total"]

    def test_el_reporte_no_acepta_filtros_que_nadie_pidio(self, client, token_admin):
        """La spec no promete rango de fechas; si alguien lo manda, se ignora en vez de
        devolver un agregado que parezca filtrado."""
        respuesta = client.get("/api/reporte?desde=2000-01-01", headers=_auth(token_admin))
        assert respuesta.status_code == 200

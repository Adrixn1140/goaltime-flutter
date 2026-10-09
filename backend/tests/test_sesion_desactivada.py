"""Una cuenta desactivada no conserva la sesión, en ninguna ruta protegida.

Desactivar es una medida de seguridad, no un estado cosmético: `auth_helpers.con_rol`
responde `401` para que el token de ese usuario deje de servir de inmediato, sin esperar
las 12 h de su expiración, y con un `401` —que es lo único que la app sabe manejar— en vez
de un `403` que la dejaría en una pantalla de errores de permisos que el usuario no puede
arreglar (heuristics.md, HEUR-9).

Este módulo existe porque ese invariante se puede cumplir en unas rutas y no en otras sin
que nada se note. Las primeras versiones sólo lo comprobaban sobre `/api/gestion/canchas`,
una de las rutas que pasaban por `con_rol`, mientras `reservas.py` y `pagos.py` seguían con
`@jwt_required()` y `usuario_del_token()` a pelo: un cliente desactivado perdía la gestión
y conservaba el catálogo, las reservas y el pago. El criterio de `spec.md` estaba marcado
en verde y el agujero estaba abierto, porque un test que vigila una sola ruta no vigila la
regla.

Por eso el barrido es **parametrizado sobre el inventario completo** y no sobre una lista
de casos escritos a mano: `test_el_barrido_cubre_toda_ruta_nueva` obliga a que cada ruta
nueva se clasifique como protegida o como pública. Añadir un endpoint sin decidir qué es
rompe la suite en vez de colarse por el hueco.
"""

import re

import pytest

from extensions import db

PASSWORD = "Goaltime123!"

# (rol con el que se entra, método, ruta, cuerpo)
#
# Los ids son inventados a propósito: `con_rol` responde el `401` antes de que la vista
# toque la base, así que el barrido no necesita las fixtures `cancha`/`horario` ni una
# reserva real. Los cuerpos, en cambio, son válidos: si el filtro de sesión desapareciera,
# la petición tiene que poder llegar lejos de verdad. Un `400` por validación no
# demostraría el agujero, sólo lo taparía.
RUTAS_PROTEGIDAS = [
    ("cliente", "get", "/api/equipos", None),
    ("cliente", "post", "/api/equipos", {"nombre": "Equipo Prueba"}),
    ("cliente", "get", "/api/equipos/999999", None),
    ("cliente", "post", "/api/equipos/999999/jugadores",
     {"nombre": "Ana", "apellido": "Prueba", "documento": "0001234567", "celular": "3000000000"}),
    ("dueno", "get", "/api/gestion/canchas", None),
    ("dueno", "post", "/api/gestion/canchas", {"nombre": "Cancha Nueva", "ubicacion": "Cra 5 #5-5"}),
    ("dueno", "patch", "/api/gestion/canchas/999999", {"nombre": "Otro nombre"}),
    ("dueno", "delete", "/api/gestion/canchas/999999", None),
    ("dueno", "get", "/api/gestion/canchas/999999/horarios", None),
    (
        "dueno",
        "post",
        "/api/gestion/canchas/999999/horarios",
        {"dia": 0, "hora_inicio": "08:00", "hora_fin": "10:00", "tarifa": 40000},
    ),
    (
        "dueno",
        "patch",
        "/api/gestion/canchas/999999/horarios/999999",
        {"hora_fin": "11:00", "tarifa": 70000},
    ),
    ("dueno", "delete", "/api/gestion/canchas/999999/horarios/999999", None),
    ("dueno", "get", "/api/gestion/canchas/999999/reservas", None),
    ("dueno", "patch", "/api/gestion/reservas/999999", {"accion": "confirmar"}),
    ("admin", "get", "/api/usuarios", None),
    ("admin", "patch", "/api/usuarios/999999/rol", {"rol": "cliente"}),
    ("admin", "get", "/api/reporte", None),
    (
        "cliente",
        "post",
        "/api/reservas",
        {"cancha_id": 999999, "horario_id": 999999, "fecha": "2026-09-28"},
    ),
    ("cliente", "get", "/api/mis-reservas", None),
    ("cliente", "post", "/api/pagos/checkout", {"reserva_id": 999999}),
    ("cliente", "get", "/api/pagos/999999", None),
    ("cliente", "post", "/api/pagos/999999/simular", {"resultado": "aprobado"}),
    # El asistente entra aquí por `con_rol`, como cualquier otra ruta protegida: una
    # cuenta desactivada que puede seguir preguntando canchas libres es una sesión viva.
    ("cliente", "post", "/api/asistente", {"mensaje": "quiero jugar mañana"}),
]

# Rutas que NO pasan por `con_rol`, con el motivo de cada una. `/api/logout` es la
# única autenticada que se queda en `@jwt_required()`, y la razón es que desactivar una
# cuenta no puede cerrar la puerta de salida: si no, el usuario desactivado no podría
# borrar el token que tiene guardado y la app lo dejaría reintentando en cada llamada.
RUTAS_PUBLICAS = {
    ("GET", "/api/canchas"),
    ("GET", "/api/disponibilidad"),
    ("GET", "/api/health"),
    ("POST", "/api/login"),
    ("POST", "/api/register"),
    ("POST", "/api/pagos/webhook"),
    ("POST", "/api/logout"),
}

_ID = re.compile(r"<(?:int:|path:)?\w+>")


def _concreta(regla):
    """`<int:cancha_id>` → `999999`: los ids del barrido y los del `url_map` tienen que
    coincidir para que la comparación del guardián signifique algo."""

    def sustituir(_coincidencia):
        return "999999" if _coincidencia.group(0).startswith("<int:") else "x"

    return _ID.sub(sustituir, regla)


def _ids(caso):
    rol, metodo, ruta, _cuerpo = caso
    return f"{rol}-{metodo}-{ruta.removeprefix('/api/').replace('/', '-')}"


@pytest.mark.parametrize("caso", RUTAS_PROTEGIDAS, ids=_ids)
def test_cuenta_desactivada_no_conserva_la_sesion(client, request, caso):
    """Con el token ya emitido, desactivar la cuenta cierra el acceso a cada ruta protegida.

    El orden importa y es el del ataque: primero se entra, después se desactiva. Si se
    invirtiera, el `403` del login (`auth.py:98`) corta antes y la prueba no mediría nada
    de lo que dice medir.
    """
    rol, metodo, ruta, cuerpo = caso
    usuario = request.getfixturevalue(rol)
    token = _login(client, usuario.email)
    _desactivar(usuario)

    respuesta = _llamar(client, metodo, ruta, token, cuerpo)

    assert respuesta.status_code == 401, respuesta.get_json()
    assert "desactivada" in respuesta.get_json()["error"]["mensaje"]


def test_cerrar_sesion_sigue_sirviendo_con_la_cuenta_desactivada(client, cliente):
    """La excepción de `logout` es deliberada y está probada, no es un olvido.

    Sin esto, alguien que lea el barrido podría "arreglar" la inconsistencia pasando
    `logout` por `con_rol` y dejaría al usuario desactivado sin poder cerrar sesión.
    """
    token = _login(client, cliente.email)
    _desactivar(cliente)

    respuesta = client.post("/api/logout", headers=_auth(token))

    assert respuesta.status_code == 204


def test_el_barrido_cubre_toda_ruta_nueva(app):
    """Ninguna ruta puede entrar al API sin pasar por el barrido o por la lista de públicas.

    Es el guardián del propio guardián. Si alguien añade un endpoint y no lo clasifica,
    falla aquí con el inventario como diferencia, que es la información que hace falta para
    decidir; si lo clasifica como protegida y el barrido no lo cubre, también falla.
    """
    inventario = _rutas_de_api(app)
    clasificadas = RUTAS_PUBLICAS | {(metodo.upper(), ruta) for _r, metodo, ruta, _c in RUTAS_PROTEGIDAS}

    assert inventario == clasificadas


# --------------------------------------------------------------------------- ayudantes
def _login(client, email, password=PASSWORD):
    respuesta = client.post("/api/login", json={"email": email, "password": password})
    assert respuesta.status_code == 200, respuesta.get_json()
    return respuesta.get_json()["access_token"]


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _desactivar(usuario):
    """Desactiva en la base y no por `PATCH /api/usuarios/{id}/rol`.

    Lo que se prueba es "una cuenta desactivada recibe 401", no "el admin puede
    desactivar", que es otra cosa y ya tiene sus tests en `test_admin.py`. Además, pasar por
    el endpoint obligaría a que la ruta de admin se protegiera contra sí misma.
    """
    usuario.activo = False
    db.session.commit()


def _llamar(client, metodo, ruta, token, cuerpo):
    """`json` sólo cuando hay cuerpo: mandar `null` como JSON no es lo mismo que no mandar."""
    if cuerpo is None:
        return getattr(client, metodo)(ruta, headers=_auth(token))
    return getattr(client, metodo)(ruta, headers=_auth(token), json=cuerpo)


def _rutas_de_api(app):
    """Las rutas de `/api` con los ids ya puestos, para compararlas con el barrido."""
    vistas = set()
    for regla in app.url_map.iter_rules():
        if not regla.rule.startswith("/api/"):
            continue
        ruta = _concreta(regla.rule)
        for metodo in regla.methods - {"HEAD", "OPTIONS"}:
            vistas.add((metodo, ruta))
    return vistas

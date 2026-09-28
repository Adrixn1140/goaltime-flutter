"""Tests del asistente de lenguaje natural (spec.md 3.6).

Contra el motor `mock`, que es la razón por la que esta suite puede correr en CI: si
estos tests dependieran de Ollama o de Gemini, no serían tests, serían integraciones con
un servicio de terceros que fallan cuando el servicio está ocupado.

Lo que se verifica, y por qué es lo importante:

- Que **una sugerencia no se puede inventar**: cada `horario_id` de la respuesta existe en
  la base y estaba libre. Es la propiedad que justifica las dos vueltas del asistente.
- Que una cancha **inexistente** no produce sugerencias, sino un `detalle` que el modelo
  va a decir en voz alta. Es el mecanismo que impide el "te Recommendé Las Palmeras" cuando
  no existe.
- Que un slot **ocupado o ya pasado** no se sugiere, aunque la franja y el día encajen.
- Los **códigos de §3.6**: 400, 401, 403, 422 y 502.
"""

from datetime import date, time, timedelta

import pytest

from blueprints.asistente import LIMITE_SUGERENCIAS
from dominio.disponibilidad import FRANJA_NOCHE
from extensions import db
from models import ESTADO_CONFIRMADA, Horario, Reserva
from motores import obtener_motor
from motores.base import FalloMotor, MotorLLM, PeticionHerramienta
from motores.mock import MockMotor
from tests.conftest import _crear_cliente

PASSWORD = "Goaltime123!"


# --- fixtures de sesión, siguiendo la convención de los demás archivos -------------------


@pytest.fixture()
def token_cliente(client, cliente):
    return _login(client, cliente.email)


@pytest.fixture()
def token_dueno(client, dueno):
    return _login(client, dueno.email)


def _login(client, email, password=PASSWORD):
    respuesta = client.post("/api/login", json={"email": email, "password": password})
    return respuesta.get_json()["access_token"]


@pytest.fixture(autouse=True)
def _motor_por_defecto(app):
    """Motor `mock` que reconoce la cancha del resto de los tests.

    Autouse porque todos los tests del endpoint necesitan un motor y tener que pedirlo
    explícitamente en cada uno sólo añade ruido: el punto de estos tests es el endpoint y
    la herramienta, no la elección de motor, que tienen sus propios tests más abajo.
    """
    app.config["LLM_PROVEEDOR"] = "mock"
    app.config["LLM_MOCK_CANCHAS"] = ("Cancha Prueba",)
    from motores import limpiar_cache

    limpiar_cache()
    yield
    limpiar_cache()


# --- helpers de datos --------------------------------------------------------------------


def _crear_horario(cancha, dia, hora_inicio, hora_fin=(10, 0), tarifa=60000):
    horario = Horario(
        cancha_id=cancha.id,
        dia=dia,
        hora_inicio=time(*hora_inicio),
        hora_fin=time(*hora_fin),
        tarifa=tarifa,
    )
    db.session.add(horario)
    db.session.commit()
    return horario


def _reservar(horario, fecha, cliente):
    db.session.add(
        Reserva(
            horario_id=horario.id,
            cancha_id=horario.cancha_id,
            cliente_id=cliente.id,
            fecha=fecha,
            estado=ESTADO_CONFIRMADA,
        )
    )
    db.session.commit()


def _manana():
    return date.today() + timedelta(days=1)


def _post(client, token, mensaje):
    return client.post(
        "/api/asistente", json={"mensaje": mensaje}, headers={"Authorization": f"Bearer {token}"}
    )


# --- la propiedad que justifica el diseño: nada inventado -------------------------------


def test_sugerencia_tiene_horario_id_real(client, token_cliente, app, cancha, dueno):
    """El `horario_id` que sale de la respuesta existe en la base y está libre.

    Este es el test más importante del archivo. Un `horario_id` inventado produce un
    `409` al reservar, y la persona ve que el asistente le ofreció algo que no existe: la
    falla más visible y más difícil de recuperar del producto.
    """
    dia = _manana().weekday()
    horario = _crear_horario(cancha, dia, (18, 0), (19, 0), tarifa=45000)

    respuesta = _post(client, token_cliente, "quiero jugar mañana en la noche")
    assert respuesta.status_code == 200
    datos = respuesta.get_json()

    assert len(datos["sugerencias"]) == 1
    sugerencia = datos["sugerencias"][0]
    assert sugerencia["horario_id"] == horario.id
    assert sugerencia["cancha_id"] == cancha.id
    assert sugerencia["cancha"] == cancha.nombre
    assert sugerencia["fecha"] == _manana().isoformat()
    assert sugerencia["hora_inicio"] == "18:00"
    assert sugerencia["tarifa"] == 45000.0

    # Y que ese horario existe de verdad, no sólo que los números cuadran.
    assert db.session.get(Horario, sugerencia["horario_id"]) is horario


def test_sugerencia_respeta_el_tope(client, token_cliente, app, cancha, dueno):
    """Más horarios de los que el endpoint decide devolver, no llega a la respuesta.

    El tope lo pone el backend y no el modelo: si lo pusiera el modelo, el mismo mensaje
    daría respuestas de distinto tamaño según el proveedor.
    """
    dia = _manana().weekday()
    for hora in (8, 9, 10, 11, 12):
        _crear_horario(cancha, dia, (hora, 0), (hora + 1, 0))

    datos = _post(client, token_cliente, "quiero jugar mañana").get_json()
    assert len(datos["sugerencias"]) == LIMITE_SUGERENCIAS


def test_slot_ocupado_no_se_sugiere(client, token_cliente, app, cancha, dueno, cliente):
    """Un horario reservado no aparece en las sugerencias, aunque el día y la franja
    encajen. Sugerirlo convertiría al asistente en una fábrica de `409`."""
    dia = _manana().weekday()
    horario = _crear_horario(cancha, dia, (18, 0), (19, 0))
    _reservar(horario, _manana(), cliente)

    datos = _post(client, token_cliente, "quiero jugar mañana en la noche").get_json()
    assert datos["sugerencias"] == []
    assert datos["respuesta"]


def test_slot_transcurrido_no_se_sugiere(client, token_cliente, app, cancha, dueno):
    """Un horario de hoy cuya hora ya pasó no se sugiere.

    Los fixtures de este archivo usan una fecha de mañana justamente para no depender de la
    hora del reloj, así que este caso necesita un caso hecho a mano.
    """
    ahora = date.today()
    # Un horario que empezó hace media hora: siempre en el pasado, sea cual sea la hora.
    if ahora.weekday() in range(7):
        _crear_horario(cancha, ahora.weekday(), (0, 0), (0, 1))

    datos = _post(client, token_cliente, "quiero jugar hoy").get_json()
    for sugerencia in datos["sugerencias"]:
        assert sugerencia["hora_inicio"] != "00:00"


def test_cancha_inexistente_no_produce_sugerencias(
    client, token_cliente, app, cancha, dueno, inyectar_motor
):
    """Nombrar una cancha que no existe da cero sugerencias y un `detalle` que el motor
    puede decir en voz alta. Es lo contrario de recomendar una cancha que no existe.

    El motor se inyecta con el nombre explícito porque el `mock` sólo reconoce nombres que
    conoce: si se le dejara extraer solo, devolvería `cancha` vacía y caería en la cancha
    por defecto, que es otro camino y otro test.
    """
    _crear_horario(cancha, _manana().weekday(), (18, 0), (19, 0))

    inyectar_motor(
        _motor_con_argumentos(
            {
                "cancha": "Cancha Fantasma",
                "fecha": _manana().isoformat(),
                "franja": FRANJA_NOCHE,
            }
        )
    )
    respuesta = _post(client, token_cliente, "quiero jugar en la cancha fantasma")

    assert respuesta.status_code == 200
    datos = respuesta.get_json()
    assert datos["sugerencias"] == []
    assert "no" in datos["respuesta"].lower()


def test_cancha_por_defecto_cuando_no_dijo_ninguna(
    client, token_cliente, app, cancha, dueno
):
    """Si no dijo cancha, el backend le enseña la primera activa, sin preguntar.

    Es una decisión de producto que vive en el backend y no en el prompt: "si no dijo
    cancha, enséñale la primera" es una regla del catálogo, y si dependiera del modelo cada
    proveedor la cumpliría distinto. Y preguntar "¿cuál cancha?" antes de mostrar nada es
    una ronda de más para el caso más común.
    """
    _crear_horario(cancha, _manana().weekday(), (18, 0), (19, 0))

    datos = _post(client, token_cliente, "quiero jugar mañana en la noche").get_json()
    assert [s["cancha_id"] for s in datos["sugerencias"]] == [cancha.id]


def test_cancha_sin_horarios_dice_que_no_hay(client, token_cliente, app, cancha, dueno):
    """Cancha que existe pero no tiene nada libre: cero sugerencias y una respuesta que lo
    dice, en vez de un error."""
    datos = _post(client, token_cliente, "quiero jugar mañana").get_json()
    assert datos["sugerencias"] == []
    assert datos["respuesta"]


def test_franja_filtra_por_hora(client, token_cliente, app, cancha, dueno):
    """`por la noche` no devuelve un horario de las 8 de la mañana."""
    dia = _manana().weekday()
    _crear_horario(cancha, dia, (8, 0), (9, 0))
    noche = _crear_horario(cancha, dia, (20, 0), (21, 0))

    datos = _post(client, token_cliente, "quiero jugar mañana por la noche").get_json()
    assert [s["horario_id"] for s in datos["sugerencias"]] == [noche.id]


# --- códigos de la tabla de §3.6 ---------------------------------------------------------


def test_mensaje_ausente_400(client, token_cliente):
    respuesta = client.post(
        "/api/asistente", json={}, headers={"Authorization": f"Bearer {token_cliente}"}
    )
    assert respuesta.status_code == 400
    assert respuesta.get_json()["error"]["codigo"] == 400


def test_mensaje_vacio_400(client, token_cliente):
    respuesta = _post(client, token_cliente, "   ")
    assert respuesta.status_code == 400


def test_mensaje_no_texto_400(client, token_cliente):
    respuesta = client.post(
        "/api/asistente", json={"mensaje": 42}, headers={"Authorization": f"Bearer {token_cliente}"}
    )
    assert respuesta.status_code == 400


def test_sin_token_401(client):
    assert client.post("/api/asistente", json={"mensaje": "hola"}).status_code == 401


def test_dueño_recibe_403(client, token_dueno):
    """Sólo `cliente` entra. El asistente reserva en nombre de quien pregunta, y quien
    pregunta es un cliente; un dueño que llegara aquí sugeriría sobre el catálogo entero."""
    assert _post(client, token_dueno, "quiero jugar mañana").status_code == 403


def test_admin_recibe_403(client, app):
    token = _login(client, _crear_cliente("admin@asistente.co", "admin").email)
    assert _post(client, token, "quiero jugar mañana").status_code == 403


@pytest.fixture()
def inyectar_motor(monkeypatch):
    """Sustituye el motor del endpoint por uno hecho a mano.

    Se hace por `monkeypatch` y no reasignando el atributo a mano porque `monkeypatch`
    deshace solo al final del test: un `try/finally` olvidado dejaría el endpoint apuntando
    a un motor falso para el resto de la suite, y el síntoma sería un test que pasa solo.
    """
    import blueprints.asistente as modulo

    def _inyectar(motor):
        monkeypatch.setattr(modulo, "obtener_motor", lambda config=None: motor)
        return motor

    return _inyectar


def test_fecha_fuera_de_ventana_422(client, token_cliente, app, inyectar_motor):
    """Una fecha más allá de la ventana de 6 días es `422`, no una lista vacía.

    La diferencia importa: `422` dice "tu pregunta no se puede responder así", y una lista
    vacía diría "no hay canchas", que es una afirmación falsa sobre el catálogo.
    """
    inyectar_motor(
        _motor_con_argumentos(
            {
                "cancha": "",
                "fecha": (date.today() + timedelta(days=30)).isoformat(),
                "franja": "cualquiera",
            }
        )
    )

    respuesta = _post(client, token_cliente, "quiero jugar el próximo mes")
    assert respuesta.status_code == 422
    assert respuesta.get_json()["error"]["codigo"] == 422


def test_franja_invalida_422(client, token_cliente, inyectar_motor):
    inyectar_motor(
        _motor_con_argumentos(
            {"cancha": "", "fecha": date.today().isoformat(), "franja": "madrugada"}
        )
    )
    respuesta = _post(client, token_cliente, "quiero jugar a la madrugada")
    assert respuesta.status_code == 422


def test_motor_caido_502(client, token_cliente, inyectar_motor):
    """Un proveedor que no responde es `502` y su detalle técnico no sale en la respuesta.

    El mensaje genérico es la parte importante: el texto de la excepción puede llevar la
    URL y, con Gemini, el prefijo de la llave, y un `502` con la llave dentro sería una
    fuga de §7.2 por el camino de los errores.
    """

    class _Roto(MotorLLM):
        nombre = "roto"

        def interpretar(self, mensaje):
            raise FalloMotor("conexión a http://localhost:11434/api/chat rechazada")

        def redactar(self, mensaje, resultado):
            raise FalloMotor("no debería llegar aquí")

    inyectar_motor(_Roto())
    respuesta = _post(client, token_cliente, "quiero jugar mañana")

    assert respuesta.status_code == 502
    # Lo que se comprueba es lo que NO sale: la URL interna.
    assert "11434" not in respuesta.get_data(as_text=True)
    assert "asistente" in respuesta.get_json()["error"]["mensaje"].lower()


def test_motor_que_redacta_falla_502(client, token_cliente, app, cancha, dueno, inyectar_motor):
    """Si la consulta funciona pero la redacción falla, también es `502`."""
    _crear_horario(cancha, _manana().weekday(), (18, 0), (19, 0))

    class _CiegoEnLaSegunda(MotorLLM):
        nombre = "ciego"

        def interpretar(self, mensaje):
            return PeticionHerramienta(
                nombre="buscar_disponibilidad",
                argumentos={
                    "cancha": "",
                    "fecha": date.today().isoformat(),
                    "franja": "cualquiera",
                },
            )

        def redactar(self, mensaje, resultado):
            raise FalloMotor("el proveedor se cayó al redactar")

    inyectar_motor(_CiegoEnLaSegunda())
    assert _post(client, token_cliente, "quiero jugar mañana").status_code == 502


def _motor_con_argumentos(argumentos):
    """Motor que siempre pide lo mismo, para probar un caso sin escribir una clase."""
    return _MockDeArgumentos(argumentos)


class _MockDeArgumentos(MockMotor):
    def __init__(self, argumentos):
        super().__init__(canchas=("Cancha Prueba",))
        self._argumentos = argumentos

    def interpretar(self, mensaje):
        return PeticionHerramienta(nombre="buscar_disponibilidad", argumentos=self._argumentos)


def test_saludo_no_dispara_una_busqueda(client, token_cliente, app, cancha, dueno):
    """Un saludo suena a saludo. Si no, el asistente parece un robot que sólo sabe de
    canchas, que es la primera impresión que se queda."""
    _crear_horario(cancha, _manana().weekday(), (18, 0), (19, 0))

    datos = _post(client, token_cliente, "hola").get_json()
    assert datos["sugerencias"] == []


# --- el motor, sin HTTP ------------------------------------------------------------------


def test_mock_por_defecto_es_el_de_los_tests(app):
    """El `mock` es el que permite esta suite; si el default cambia, CI lo avisa aquí."""
    assert obtener_motor(app.config).nombre == "mock"


def test_motores_desconocidos_da_error_de_config(app):
    app.config["LLM_PROVEEDOR"] = "gpt"
    from motores import limpiar_cache

    limpiar_cache()
    with pytest.raises(RuntimeError, match="LLM_PROVEEDOR desconocido"):
        obtener_motor(app.config)


def test_proveedor_desconocido_no_se_importa(app):
    """Con `LLM_PROVEEDOR=mock`, importar la app no debe requerir `httpx` ni llaves.

    Es la propiedad que hace que la instalación por omisión no dependa de ningún
    proveedor: si importar `motores` arrastrara `httpx` y la llave de Gemini, la instalación
    normal empezaría a exigir cosas que no usa.
    """
    app.config["LLM_PROVEEDOR"] = "mock"
    from motores import limpiar_cache

    limpiar_cache()
    assert obtener_motor(app.config).nombre == "mock"

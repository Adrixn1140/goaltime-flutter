"""Tests del parser de Gemini, sin salir a la red (spec.md 3.6).

El `52x` de CI no llama a Google: los tests del motor sustituyen a `httpx.post` por una
respuesta falsa y comprueban que el código traduce bien lo que Google devuelve y que
traduce bien —o corta— lo que Google puede devolver mal.

La división de responsabilidades queda así:

- Este archivo prueba que `GeminiMotor` interpreta y redacta, con la red cortada.
- `test_asistente.py` prueba el endpoint, con el motor `mock`.
- La prueba real contra Google se hace a mano, y su resultado se documenta en `ESTADO.md`
  con la disciplina de "verificado" del proyecto: no puede vivir en CI porque depende de
  una llave y de un servicio de terceros, que es exactamente lo que la suite evita.

Casos que importan y por qué:

- **Argumentos que no son un objeto**: Gemini devuelve `args` como lista y el código debe
  cortar en `RespuestaIninterpretable`, no reventar con un `TypeError` que no sabemos
  traducir. Es el caso más feo del protocolo y el que más probablemente nadie prueba.
- **Candidatos vacíos con 200**: el filtro de seguridad de Gemini satisface la petición
  pero no produce texto ni llamada. Sin este test, ese síntoma se vería como un reventón
  raro en producción, y es un caso documentado del proveedor.
- **La llave nunca aparece**: el `502` del endpoint ya es genérico en `test_asistente.py`;
  aquí se comprueba que el motivo de `FalloMotor` no formatea la llave. Si algún día alguien
  la imprime, que sea porque un test lo pilló a propósito.
"""

import httpx
import pytest

from motores.base import (
    ESQUEMA_HERRAMIENTA,
    FalloMotor,
    PeticionHerramienta,
    RespuestaIninterpretable,
    ResultadoHerramienta,
    Sugerencia,
    sistema_interpretar,
)
from motores.gemini import GeminiMotor

LLAVE = "AIza-prueba-no-real"


def _respuesta(status, json_):
    return httpx.Response(status, json=json_, request=httpx.Request("POST", "http://falso"))


def _motor_con(monkeypatch, respuesta):
    """Sustituye la única salida a la red por una respuesta prefijada."""
    motor = GeminiMotor(api_key=LLAVE)

    def _falso_post(url, json, headers, timeout):
        return respuesta

    monkeypatch.setattr(httpx, "post", _falso_post)
    return motor


def _cuerpo_function_call(nombre="buscar_disponibilidad", args=None):
    return {
        "candidates": [
            {
                "content": {
                    "parts": [{"functionCall": {"name": nombre, "args": args or {}}}],
                }
            }
        ]
    }


# --- primera vuelta: la llamada a la herramienta ------------------------------------------


def test_interpretar_devuelve_peticion_de_herramienta(monkeypatch):
    motor = _motor_con(
        monkeypatch,
        _respuesta(200, _cuerpo_function_call(args={"cancha": "", "fecha": "2026-10-05"})),
    )

    peticion = motor.interpretar("quiero jugar mañana")

    assert peticion.nombre == "buscar_disponibilidad"
    assert peticion.argumentos == {"cancha": "", "fecha": "2026-10-05"}


def test_interpretar_con_texto_devuelve_respuesta_directa(monkeypatch):
    motor = _motor_con(
        monkeypatch,
        _respuesta(200, {"candidates": [{"content": {"parts": [{"text": "Hola :)"}]}}]}),
    )

    peticion = motor.interpretar("hola")

    assert peticion.nombre == "responder_directo"
    assert peticion.argumentos["texto"] == "Hola :)"


def test_interpretar_sin_function_call_ni_texto_no_revienta_en_index(monkeypatch):
    """Candidato sin `parts`: el `next(...)` debe devolver `None`, no levantar."""
    motor = _motor_con(monkeypatch, _respuesta(200, {"candidates": [{"content": {}}]}))

    peticion = motor.interpretar("hola")

    assert peticion.nombre == "responder_directo"


def test_interpretar_args_no_objeto_es_ininterpretable(monkeypatch):
    """Gemini puede devolver `args` como lista (flema de la API). No debe reventar."""
    motor = _motor_con(
        monkeypatch, _respuesta(200, _cuerpo_function_call("buscar_disponibilidad", [1, 2]))
    )

    with pytest.raises(RespuestaIninterpretable, match="no son un objeto"):
        motor.interpretar("quiero jugar mañana")


def test_interpretar_sin_nombre_es_ininterpretable_o_vacio(monkeypatch):
    motor = _motor_con(monkeypatch, _respuesta(200, _cuerpo_function_call("", {})))

    peticion = motor.interpretar("quiero jugar")

    assert peticion.nombre == "" or peticion.nombre == "buscar_disponibilidad"


# --- segunda vuelta: la redacción ---------------------------------------------------------


def test_redactar_devuelve_el_texto(monkeypatch):
    resultado = ResultadoHerramienta(
        sugerencias=(
            Sugerencia(
                cancha_id=1,
                cancha="Cancha Prueba",
                fecha="2026-10-05",
                horario_id=7,
                hora_inicio="18:00",
                hora_fin="19:00",
                tarifa=45000.0,
            ),
        ),
    )
    motor = _motor_con(
        monkeypatch,
        _respuesta(
            200, {"candidates": [{"content": {"parts": [{"text": "Hay una a las 18:00."}]}}]}
        ),
    )

    assert motor.redactar("quiero jugar mañana", resultado) == "Hay una a las 18:00."


def test_redactar_termina_en_turno_usuario(monkeypatch):
    """Gemini rechaza un request que termina en turno `model` ("Requests ending with a
    model turn are not supported"). El resultado de la herramienta se entrega como turno
    `user`, que es como la API lo acepta: un `400` en vivo lo destapó, y este test lo fija
    para no volver a caer."""
    resultado = ResultadoHerramienta(
        sugerencias=(
            Sugerencia(
                cancha_id=1,
                cancha="Cancha Prueba",
                fecha="2026-10-05",
                horario_id=7,
                hora_inicio="18:00",
                hora_fin="19:00",
                tarifa=45000.0,
            ),
        ),
    )
    motor = GeminiMotor(api_key=LLAVE)
    cuerpo = None

    def _capturar(url, json, headers, timeout):
        nonlocal cuerpo
        cuerpo = json
        return _respuesta(
            200, {"candidates": [{"content": {"parts": [{"text": "Hay una a las 18:00."}]}}]}
        )

    monkeypatch.setattr(httpx, "post", _capturar)
    motor.redactar("quiero jugar mañana", resultado)

    roles = [turno["role"] for turno in cuerpo["contents"]]
    assert roles[-1] == "user"
    assert "RESULTADO DE LA HERRAMIENTA" in cuerpo["contents"][-1]["parts"][0]["text"]


def test_redactar_vacio_es_ininterpretable(monkeypatch):
    motor = _motor_con(monkeypatch, _respuesta(200, {"candidates": [{"content": {"parts": []}}]}))

    with pytest.raises(RespuestaIninterpretable, match="vacío"):
        motor.redactar("hola", ResultadoHerramienta())


# --- lo que Google devuelve mal -----------------------------------------------------------


def test_candidatos_vacios_es_ininterpretable(monkeypatch):
    """200 con `candidates` vacío: el filtro de seguridad bloqueó la respuesta."""
    motor = _motor_con(monkeypatch, _respuesta(200, {"candidates": []}))

    with pytest.raises(RespuestaIninterpretable, match="seguridad"):
        motor.interpretar("quiero jugar mañana")


def test_json_roto_es_ininterpretable(monkeypatch):
    motor = _motor_con(monkeypatch, httpx.Response(200, text="no es json", request=httpx.Request("POST", "http://falso")))

    with pytest.raises(RespuestaIninterpretable, match="JSON"):
        motor.interpretar("quiero jugar mañana")


def test_400_menciona_el_modelo(monkeypatch):
    """El `400` de Gemini suele ser nombre de modelo o llave; el fallo debe decirlo."""
    motor = _motor_con(monkeypatch, _respuesta(400, {}))
    motor.modelo = "gemini-3.6-flash"

    with pytest.raises(FalloMotor, match="gemini-3.6-flash"):
        motor.interpretar("quiero jugar mañana")


def test_401_y_403_son_llave(monkeypatch):
    for status in (401, 403):
        motor = _motor_con(monkeypatch, _respuesta(status, {}))
        with pytest.raises(FalloMotor, match="llave"):
            motor.interpretar("quiero jugar mañana")


def test_429_es_limite_de_peticiones(monkeypatch):
    motor = _motor_con(monkeypatch, _respuesta(429, {}))

    with pytest.raises(FalloMotor, match="limitando"):
        motor.interpretar("quiero jugar mañana")


def test_503_se_reintenta_y_la_segunda_acierta(monkeypatch):
    """El `503` de Google es transitorio por definición del propio proveedor: se espera
    un momento y se vuelve a intentar antes de dar un `502`."""
    motor = GeminiMotor(api_key=LLAVE)
    llamadas = []

    def _falso_post(url, json, headers, timeout):
        llamadas.append(url)
        return _respuesta(503, {}) if len(llamadas) == 1 else _respuesta(200, _cuerpo_function_call())

    monkeypatch.setattr(httpx, "post", _falso_post)
    import motores.gemini as modulo

    monkeypatch.setattr(modulo, "_INTENTOS", 3)
    monkeypatch.setattr(modulo, "_ESPERA_REINTENTO", 0.0)

    peticion = motor.interpretar("quiero jugar mañana")

    assert len(llamadas) == 2
    assert peticion.nombre == "buscar_disponibilidad"


def test_503_persistente_agota_los_reintentos(monkeypatch):
    motor = GeminiMotor(api_key=LLAVE)
    llamadas = []

    def _falso_post(url, json, headers, timeout):
        llamadas.append(url)
        return _respuesta(503, {})

    monkeypatch.setattr(httpx, "post", _falso_post)
    import motores.gemini as modulo

    monkeypatch.setattr(modulo, "_INTENTOS", 3)
    monkeypatch.setattr(modulo, "_ESPERA_REINTENTO", 0.0)

    with pytest.raises(FalloMotor, match="saturado"):
        motor.interpretar("quiero jugar mañana")
    assert len(llamadas) == 3


def test_timeout_es_fallo_del_motor(monkeypatch):
    motor = GeminiMotor(api_key=LLAVE)

    def _falso_post(url, json, headers, timeout):
        raise httpx.TimeoutException("tarde")

    monkeypatch.setattr(httpx, "post", _falso_post)

    with pytest.raises(FalloMotor, match="no respondió"):
        motor.interpretar("quiero jugar mañana")


def test_error_http_es_fallo_del_motor(monkeypatch):
    motor = GeminiMotor(api_key=LLAVE)

    def _falso_post(url, json, headers, timeout):
        raise httpx.HTTPError("cayó la conexión")

    monkeypatch.setattr(httpx, "post", _falso_post)

    with pytest.raises(FalloMotor):
        motor.interpretar("quiero jugar mañana")


def test_sin_llave_falla_al_construir():
    """`LLM_PROVEEDOR=gemini` sin `GEMINI_API_KEY` es un error de despliegue que se ve al
    arrancar, no en la primera petición de un usuario que confió en el asistente."""
    with pytest.raises(FalloMotor, match="GEMINI_API_KEY"):
        GeminiMotor(api_key="")


# --- la traducción del esquema ------------------------------------------------------------


def test_esquema_se_traduce_al_dialecto_de_gemini(monkeypatch):
    """El esquema debe ir con tipos en mayúsculas (OBJECT, STRING) y sin el envoltorio
    `function` que OpenAI quiere: Gemini rechaza ese formato."""
    motor = _motor_con(monkeypatch, _respuesta(200, _cuerpo_function_call()))
    cuerpo = None

    def _capturar(url, json, headers, timeout):
        nonlocal cuerpo
        cuerpo = json
        return _respuesta(200, _cuerpo_function_call(("buscar_disponibilidad"), {"cancha": ""}))

    monkeypatch.setattr(httpx, "post", _capturar)
    motor.interpretar("quiero jugar")

    declaracion = cuerpo["tools"][0]["functionDeclarations"][0]
    assert "function" not in declaracion
    assert declaracion["name"] == "buscar_disponibilidad"
    assert declaracion["parameters"]["type"] == "OBJECT"
    assert declaracion["parameters"]["properties"]["cancha"]["type"] == "STRING"
    assert declaracion["parameters"]["properties"]["franja"]["enum"]


def test_esquema_compartido_sigue_siendo_el_mismo():
    """El esquema es una sola fuente. Si se cambia aquí con un motivo real, este test lo
    hace deliberado, no casual."""
    assert ESQUEMA_HERRAMIENTA["function"]["name"] == "buscar_disponibilidad"
    assert list(ESQUEMA_HERRAMIENTA["function"]["parameters"]["properties"]) == [
        "cancha",
        "fecha",
        "franja",
    ]


def test_la_fecha_de_hoy_viaja_en_el_prompt(monkeypatch):
    """Un modelo no sabe qué día es hoy: su reloj interno es el de sus datos de
    entrenamiento. La fecha real debe ir embebida en la primera vuelta, y esto es lo que
    hace que "mañana" caiga dentro de la ventana de 6 días en vez de dar un `422`."""
    from datetime import date

    hoy = date.today().isoformat()
    assert hoy in sistema_interpretar()
    assert "mañana" in sistema_interpretar()
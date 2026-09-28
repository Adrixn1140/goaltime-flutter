"""Motor que habla con Gemini (spec.md 3.6).

Gemini es la alternativa en la nube a Ollama: mismo contrato, otra API. La diferencia que
más pesa aquí no es el modelo sino el **esquema**: Gemini no acepta el formato de
herramientas de OpenAI, sino uno plano y con los tipos en mayúsculas. Traducir el esquema
en la frontera es preferible a mantener dos copias de la definición de la herramienta,
porque dos copias se desincronizan y el síntoma es que un proveedor inventa argumentos que
el otro sí entiende.

Igual que con Ollama, `httpx` se importa dentro de los métodos: sin la llave y sin
`LLM_PROVEEDOR=gemini`, nadie debería necesitar el cliente HTTP.
"""

from motores.base import (
    ESQUEMA_HERRAMIENTA,
    REGLAS_REDACCION,
    SYSTEM_PROMPT,
    FalloMotor,
    MotorLLM,
    PeticionHerramienta,
    RespuestaIninterpretable,
    describir_resultado,
    sistema_interpretar,
)

URL_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
TIMEOUT_SEGUNDOS = 60.0

#: Reintentos ante el `503` "high demand" de Google, que el propio mensaje del proveedor
#: describe como transitorio. No son para cualquier error: un `400` se mantiene en 0
#: intentos. El `time.sleep` sólo se duerme entre reintentos, y la espera crece con el
#: número de intento (`_ESPERA_REINTENTO`, `2×`, `3×`...) para no martillar a Google en
#: pleno pico.
_INTENTOS = 3
_ESPERA_REINTENTO = 0.5

#: Códigos que Google usa para épocas de alta demanda o límite de peticiones. El 503 con
#: "high demand" y el 429 "limitando" son transitorios por diseño; un `500` también.
_TRANSPARENTES = frozenset({429, 500, 502, 503})

#: Gemini no quiere el papel de `system` en `contents`: va aparte, en `systemInstruction`.
#: Ponerlo como un `user` más es la forma habitual de que Gemini lo ignore.


class GeminiMotor(MotorLLM):
    """Proveedor en la nube de Google."""

    nombre = "gemini"

    def __init__(self, api_key, modelo="gemini-3.6-flash", timeout=TIMEOUT_SEGUNDOS):
        if not api_key:
            # Falla al construir y no al llamar: un `LLM_PROVEEDOR=gemini` sin llave es un
            # error de despliegue, y conviene verlo al arrancar, no en la primera petición
            # de un usuario que sí confió en que el asistente funcionaba.
            raise FalloMotor(
                "LLM_PROVEEDOR=gemini pero GEMINI_API_KEY está vacía. "
                "Ponla en `.env` o usa LLM_PROVEEDOR=ollama."
            )
        self.api_key = api_key
        self.modelo = modelo
        self.timeout = timeout

    def interpretar(self, mensaje):
        cuerpo = {
            "systemInstruction": {"parts": [{"text": sistema_interpretar()}]},
            "contents": [_mensaje_usuario(mensaje)],
            "tools": [{"functionDeclarations": [_declaracion_gemini()]}],
        }
        partes = self._generar(cuerpo)

        llamada = next((p["functionCall"] for p in partes if "functionCall" in p), None)
        if llamada is None:
            texto = "".join(p.get("text", "") for p in partes).strip()
            return PeticionHerramienta(nombre="responder_directo", argumentos={"texto": texto})

        argumentos = llamada.get("args") or {}
        if not isinstance(argumentos, dict):
            raise RespuestaIninterpretable("Los argumentos de la herramienta no son un objeto.")
        return PeticionHerramienta(nombre=llamada.get("name") or "", argumentos=argumentos)

    def redactar(self, mensaje, resultado):
        cuerpo = {
            "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT + "\n\n" + REGLAS_REDACCION}]},
            "contents": [
                _mensaje_usuario(mensaje),
                # Gemini no admite un request que termina en turno `model` ("Requests ending
                # with a model turn are not supported"): el resultado de la herramienta se
                # entrega como turno `user` y la conversación termina ahí.
                _mensaje_usuario(f"RESULTADO DE LA HERRAMIENTA:\n{describir_resultado(resultado)}"),
            ],
        }
        partes = self._generar(cuerpo)
        texto = "".join(p.get("text", "") for p in partes).strip()
        if not texto:
            raise RespuestaIninterpretable("Gemini respondió vacío al redactar.")
        return texto

    def _generar(self, cuerpo):
        import time

        import httpx

        url = f"{URL_BASE}/{self.modelo}:generateContent"
        for intento in range(1, _INTENTOS + 1):
            try:
                respuesta = httpx.post(
                    url,
                    json=cuerpo,
                    headers={"x-goog-api-key": self.api_key},
                    timeout=self.timeout,
                )
            except httpx.TimeoutException as exc:
                raise FalloMotor(f"Gemini no respondió en {self.timeout:.0f} s.") from exc
            except httpx.HTTPError as exc:
                raise FalloMotor("No se pudo hablar con Gemini.") from exc

            if respuesta.status_code in _TRANSPARENTES and intento < _INTENTOS:
                # Google devuelve 503/429/5xx cuando el modelo tiene un pico de demanda o
                # está limitando, y los etiqueta él mismo como transitorios ("spikes in
                # demand are usually temporary"). Antes de darle un 502 a la persona merece
                # un segundo intento con una espera corta; no es un error del usuario.
                time.sleep(_ESPERA_REINTENTO * intento)
                continue
            elif respuesta.status_code in _TRANSPARENTES:
                # Último intento y sigue transitorio: se sale del bucle con el diagnóstico
                # correcto en vez de caer en el mensaje genérico de ">= 400".
                return _transitorio_agotado(respuesta.status_code)
            elif respuesta.status_code == 400:
                raise FalloMotor(
                    "Gemini rechazó la petición. Suele ser la llave inválida o el nombre del "
                    f"modelo ({self.modelo!r})."
                )
            elif respuesta.status_code in (401, 403):
                raise FalloMotor("Gemini rechazó la llave de API.")
            elif respuesta.status_code >= 400:
                raise FalloMotor(f"Gemini respondió {respuesta.status_code}.")

            try:
                datos = respuesta.json()
            except ValueError as exc:
                raise RespuestaIninterpretable("Gemini no devolvió JSON.") from exc

            candidatos = datos.get("candidates") or []
            if not candidatos:
                # 200 con la lista vacía: Gemini bloqueó la respuesta por seguridad sin
                # ponerlo como código de error. Es un `502` como cualquier otra cosa que no
                # se pudo interpretar, y el mensaje lo deja claro para no perder tiempo.
                raise RespuestaIninterpretable(
                    "Gemini no devolvió candidatos. Suele ser el filtro de seguridad del modelo."
                )
            return candidatos[0].get("content", {}).get("parts") or []


def _transitorio_agotado(status):
    """Diagnóstico cuando un `503`/`429` sobrevive a todos los reintentos.

    Cada código transitorio tiene su propio diagnóstico, y el usuario merece el suyo y no
    el genérico: un 429 ("estás llamando demasiado") se soluciona esperando, y un 503 ("el
    modelo está saturado") se soluciona volviendo a intentar más tarde. Mezclarlos haría
    que un límite de peticiones pareciera un fallo del modelo.
    """
    raise FalloMotor(
        ("Gemini está limitando las peticiones. Intenta en un momento.")
        if status == 429
        else f"Gemini seguía saturado tras {_INTENTOS} intentos."
    )


def _mensaje_usuario(texto):
    return {"role": "user", "parts": [{"text": texto}]}


def _mensaje_modelo(texto):
    """Gemini usa `model` donde OpenAI usa `assistant`."""
    return {"role": "model", "parts": [{"text": texto}]}


def _declaracion_gemini():
    """Traduce el esquema compartido al dialecto de Gemini.

    Tres diferencias y ninguna trivial: Gemini no quiere el envoltorio `function`, usa los
    tipos en mayúsculas, y `additionalProperties` es obligatorio para declarar que no se
    aceptan claves extra — sin eso el modelo se inventa campos.
    """
    funcion = ESQUEMA_HERRAMIENTA["function"]
    parametros = dict(funcion["parameters"])
    parametros["type"] = parametros["type"].upper()
    parametros["properties"] = {
        nombre: {**prop, "type": prop["type"].upper()} for nombre, prop in parametros["properties"].items()
    }
    return {
        "name": funcion["name"],
        "description": funcion["description"],
        "parameters": parametros,
    }

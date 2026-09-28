"""Selección del motor de lenguaje según `LLM_PROVEEDOR` (spec.md 3.6).

Es la misma forma que [`pasarelas`](../pasarelas/__init__.py), y a propósito: los dos
proyectos tienen el mismo esqueleto —una interfaz, varias implementaciones, un
seleccionador por configuración—, y escribir el patrón dos veces de forma distinta es la
forma más rápida de que los dos diverjan.

`ollama` y `gemini` sólo se importan cuando corresponden, para que la instalación por
omisión no necesite `httpx` ni una llave de API para nada. El `mock` no necesita red y es
el que corre en CI, precisamente para que un test no dependa de un servicio de terceros.

La caché es por tupla de configuración, igual que en las pasarelas, y por el mismo motivo:
`PAGADORA` se lee una vez pero el motor se pide en cada request, y un `OllamaMotor` nuevo
por request tiraría la conexión HTTP cada vez.
"""

from flask import current_app

from motores.base import MotorLLM
from motores.mock import MockMotor

_cache: dict[tuple, MotorLLM] = {}


def obtener_motor(config=None) -> MotorLLM:
    config = config or current_app.config
    nombre = config.get("LLM_PROVEEDOR", "mock").lower()
    clave = (
        nombre,
        config.get("OLLAMA_URL"),
        config.get("OLLAMA_MODELO"),
        config.get("GEMINI_API_KEY"),
        config.get("GEMINI_MODELO"),
        config.get("LLM_MOCK_CANCHAS"),
    )
    if clave in _cache:
        return _cache[clave]

    motor: MotorLLM
    if nombre == "mock":
        motor = MockMotor(canchas=config.get("LLM_MOCK_CANCHAS") or ())
    elif nombre == "ollama":
        from motores.ollama import OllamaMotor

        motor = OllamaMotor(
            url=config.get("OLLAMA_URL", "http://localhost:11434"),
            modelo=config.get("OLLAMA_MODELO", "qwen2.5:3b"),
        )
    elif nombre == "gemini":
        from motores.gemini import GeminiMotor

        motor = GeminiMotor(
            api_key=config.get("GEMINI_API_KEY", ""),
            modelo=config.get("GEMINI_MODELO", "gemini-3.6-flash"),
        )
    else:
        raise RuntimeError(
            f"LLM_PROVEEDOR desconocido: {nombre!r}. Usa 'mock', 'ollama' o 'gemini'."
        )

    _cache[clave] = motor
    return motor


def limpiar_cache():
    """Vacía la caché de motores.

    Sólo lo usan los tests, para que un test que cambia la configuración no herede el
    motor del anterior. Vive aquí y no en el test para que el que limpia sea el dueño de lo
    que se limpia.
    """
    _cache.clear()

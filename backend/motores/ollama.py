"""Motor que habla con Ollama (spec.md 3.6).

Ollama corre en local, así que es el motor que sirve para tener el asistente sin enviar
nada fuera de la máquina. Es también el que choca con la RAM de este equipo, y de ahí el
timeout generoso: un modelo de 3B en una máquina de 2 núcleos tarda, y cortarlo a los 10
segundos convertiría "el equipo es lento" en "el asistente está caído".

Se importa con `import httpx` **dentro** de los métodos, no al principio del módulo, por
la misma razón que `stripe_pasarela`: la instalación normal no necesita el cliente HTTP
para nada más, y que la clase se pueda importar sin él permite que los tests del resto del
proyecto no dependan de que esté instalado.
"""

import json

from motores.base import (
    ESQUEMA_HERRAMIENTA,
    REGLAS_REDACCION,
    SYSTEM_PROMPT,
    describir_resultado,
    FalloMotor,
    MotorLLM,
    PeticionHerramienta,
    RespuestaIninterpretable,
)

#: Generoso a propósito. Un `qwen2.5:3b` en 2 núcleos con 3.7 GB tarda del orden de
#: decenas de segundos en el primer token; el límite está para que un modelo colgado no
#: deje el request colgado, no para castigar al equipo lento.
TIMEOUT_SEGUNDOS = 180.0


class OllamaMotor(MotorLLM):
    """Proveedor local vía la API de chat de Ollama."""

    nombre = "ollama"

    def __init__(self, url="http://localhost:11434", modelo="qwen2.5:3b", timeout=TIMEOUT_SEGUNDOS):
        self.url = url.rstrip("/")
        self.modelo = modelo
        self.timeout = timeout

    # --- primera vuelta ---------------------------------------------------------------

    def interpretar(self, mensaje):
        cuerpo = {
            "model": self.modelo,
            "stream": False,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": mensaje},
            ],
            "tools": [ESQUEMA_HERRAMIENTA],
        }
        datos = self._post("/api/chat", cuerpo)

        # Sin `tool_calls` el modelo decidió que no hace falta consultar. Se devuelve una
        # petición vacía con otro nombre y el blueprint redacta sin resultado, en vez de
        # inventar una búsqueda: la spec dice que el modelo **debe** usar la herramienta,
        # y si no lo hizo es que está respondiendo de memoria, que es lo que no queremos.
        llamadas = datos.get("message", {}).get("tool_calls") or []
        if not llamadas:
            contenido = (datos.get("message", {}).get("content") or "").strip()
            return PeticionHerramienta(nombre="responder_directo", argumentos={"texto": contenido})

        llamada = llamadas[0].get("function") or {}
        argumentos = llamada.get("arguments") or {}
        if not isinstance(argumentos, dict):
            raise RespuestaIninterpretable("Los argumentos de la herramienta no son un objeto.")
        # Ollama devuelve los argumentos como `dict`, pero algunos modelos los serializan
        # como texto JSON. Se acepta el texto porque llegar hasta aquí significa que el
        # modelo acertó la herramienta; lo que no se acepta es un `str` que no es JSON,
        # porque eso ya es ruido.
        if isinstance(argumentos, str):
            try:
                argumentos = json.loads(argumentos)
            except (ValueError, TypeError) as exc:
                raise RespuestaIninterpretable("Los argumentos de la herramienta no son JSON.") from exc

        return PeticionHerramienta(
            nombre=llamada.get("name") or "", argumentos=argumentos
        )

    # --- segunda vuelta ------------------------------------------------------------------

    def redactar(self, mensaje, resultado):
        cuerpo = {
            "model": self.modelo,
            "stream": False,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": mensaje},
                {"role": "assistant", "content": f"RESULTADO DE LA HERRAMIENTA:\n{describir_resultado(resultado)}"},
                {"role": "user", "content": REGLAS_REDACCION},
            ],
        }
        datos = self._post("/api/chat", cuerpo)
        texto = (datos.get("message", {}).get("content") or "").strip()
        if not texto:
            raise RespuestaIninterpretable("Ollama respondió vacío al redactar.")
        return texto

    # --- transporte ----------------------------------------------------------------------

    def _post(self, ruta, cuerpo):
        import httpx

        try:
            respuesta = httpx.post(
                f"{self.url}{ruta}", json=cuerpo, timeout=self.timeout
            )
        except httpx.TimeoutException as exc:
            raise FalloMotor(
                f"Ollama no respondió en {self.timeout:.0f} s. Si el equipo va justo, "
                "prueba con un modelo más pequeño o para lo que esté usando la memoria."
            ) from exc
        except httpx.HTTPError as exc:
            raise FalloMotor(
                f"No se pudo hablar con Ollama en {self.url}. ¿Está `ollama serve` corriendo?"
            ) from exc

        if respuesta.status_code >= 400:
            raise FalloMotor(
                f"Ollama respondió {respuesta.status_code}: {respuesta.text[:200]}"
            )
        try:
            return respuesta.json()
        except ValueError as exc:
            raise RespuestaIninterpretable("Ollama no devolvió JSON.") from exc

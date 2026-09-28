"""Motor simulado de lenguaje (spec.md 3.6).

Responde con reglas, sin red y sin modelo. Está aquí por dos razones que son la misma: es
lo que permite que el endpoint del asistente se pruebe en CI, y es lo que impide que una
prueba dependa de un servicio de terceros. Un test que llama a Ollama de verdad no es un
test: es un test que falla cuando el servidor está ocupado, y acabaríaBeing el motivo
para saltárselo.

No pretende ser listo. Pretende ser **determinista y predecible**, que es lo que un test
puede afirmar. Entiende la hora del día, entiende "hoy" y "mañana", y busca nombres de
cancha en la lista con la que se construyó. No entiende nada más, y esa limitación es
visible a propósito: si algún día `MockMotor` aprende a hacer preguntas de seguimiento,
alguien tiene que decidir si esa capacidad llega al modelo de verdad.
"""

import re
from datetime import date, timedelta

from motores.base import (
    HERRAMIENTA_BUSCAR,
    MotorLLM,
    PeticionHerramienta,
    ResultadoHerramienta,
    RespuestaIninterpretable,
)

#: Cualquier mención a una parte del día. La decisión de si es franja o día la toma
#: `_es_franja`, mirando lo que la rodea.
_PATRON_PALABRA_DIA = re.compile(r"\b(mañana|manana|tarde|noche)\b", re.IGNORECASE)
_PATRON_MAÑANA = re.compile(r"\b(mañana|manana)\b", re.IGNORECASE)

#: Preposición, con artículo opcional, pegada a la palabra: de cara la / por la mañana /
#: en el día. El artículo es obligatorio en la práctica —"en noche" no lo dice nadie—, así
#: que sin él la detección de franja no encuentra nada y todo cae en "cualquiera".
_ANTES_FRANJA = re.compile(r"\b(de|por|en|para)\s+(el|la|los|las)\s+$", re.IGNORECASE)

#: Frases que no son una petición de disponibilidad. Sin esto, un "hola" preguntaría por
#: canchas libres, que es la clase de error que hace que un asistente parezca un robot.
_SALUDOS = re.compile(
    r"^\s*(hola|buenas|buenos dias|buenas tardes|buenas noches|hey|qu[eé] tal|test|prueba)\b",
    re.IGNORECASE,
)


class MockMotor(MotorLLM):
    """Motor determinista. Sin red, sin modelo, sin `requests`."""

    nombre = "mock"

    def __init__(self, canchas=(), hoy=None):
        #: Nombres de cancha que este mock sabe reconocer. En producción viene de
        #: `LLM_MOCK_CANCHAS`; en los tests se inyectan, y por eso `canchas` es un
        #: parámetro y no una constante: un test necesita poder meter "Cancha Prueba"
        #: sin que el mock sepa nada del seed.
        self.canchas = tuple(canchas)
        self._hoy = hoy

    def _fecha_hoy(self):
        return self._hoy or date.today()

    def interpretar(self, mensaje):
        if not isinstance(mensaje, str) or not mensaje.strip():
            raise RespuestaIninterpretable("El mensaje está vacío.")

        if _SALUDOS.match(mensaje):
            return PeticionHerramienta(nombre="responder_directo", argumentos={})

        return PeticionHerramienta(
            nombre=HERRAMIENTA_BUSCAR,
            argumentos={
                "cancha": self._cancha(mensaje),
                "fecha": self._fecha(mensaje),
                "franja": self._franja(mensaje),
            },
        )

    def redactar(self, mensaje, resultado):
        if not isinstance(resultado, ResultadoHerramienta):
            raise RespuestaIninterpretable("El resultado no es un ResultadoHerramienta.")

        if not resultado.sugerencias:
            return resultado.detalle or "No encontré horarios disponibles."

        primero = resultado.sugerencias[0]
        plural = "s" if len(resultado.sugerencias) > 1 else ""
        horas = ", ".join(
            f"{s.hora_inicio} en {s.cancha}" for s in resultado.sugerencias
        )
        return (
            f"Encontré {len(resultado.sugerencias)} horario{plural} libre{plural}: {horas}. "
            f"El primero es el {primero.fecha} de {primero.hora_inicio} a "
            f"{primero.hora_fin} por ${primero.tarifa:,.0f}."
        )

    def _cancha(self, mensaje):
        """Primer nombre conocido que aparece en el mensaje, o cadena vacía.

        Vacía y no `None` porque el esquema de la herramienta dice que es `string`, y un
        `None` haría que un motor real lo mandara como `null` contra un tipo `string`.
        """
        for nombre in self.canchas:
            if nombre.lower() in mensaje.lower():
                return nombre
        return ""

    def _fecha(self, mensaje):
        """Traduce "hoy" y "mañana" a fecha ISO; por omisión, hoy.

        Por omisión **hoy** y no "cualquiera" porque la ventana de §3.2 son 6 días desde
        hoy: preguntar por hoy siempre da algo, mientras que una fecha inventada da un
        `422` y una pantalla de error. Ante la duda, el primer día de la ventana.
        """
        for coincidencia in _PATRON_MAÑANA.finditer(mensaje):
            if not _es_franja(mensaje, coincidencia):
                return (self._fecha_hoy() + timedelta(days=1)).isoformat()
        return self._fecha_hoy().isoformat()

    def _franja(self, mensaje):
        for coincidencia in _PATRON_PALABRA_DIA.finditer(mensaje):
            if _es_franja(mensaje, coincidencia):
                return _normalizar(coincidencia.group(1))
        return "cualquiera"


def _es_franja(mensaje, coincidencia):
    """True si esta aparición de la palabra es franja horaria y no día siguiente.

    "en la mañana" y "de la mañana" son franja; "mañana por la noche" es el día siguiente.
    Se decide por lo que la rodea, que es el mismo criterio que sigue un humano: la
    palabra sola es ambigua y el contexto es lo que la desambigua.
    """
    antes = mensaje[: coincidencia.start()]
    despues = mensaje[coincidencia.end() :]
    if _ANTES_FRANJA.search(antes):
        return True
    if re.match(r"\s+(tarde|noche)\b", despues, re.IGNORECASE):
        return True
    return False


def _normalizar(palabra):
    palabra = palabra.lower()
    if palabra in ("manana", "mañana"):
        return "mañana"
    return palabra

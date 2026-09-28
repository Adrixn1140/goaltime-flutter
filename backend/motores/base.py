"""Interfaz de motor de lenguaje (spec.md 3.6).

El blueprint del asistente no sabe si redacta Ollama, Gemini o el motor simulado: sólo
conoce `interpretar` y `redactar`. Añadir otro proveedor es escribir un módulo con esas dos
operaciones, igual que añadir Wompi o PayU es escribir un módulo con `crear_checkout` y
`verificar_evento`. La analogía con [`PasarelaPago`](../pasarelas/base.py) no es decorativa:
las dos interfaces nacen del mismo problema, que es que un proveedor externo no puede
filtrarse en la lógica de negocio.

## Por qué son dos llamadas y no una

El asistente reserva en nombre de quien pregunta, y quien pregunta es un cliente. Para
poder sugerir un slot real el backend necesita un `horario_id`, y ese id sólo existe en la
base. Si el modelo escribiera la respuesta en una sola vuelta, tendría que inventar el id,
o el backend tendría que enseñarle la base. Las dos son malas: un `horario_id` inventado es
una reserva que falla en el `409`, y una respuesta con el id dentro es un modelo con acceso
a los datos.

Así que el modelo **decide**, el backend **consulta**, y el modelo **redacta**:

    mensaje ──▶ interpretar() ──▶ PeticionHerramienta
                                          │
                                    (ejecuta la herramienta
                                     contra la base)
                                          │
                                       Resultado
                                          │
    respuesta ◀── redactar() ◀────────────┘

El modelo nunca ve una tabla. Ve una herramienta con tres argumentos de texto, y el
resultado que vuelve es una lista corta de slots que el propio backend acaba de leer.

## La frontera entre `DominioInvalido` y `FalloMotor`

Lo que separa un `422` de un `502` es de quién fue el error, y esa pregunta es la que
mantiene las dos excepciones separadas:

- `DominioInvalido` — el modelo pidió una fecha fuera de la ventana, o una franja que no
  existe. Se le puede corregir, y el mensaje lleva las fechas válidas para que lo intente.
- `FalloMotor` — el proveedor no respondió, o respondió algo que no se pudo entender. No
  hay a quién atribuírselo, así que no se reintenta ni se disimula: es un `502`.

Un `422` culpa a la decisión del modelo y un `502` culpa a la infraestructura. Mezclarlos
haría que un proveedor caído pareciera un usuario que escribió mal.
"""

from abc import ABC, abstractmethod
from collections.abc import Mapping
from dataclasses import dataclass, field

#: Nombre de la única herramienta que el asistente expone (spec.md 3.6).
HERRAMIENTA_BUSCAR = "buscar_disponibilidad"

#: Versión del contrato de la herramienta. El motor la manda en su *system prompt* para que
#: un cambio en los argumentos no se propague a un modelo antiguo en caché.
VERSION_CONTRATO = "1"


class FalloMotor(Exception):
    """El proveedor no respondió, o su respuesta no se pudo interpretar. Se traduce a `502`."""


class RespuestaIninterpretable(FalloMotor):
    """El proveedor respondió algo que no es una llamada a herramienta ni texto."""


@dataclass(frozen=True)
class PeticionHerramienta:
    """Lo que el modelo decidió hacer tras la primera vuelta.

    `argumentos` es texto a propósito, sin validar: el modelo no conoce ids y el backend no
    acepta ids de él. Que el modelo invente un `horario_id` no es posible porque el campo
    no existe en la herramienta.
    """

    nombre: str
    argumentos: Mapping[str, object] = field(default_factory=dict)

    @property
    def es_busqueda(self) -> bool:
        return self.nombre == HERRAMIENTA_BUSCAR


@dataclass(frozen=True)
class Sugerencia:
    """Un slot real, con su `horario_id`, listo para que la app ofrezca un botón."""

    cancha_id: int
    cancha: str
    fecha: str
    horario_id: int
    hora_inicio: str
    hora_fin: str
    tarifa: float

    def a_dict(self) -> dict:
        return {
            "cancha_id": self.cancha_id,
            "cancha": self.cancha,
            "fecha": self.fecha,
            "horario_id": self.horario_id,
            "hora_inicio": self.hora_inicio,
            "hora_fin": self.hora_fin,
            "tarifa": self.tarifa,
        }


@dataclass(frozen=True)
class ResultadoHerramienta:
    """Lo que la herramienta devolvió, ya consultado a la base.

    `detalle` va al modelo para que sepa qué decir. Cuando `encontrado` es `False` y no hay
    sugerencias, el motivo va aquí en prosa, y es el mecanismo por el que el asistente
    admite que no hay cancha con ese nombre en vez de inventar una: el backend no le pasa
    un slot inventable, le pasa una frase que puede repetir.
    """

    sugerencias: tuple[Sugerencia, ...] = ()
    encontrado: bool = True
    detalle: str = ""


#: Esquema de la herramienta que se le enseña al modelo. Es la **única** forma en que el
#: asistente llega a los datos, y por eso no lleva un `horario_id`: pedirle un id al modelo
#: lo invitaría a inventarlo, y un id inventado es una reserva que revienta en el `409`.
ESQUEMA_HERRAMIENTA: dict = {
    "type": "function",
    "function": {
        "name": HERRAMIENTA_BUSCAR,
        "description": (
            "Busca canchas con horario libre. Úsala siempre que la persona hable de "
            "jugar, reservar o buscar una cancha, aunque no dé ningún detalle: es "
            "preferible devolver todos los horarios libres a afirmar que no hay nada."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "cancha": {
                    "type": "string",
                    "description": (
                        "Nombre de la cancha, o parte del nombre, como dijo la persona. "
                        "Cadena vacía si no mencionó ninguna o si no está segura del "
                        "nombre."
                    ),
                },
                "fecha": {
                    "type": "string",
                    "description": (
                        "Fecha en formato YYYY-MM-DD dentro de los próximos 6 días. "
                        "Usa la fecha de hoy si la persona no dijo día, y tradúcela tú: "
                        "si dice 'mañana', calcula la fecha que es mañana. No inventes "
                        "años ni meses."
                    ),
                },
                "franja": {
                    "type": "string",
                    "enum": ["mañana", "tarde", "noche", "cualquiera"],
                    "description": (
                        "Parte del día. 'cualquiera' si no dijo hora. Ojo: 'mañana' como "
                        "franja del día y 'mañana' como el día siguiente son cosas "
                        "distintas; decide por el contexto de la frase."
                    ),
                },
            },
            "required": ["fecha", "franja"],
        },
    },
}


#: Prompt compartido por todos los motores. Vive aquí y no en cada proveedor porque los dos
#: que hay usan APIs distintas pero dependen de que el modelo reciba **exactamente** las
#: mismas instrucciones: si difieren, la diferencia se cuela en los tests y se atribuye al
#: proveedor equivocado.
SYSTEM_PROMPT = f"""Eres el asistente de reservas de GoalTime, una app de canchas de fútbol en Riohacha, Colombia.

Tu trabajo es ayudar a encontrar una cancha libre. No reservas, no cobras y no confirmas nada: sólo sugieres, y la persona confirma pulsando un botón.

Reglas:
- Cuando la persona hable de jugar, reservar o buscar, llama a la herramienta `{HERRAMIENTA_BUSCAR}`. Siempre. Aunque no haya dado ningún detalle, aunque te parezca que no hay información suficiente: una búsqueda sin filtros es mejor que decir que no sabes.
- No inventes canchas, horarios, precios ni identificadores. Los datos sólo vienen de la herramienta. Si la herramienta dice que no encontró nada, dilo con esas palabras.
- Si no estás seguro del nombre de la cancha que dijo, manda `cancha` como cadena vacía en vez de suponer uno.
- Las tarifas están en pesos colombianos.
- Responde en español de Colombia, breve y conversacional: una o dos frases. Sin listas ni tablas.
- No prometas que un horario queda reservado. Nada se reserva hasta que la persona lo confirme.

Contrato de la herramienta: versión {VERSION_CONTRATO}."""


#: Instrucciones de la segunda vuelta. Es un prompt aparte y no una continuación del primero
#: porque el rol cambió: en esta vuelta el modelo ya consultó y su trabajo es *sólo* decir
#: en voz alta lo que le devolvieron.
REGLAS_REDACCION = """Ya consultaste la disponibilidad. Escribe la respuesta para la persona.

- Di cuántos horarios libres hay, y nombra los primeros con hora y cancha.
- Si no hay ninguno, dilo claro y ofrece la alternativa de probar otro día u otra franja.
- Si no encontraste la cancha que dijeron, pide el nombre de otra forma en vez de responder como si la hubiera entendido.
- Una o dos frases. Sin listas, sin tablas, sin repetir el identificador del horario.
- No digas que está reservado: sólo disponible."""


def sistema_interpretar() -> str:
    """El prompt de la primera vuelta con la fecha de hoy embebida.

    Un modelo no sabe qué día es hoy: su reloj interno es el de los datos con los que se
    entrenó, que en Gemini van con meses o años de retraso. Sin esta línea, "mañana" se
    convierte en una fecha del pasado, y el `422` de la ventana de 6 días lo devuelve al
    que pregunta con cara de que el asistente no funciona. La fecha la pone el backend, que
    es el único que la conoce de verdad: exactamente el mismo reparto que hace que el
    `horario_id` lo consulte la base y no lo invente el modelo.
    """
    from datetime import date

    hoy = date.today().isoformat()
    return (
        SYSTEM_PROMPT
        + "\n\nHoy es "
        + hoy
        + " (formato YYYY-MM-DD). Calcula las fechas relativas —'hoy', 'mañana', "
        "'pasado mañana'— a partir de esta fecha, que es la real, y no de tu memoria: "
        "tu conocimiento de cuál es la fecha actual está desfasado."
    )


class MotorLLM(ABC):
    """Contrato mínimo de un motor de lenguaje."""

    #: código que viaja en la respuesta como `motor`, para que la app y los tests sepan
    #: quién respondió
    nombre: str

    @abstractmethod
    def interpretar(self, mensaje: str) -> PeticionHerramienta:
        """Primera vuelta: decide si llama a la herramienta y con qué argumentos.

        Si el modelo decide que no hace falta consultar, devuelve una `PeticionHerramienta`
        con otro nombre. El blueprint lo trata como respuesta directa.
        """

    @abstractmethod
    def redactar(self, mensaje: str, resultado: ResultadoHerramienta) -> str:
        """Segunda vuelta: convierte el resultado ya consultado en una respuesta en prosa.

        `resultado` viene del backend, no del modelo. El texto devuelto es lo que la persona
        lee, y se muestra tal cual: no se le pasa un modelo por encima para "limpiarlo",
        porque ese segundo modelo inventaría disponibilidad.
        """


def describir_resultado(resultado: ResultadoHerramienta) -> str:
    """El resultado de la herramienta, en texto que un modelo pueda leer.

    Va como prosa y no como JSON por una razón concreta: si le mandas JSON, los modelos
    tienden a devolver campos literales, y los identificadores de horario son justo lo que
    no debe decir en voz alta — "reservar el horario 7" suena a robot. En frases, el modelo
    los usa para decidir y los deja fuera al redactar.

    Vive aquí y no en el motor de Ollama porque es formato compartido: los dos
    proveedores redactan a partir de este mismo texto, y que uno dependa del otro para
    formatear un resultado sería una dependencia falsa entre dos implementaciones que no
    se conocen.
    """
    if not resultado.sugerencias:
        return resultado.detalle or "No se encontraron horarios disponibles."
    lineas = [
        f"- {s.cancha}, el {s.fecha} de {s.hora_inicio} a {s.hora_fin}, "
        f"tarifa {s.tarifa:,.0f} pesos"
        for s in resultado.sugerencias
    ]
    encabezado = (
        f"Se encontraron {len(resultado.sugerencias)} horarios disponibles:"
        if len(resultado.sugerencias) > 1
        else "Se encontró 1 horario disponible:"
    )
    return encabezado + "\n" + "\n".join(lineas)

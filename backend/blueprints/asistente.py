"""Asistente de reserva por lenguaje natural (spec.md 3.6).

`POST /api/asistente` — recibe lo que la persona escribió, decide con el motor qué
herramienta llamar, ejecuta esa herramienta contra la base y devuelve texto más sugerencias
con `horario_id` real.

## Lo que este endpoint no hace

- **No reserva ni cobra.** Devuelve sugerencias, y el único camino que reserva es
  `POST /api/reservas` (spec.md 3.2). Se puede recortar sin dejar la app a medias: el
  asistente se puede apagar y la reserva sigue funcionando.
- **No le enseña la base al modelo.** El modelo elige una herramienta con tres argumentos
  de texto; el backend consulta. Un `horario_id` que sale de aquí salió de una consulta
  real, no de una inferencia del modelo.
- **No acepta identificadores del modelo.** El esquema de la herramienta no tiene forma de
  que el modelo pase un id, ni siquiera equivocándose: si no se lo ofreces, no lo inventa.

## Por qué dos vueltas y no un `if`

Un `if "reservar" in mensaje` sería más corto, y sería un asistente que no entiende
"¿tenéis algo para el jueves al mediodía?", que es medio de lo que la gente escribe. La
complejidad de las dos vueltas compra entender frases en vez de palabras clave. Y el `502`
existe para que un proveedor caído no se confunda con un usuario que escribió mal: son dos
fallos distintos y merecen códigos distintos.
"""

from flask import Blueprint, current_app, jsonify, request

from auth_helpers import con_rol
from dominio.disponibilidad import (
    FRANJA_CUALQUIERA,
    FRANJAS,
    fecha_en_ventana,
    resolver_cancha_por_nombre,
    slots_reservables,
)
from dominio.errores import DominioInvalido
from errors import error_response
from extensions import db
from models import ROL_CLIENTE, Cancha
from motores import obtener_motor
from motores.base import FalloMotor, ResultadoHerramienta, Sugerencia

bp = Blueprint("asistente", __name__)

#: Tope de sugerencias devueltas. Tres alcanzan para que la persona elija sin que la
#: respuesta se convierta en una tabla. Lo decide el backend y no el modelo para que el
#: mismo mensaje produzca la misma respuesta con cualquier proveedor.
LIMITE_SUGERENCIAS = 3


@bp.post("/asistente")
@con_rol(ROL_CLIENTE)
def asistente():
    cuerpo = request.get_json(silent=True) or {}
    mensaje = cuerpo.get("mensaje")

    if not isinstance(mensaje, str) or not mensaje.strip():
        return error_response(400, "El campo 'mensaje' es obligatorio y debe ser texto")

    motor = obtener_motor()

    # --- primera vuelta: el modelo decide ------------------------------------------------
    try:
        peticion = motor.interpretar(mensaje)
    except FalloMotor as exc:
        return _motor_caido(exc)

    if peticion.nombre != "buscar_disponibilidad":
        # El motor decidió responder sin consultar. Se respeta su respuesta en vez de
        # forzarlo a buscar: un saludo debe sonar a saludo, no a "hay 3 canchas libres".
        texto = str(peticion.argumentos.get("texto") or "").strip() or _SALUDO
        return _respuesta(texto, (), motor.nombre)

    # --- la herramienta corre contra la base ---------------------------------------------
    try:
        resultado = _buscar(peticion.argumentos or {})
    except DominioInvalido as exc:
        return error_response(422, str(exc))

    # --- segunda vuelta: el modelo redacta ------------------------------------------------
    try:
        texto = motor.redactar(mensaje, resultado)
    except FalloMotor as exc:
        return _motor_caido(exc)

    return _respuesta(texto, resultado.sugerencias, motor.nombre)


#: `FranjaInvalida` se importa perezoso dentro de `_buscar` para que salga de su módulo,
#: que es donde vive la lista de franjas válidas y el mensaje con ella. Importar la
#: excepción arriba sería tirar el módulo entero por una clase.
def _buscar(argumentos) -> ResultadoHerramienta:
    """Corre `buscar_disponibilidad` y devuelve lo que el modelo va a redactar.

    Es la frontera del sistema: de aquí para atrás hay un modelo hablando y una base de
    datos esperando. Lo que no se puede sostener —una fecha fuera de la ventana, una franja
    que no existe— sale como `DominioInvalido` y el endpoint lo traduce a `422`.
    """
    from dominio.errores import FranjaInvalida

    fecha = fecha_en_ventana(argumentos.get("fecha"))
    franja = argumentos.get("franja") or FRANJA_CUALQUIERA
    if franja not in FRANJAS:
        raise FranjaInvalida(
            f"Franja desconocida: {franja!r}. Usa una de: {', '.join(FRANJAS)}."
        )

    texto_cancha = argumentos.get("cancha")
    cancha = resolver_cancha_por_nombre(texto_cancha) if texto_cancha else _primera_cancha()

    if cancha is None:
        # No es un error: es la respuesta correcta a una pregunta mal enfocada. Se le da
        # al modelo una frase para que lo diga con esas palabras. Una cancha que no existe
        # no puede convertirse en sugerencia, y esto es lo que garantiza que no lo haga.
        return ResultadoHerramienta(
            sugerencias=(),
            encontrado=False,
            detalle=(
                f"No encontré ninguna cancha que se llame parecido a {texto_cancha!r}. "
                "Pide el nombre de otra forma."
            ),
        )

    slots = slots_reservables(cancha, fecha, franja=franja, limite=LIMITE_SUGERENCIAS)
    sugerencias = tuple(
        Sugerencia(
            cancha_id=cancha.id,
            cancha=cancha.nombre,
            fecha=slot["fecha"],
            horario_id=slot["horario_id"],
            hora_inicio=slot["hora_inicio"],
            hora_fin=slot["hora_fin"],
            tarifa=slot["tarifa"],
        )
        for slot in slots
    )
    if not sugerencias:
        return ResultadoHerramienta(
            sugerencias=(),
            encontrado=True,
            detalle=(
                f"La cancha {cancha.nombre} no tiene horarios libres el {fecha.isoformat()}"
                + ("" if franja == FRANJA_CUALQUIERA else f" por la {franja}")
                + ". Prueba otro día u otra franja."
            ),
        )
    return ResultadoHerramienta(sugerencias=sugerencias, encontrado=True)


def _primera_cancha():
    """Primera cancha activa, o `None` si no hay ninguna.

    Se usa cuando la persona no dijo ninguna. Es una decisión de producto, y va en el
    backend y no en el prompt: "si no dijo cancha, enséñale la primera" es una regla del
    catálogo, y pedirle a un modelo que la aplique es pedirle que la cumpla siempre.
    """
    return (
        db.session.execute(
            db.select(Cancha).where(Cancha.activo.is_(True)).order_by(Cancha.id)
        )
        .scalars()
        .first()
    )


def _motor_caido(exc: Exception):
    """Traduce un fallo del proveedor a un `502` con detalle al log y no a la respuesta.

    El mensaje que ve la persona es genérico a propósito. El texto de la excepción puede
    incluir la URL completa y, con Gemini, el prefijo de la llave: un `502` con la llave en
    el cuerpo sería una fuga de §7.2 por el camino de los errores, que es el peor sitio
    posible para que se disperse.
    """
    current_app.logger.warning("Asistente: el motor falló: %s", exc)
    return error_response(502, "El asistente no está disponible en este momento")


def _respuesta(texto, sugerencias, nombre_motor):
    return jsonify(
        {
            "respuesta": texto,
            "sugerencias": [s.a_dict() for s in sugerencias],
            "motor": nombre_motor,
        }
    )


_SALUDO = "Hola. Dime qué quieres reservar y te busco canchas libres."

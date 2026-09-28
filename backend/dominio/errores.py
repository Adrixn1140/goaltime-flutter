"""Errores del dominio de disponibilidad.

Viven aquí y no en [`errors.py`](../errors.py) por una razón de capas: `errors.py` importa
`flask` porque su trabajo es dar formato HTTP, y un módulo de reglas de negocio no debería
depender del módulo que sabe responder una petición. El dominio lanza; el blueprint traduce
la excepción a un código de la tabla de §3.6.
"""


class DominioInvalido(Exception):
    """Un argumento de la herramienta no se puede sostener.

    El blueprint lo traduce a `422`. El mensaje es para el modelo, no para el usuario: va
    con las fechas concretas que sí valen, para que el modelo pueda corregir su decisión en
    lugar de rendirse.
    """


class FranjaInvalida(DominioInvalido):
    """La franja no es una de las cuatro de la spec."""

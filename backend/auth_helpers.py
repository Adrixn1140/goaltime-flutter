"""Identidad y permisos compartidos por los blueprints.

Vive fuera de cualquier blueprint porque el mismo criterio lo necesitan la gestión del
dueño, el panel de admin y los endpoints de cliente: la respuesta a "¿quién es y qué
puede hacer?" no puede depender de qué archivo importó la función primero.

Dos decisiones que los tests fijan:

- **Un `401` no es un `403`.** Si el token es criptográficamente válido pero el usuario ya
  no está en la base, la respuesta es `401`: el cliente está autenticado, la sesión ya no
  sirve. Confundirlos haría que la app pidiera permisos que no tiene en vez de reloguear.
- **Cuenta desactivada también es `401`.** El admin puede desactivar a un usuario
  (`PATCH /api/usuarios/{id}/rol`, spec.md 3.5) y desactivar es una medida de seguridad:
  si su token siguiera valiendo, bastaría con esperar a que expire, hasta 12 h después.
  Un `401` es además lo que la app sabe manejar: cierra la sesión y manda al login, en
  vez de dejar una pantalla llena de errores de permisos que el usuario no puede
  arreglar. El login, en cambio, responde `403` con su propio mensaje: ahí el que llama
  es un anónimo y el problema se explica sin rastro de sesión.
- **El orden de los decoradores importa.** `con_rol` va **encima** de `@jwt_required()`:

      @con_rol(ROL_DUENO, ROL_ADMIN)
      @jwt_required()
      def mi_endpoint(): ...

  El decorador de dentro se ejecuta primero, así que la firma del JWT ya está verificada
  cuando `con_rol` lee la identidad. Al revés, `get_jwt_identity()` se llamaría sobre un
  token sin verificar.
"""

from functools import wraps

from flask import g
from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request

from errors import error_response
from extensions import db
from models import ROL_ADMIN, Cliente


def usuario_del_token():
    """Cliente del JWT, o `None` si el token es válido pero el usuario ya no existe.

    `None` **no** significa "sin token": a esta función sólo se llega después de
    `jwt_required()`, así que un `None` aquí siempre es una sesión muerta.
    """
    try:
        cliente_id = int(get_jwt_identity())
    except (TypeError, ValueError):
        return None
    return db.session.get(Cliente, cliente_id)


def con_rol(*roles):
    """Deja pasar sólo a los roles indicados y deja al usuario en `g.usuario`.

    Sin argumentos sólo exige sesión (útil para reutilizar el mismo camino de errores).
    """
    permitidos = set(roles)

    def decorador(funcion):
        @wraps(funcion)
        def envoltura(*args, **kwargs):
            verify_jwt_in_request()
            cliente = usuario_del_token()
            if cliente is None:
                return error_response(401, "La sesión no es válida")
            if not cliente.activo:
                return error_response(401, "Tu cuenta está desactivada, contacta al administrador")
            if permitidos and cliente.rol not in permitidos:
                return error_response(403, "No tienes permisos para esta operación")
            g.usuario = cliente
            return funcion(*args, **kwargs)

        return envoltura

    return decorador


def dueno_o_admin(cliente):
    """`True` si el usuario puede ver canchas de cualquier dueño."""
    return cliente.rol == ROL_ADMIN

"""Formato de error único de la API (spec.md 4).

Todos los handlers responden `{"error": {"codigo": n, "mensaje": "..."}}`. El mensaje
va redactado para el usuario final (español, sin stack traces ni SQL), mientras el
detalle técnico queda en el log del servidor.
"""

from flask import jsonify
from werkzeug.exceptions import HTTPException


def error_response(codigo, mensaje, status=None):
    return jsonify({"error": {"codigo": codigo, "mensaje": mensaje}}), (status or codigo)


def registrar_handlers(app):
    @app.errorhandler(HTTPException)
    def _http_error(exc):
        return error_response(exc.code, _mensaje_por_defecto(exc.code))

    @app.errorhandler(404)
    def _no_encontrado(_exc):
        return error_response(404, "El recurso solicitado no existe")

    @app.errorhandler(422)
    def _no_procesable(exc):
        return error_response(422, "Los datos enviados no son válidos", status=400)


def _mensaje_por_defecto(codigo):
    return {
        400: "La solicitud no es válida",
        401: "Sesión no válida o credenciales incorrectas",
        403: "No tienes permisos para esta operación",
        404: "El recurso solicitado no existe",
        405: "Método no permitido",
        409: "La operación entra en conflicto con el estado actual",
        413: "El contenido enviado supera el tamaño permitido",
        415: "El contenido debe enviarse como application/json",
        422: "Los datos enviados no son válidos",
    }.get(codigo, "Ocurrió un error inesperado")

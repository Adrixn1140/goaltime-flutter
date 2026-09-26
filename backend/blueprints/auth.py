"""Blueprint de autenticación (spec.md 3.1).

`register` es público y siempre crea usuarios con rol `cliente`: asignar `dueno` o
`admin` es una operación de Admin (`PATCH /api/usuarios/{id}/rol`), nunca del propio
registro.
"""

import re

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import create_access_token, get_jwt_identity, jwt_required

from errors import error_response
from extensions import db
from limites import EMAIL, NOMBRE
from models import ROL_CLIENTE, Cliente, Maestra

bp = Blueprint("auth", __name__)

RE_EMAIL = re.compile(r"^[^@\s]+@[^@\s.]+\.[^@\s]+$")
MIN_PASSWORD = 8


def _peticion_json():
    """Devuelve el cuerpo JSON o `(None, error)` si falta o es inválido."""
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return None, error_response(400, "El cuerpo debe ser JSON con los campos requeridos")
    return datos, None


def _rol_de_codigo(codigo):
    return Maestra.por_codigo("rol", codigo)


def _respuesta_auth(cliente, status):
    token = create_access_token(identity=str(cliente.id), additional_claims={"rol": cliente.rol})
    return jsonify({"access_token": token, "rol": cliente.rol, "usuario": cliente.to_dict()}), status


@bp.post("/register")
def register():
    datos, error = _peticion_json()
    if error:
        return error

    nombre = str(datos.get("name") or datos.get("nombre") or "").strip()
    email = str(datos.get("email") or "").strip().lower()
    password = str(datos.get("password") or "")

    if not nombre or not email or not password:
        return error_response(400, "Nombre, email y contraseña son obligatorios")
    if len(nombre) > NOMBRE:
        return error_response(400, f"El nombre no puede superar {NOMBRE} caracteres")
    if len(email) > EMAIL:
        # Sin esto, un email largo pasaba el regex y reventaba en PostgreSQL con un 500:
        # en SQLite el `varchar(180)` no se aplica, así que el bug sólo aparece allí
        # (spec.md 7.6).
        return error_response(400, f"El email no puede superar {EMAIL} caracteres")
    if not RE_EMAIL.match(email):
        return error_response(400, "El email no tiene un formato válido")
    if len(password) < MIN_PASSWORD:
        return error_response(400, f"La contraseña debe tener al menos {MIN_PASSWORD} caracteres")

    existente = db.session.execute(db.select(Cliente).filter_by(email=email)).scalar_one_or_none()
    if existente:
        return error_response(409, "El email ya está registrado")

    rol = _rol_de_codigo(ROL_CLIENTE)
    if rol is None:
        current_app.logger.error("Catálogo 'rol' sin cliente; ejecuta `flask seed-catalogo`")
        return error_response(500, "Error de configuración del servidor")

    cliente = Cliente(nombre=nombre, email=email, rol_id=rol.id)
    cliente.set_password(password)
    db.session.add(cliente)
    db.session.commit()

    return _respuesta_auth(cliente, 201)


@bp.post("/login")
def login():
    datos, error = _peticion_json()
    if error:
        return error

    email = str(datos.get("email") or "").strip().lower()
    password = str(datos.get("password") or "")
    if not email or not password:
        return error_response(400, "Email y contraseña son obligatorios")

    cliente = db.session.execute(db.select(Cliente).filter_by(email=email)).scalar_one_or_none()
    # Mismo mensaje y trabajo aproximado para email inexistente y password inválido:
    # no se revela qué cuentas existen (HEUR-5, prevención de errores por sondeo).
    if cliente is None or not cliente.check_password(password):
        return error_response(401, "Credenciales inválidas")
    if not cliente.activo:
        return error_response(403, "Tu cuenta está desactivada, contacta al administrador")

    return _respuesta_auth(cliente, 200)


@bp.post("/logout")
@jwt_required()
def logout():
    """JWT es stateless: no hay lista de revocados. El endpoint existe para que la
    app descarte el token almacenado siguiendo el contrato (spec.md 3.1)."""
    get_jwt_identity()
    return "", 204

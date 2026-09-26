"""Panel de administración: usuarios y reporte (spec.md 3.5).

Es el único lugar de la API donde un usuario ve datos de otros, así que el módulo se
escribe alrededor de tres decisiones que los tests fijan:

1. **Sólo admin.** `con_rol(ROL_ADMIN)` responde `403` a un cliente o a un dueño. Aquí
   el `403` sí es lo correcto —a diferencia de §3.4, donde la cancha ajena es `404`—
   porque saber qué usuarios existen es justamente lo que el admin necesita saber.
2. **El admin no puede dejar la plataforma sin administración.** Cambiarse o
   desactivarse a sí mismo es `422`, y bajar de `dueno` a `cliente` con canchas activas
   también: sus canchas quedarían con un dueño que ya no puede gestionarlas. El mensaje
   dice cuántas canchas hay que bajar antes, porque un error sin el número obliga al
   admin a adivinar.
3. **El reporte suma dinero, no reservas.** Ingresos = pagos aprobados. Una reserva
   cancelada cuenta, porque cancelar no reembolsa (§3.2); un pago pendiente o rechazado
   no cuenta, porque ese dinero no entró. Los conteos de reservas sí salen por estado,
   incluidas las canceladas: al admin le interesa ver la tasa de cancelación.
"""

from datetime import datetime, timezone

from flask import Blueprint, g, jsonify, request

from auth_helpers import con_rol
from errors import error_response
from extensions import db
from models import (
    PAGO_APROBADO,
    ROL_ADMIN,
    ROL_CLIENTE,
    Cancha,
    Cliente,
    Maestra,
    Pago,
    Reserva,
)

bp = Blueprint("admin", __name__)


def _cuerpo_json():
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        return None, error_response(400, "El cuerpo debe ser JSON con 'rol' o 'activo'")
    return datos, None


def _rol_de_codigo(codigo):
    return Maestra.por_codigo("rol", codigo) if isinstance(codigo, str) else None


def _plural(n, singular, plural):
    return f"{n} {singular}" if n == 1 else f"{n} {plural}"


def _conteos():
    """Conteos de canchas por dueño y de reservas por cliente.

    Dos consultas agrupadas en vez de una por usuario: con la lista completa de usuarios
    delante, el patrón N+1 se nota en cuanto hay más de una pantalla de gente.
    """
    canchas = dict(
        db.session.execute(
            db.select(Cancha.dueno_id, db.func.count(Cancha.id)).group_by(Cancha.dueno_id)
        ).all()
    )
    reservas = dict(
        db.session.execute(
            db.select(Reserva.cliente_id, db.func.count(Reserva.id)).group_by(Reserva.cliente_id)
        ).all()
    )
    return canchas, reservas


def _usuario_dict(cliente, canchas=None, reservas=None):
    datos = cliente.to_dict()
    datos["canchas"] = canchas or 0
    datos["reservas"] = reservas or 0
    return datos


# --------------------------------------------------------------------------- usuarios
@bp.get("/usuarios")
@con_rol(ROL_ADMIN)
def listar_usuarios():
    """Todos los usuarios, con los conteos que el admin necesita para decidir."""
    canchas, reservas = _conteos()
    usuarios = db.session.execute(db.select(Cliente).order_by(Cliente.nombre, Cliente.id)).scalars().all()
    return jsonify({"usuarios": [_usuario_dict(u, canchas.get(u.id), reservas.get(u.id)) for u in usuarios]})


@bp.patch("/usuarios/<int:usuario_id>/rol")
@con_rol(ROL_ADMIN)
def cambiar_rol(usuario_id):
    """Única vía para dar de alta un dueño o un admin y para desactivar (spec.md 3.1)."""
    datos, error = _cuerpo_json()
    if error:
        return error

    objetivo = db.session.get(Cliente, usuario_id)
    if objetivo is None:
        return error_response(404, "El usuario no existe")

    nuevo_rol = None
    activo = None
    if "rol" in datos:
        nuevo_rol = _rol_de_codigo(datos.get("rol"))
        if nuevo_rol is None:
            return error_response(400, "El rol no existe")
    if "activo" in datos:
        if not isinstance(datos.get("activo"), bool):
            return error_response(400, "'activo' debe ser true o false")
        activo = datos["activo"]
    if nuevo_rol is None and activo is None:
        return error_response(400, "Indica el nuevo 'rol' o el nuevo 'activo'")

    if objetivo.id == g.usuario.id and (
        activo is False or (nuevo_rol is not None and nuevo_rol.codigo != ROL_ADMIN)
    ):
        # Sin esta guarda, con una sola cuenta de admin el botón de desactivar es un
        # botón de cierre del sistema. Un 403 estaría mal: el permiso sí existe.
        return error_response(
            422,
            "No puedes cambiarte el rol ni desactivar tu propia cuenta: "
            "dejarías la plataforma sin administración",
        )

    if nuevo_rol is not None and nuevo_rol.codigo == ROL_CLIENTE:
        activas = db.session.execute(
            db.select(db.func.count(Cancha.id)).where(
                Cancha.dueno_id == objetivo.id, Cancha.activo.is_(True)
            )
        ).scalar_one()
        if activas:
            # Con canchas activas quitarle el rol las deja sin quien las gestione. Las
            # inactivas sí se quedan con el usuario: devolverle el rol recupera su
            # operación, y el admin puede bajarlas con PATCH /api/gestion/canchas/{id}.
            return error_response(
                422,
                f"Baja primero sus {_plural(activas, 'cancha activa', 'canchas activas')}: "
                "si le quitas el rol de dueño quedarían sin nadie que las gestione",
            )

    if nuevo_rol is not None:
        objetivo.rol_id = nuevo_rol.id
    if activo is not None:
        objetivo.activo = activo
    db.session.commit()

    canchas, reservas = _conteos()
    return jsonify(_usuario_dict(objetivo, canchas.get(objetivo.id), reservas.get(objetivo.id)))


# ---------------------------------------------------------------------------- reporte
@bp.get("/reporte")
@con_rol(ROL_ADMIN)
def reporte():
    """Agregados listos para dibujar; la app no trae reservas a sumar en el cliente."""
    ingresos_cancha = db.session.execute(
        db.select(
            Reserva.cancha_id,
            Cancha.nombre,
            db.func.sum(Pago.monto).label("monto"),
            db.func.count(Pago.id).label("reservas"),
        )
        .join(Cancha, Cancha.id == Reserva.cancha_id)
        .join(Pago, Pago.reserva_id == Reserva.id)
        .where(Pago.estado == PAGO_APROBADO)
        .group_by(Reserva.cancha_id, Cancha.nombre)
        .order_by(db.func.sum(Pago.monto).desc())
    ).all()

    ingresos_dia = db.session.execute(
        db.select(
            Reserva.fecha,
            db.func.sum(Pago.monto).label("monto"),
            db.func.count(Pago.id).label("reservas"),
        )
        .join(Pago, Pago.reserva_id == Reserva.id)
        .where(Pago.estado == PAGO_APROBADO)
        .group_by(Reserva.fecha)
        .order_by(Reserva.fecha)
    ).all()

    reservas_cancha = db.session.execute(
        db.select(Reserva.cancha_id, Cancha.nombre, db.func.count(Reserva.id))
        .join(Cancha, Cancha.id == Reserva.cancha_id)
        .group_by(Reserva.cancha_id, Cancha.nombre)
        .order_by(db.func.count(Reserva.id).desc(), Cancha.nombre)
    ).all()

    por_estado = dict(
        db.session.execute(
            db.select(Reserva.estado, db.func.count(Reserva.id)).group_by(Reserva.estado)
        ).all()
    )

    por_rol = dict(
        db.session.execute(
            db.select(Maestra.codigo, db.func.count(Cliente.id))
            .join(Maestra, Maestra.id == Cliente.rol_id)
            .group_by(Maestra.codigo)
        ).all()
    )

    return jsonify(
        {
            "generado_en": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "ingresos": {
                "total": float(sum(fila.monto for fila in ingresos_cancha)),
                "por_cancha": [
                    {
                        "cancha_id": fila.cancha_id,
                        "nombre": fila.nombre,
                        "monto": float(fila.monto),
                        "reservas": fila.reservas,
                    }
                    for fila in ingresos_cancha
                ],
                "por_dia": [
                    {"fecha": fila.fecha.isoformat(), "monto": float(fila.monto), "reservas": fila.reservas}
                    for fila in ingresos_dia
                ],
            },
            "reservas": {
                "total": sum(por_estado.values()),
                "por_estado": por_estado,
                "por_cancha": [
                    {"cancha_id": fila[0], "nombre": fila[1], "reservas": fila[2]}
                    for fila in reservas_cancha
                ],
            },
            "usuarios": {
                "total": sum(por_rol.values()),
                "por_rol": por_rol,
                "inactivos": db.session.execute(
                    db.select(db.func.count(Cliente.id)).where(Cliente.activo.is_(False))
                ).scalar_one(),
            },
        }
    )

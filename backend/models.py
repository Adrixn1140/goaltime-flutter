"""Modelos del dominio GoalTime (spec.md 2).

Los nombres de tabla y campos siguen la sección 2 de la spec. Los catálogos de
`Maestra` son la fuente de verdad de los valores enumerados: los defaults de las
columnas se definen a partir de esas constantes para que no haya literales sueltos.
"""

from datetime import datetime, time
from decimal import Decimal

from sqlalchemy import CheckConstraint, Index, UniqueConstraint, func, text
from werkzeug.security import check_password_hash, generate_password_hash

from extensions import db

# --- Catálogos (Maestra.tipo) ------------------------------------------------

ROL_CLIENTE = "cliente"
ROL_DUENO = "dueno"
ROL_ADMIN = "admin"

ESTADO_PENDIENTE_PAGO = "pendiente_pago"
ESTADO_CONFIRMADA = "confirmada"
ESTADO_CANCELADA = "cancelada"

PAGO_PENDIENTE = "pendiente"
PAGO_APROBADO = "aprobado"
PAGO_RECHAZADO = "rechazado"

METODO_STRIPE = "stripe"
METODO_MOCK = "mock"

#: Fuente de verdad de los catálogos: `{tipo: {codigo: valor}}` (spec.md 2).
#: `flask init-db` los inserta en la tabla `maestra` y el seed los reutiliza.
CATALOGOS = {
    "rol": {
        ROL_CLIENTE: "Cliente",
        ROL_DUENO: "Dueño de cancha",
        ROL_ADMIN: "Administrador",
    },
    "estado_reserva": {
        ESTADO_PENDIENTE_PAGO: "Pendiente de pago",
        ESTADO_CONFIRMADA: "Confirmada",
        ESTADO_CANCELADA: "Cancelada",
    },
    "estado_pago": {
        PAGO_PENDIENTE: "Pendiente",
        PAGO_APROBADO: "Aprobado",
        PAGO_RECHAZADO: "Rechazado",
    },
    "metodo_pago": {
        METODO_STRIPE: "Stripe",
        METODO_MOCK: "Simulado",
    },
}


class Maestra(db.Model):
    """Catálogos genéricos: roles, estados y métodos de pago."""

    __tablename__ = "maestra"
    __table_args__ = (UniqueConstraint("tipo", "codigo", name="uq_maestra_tipo_codigo"),)

    id = db.Column(db.Integer, primary_key=True)
    tipo = db.Column(db.String(30), nullable=False, index=True)
    codigo = db.Column(db.String(30), nullable=False)
    valor = db.Column(db.String(80), nullable=False)

    @staticmethod
    def por_codigo(tipo, codigo):
        return db.session.execute(
            db.select(Maestra).filter_by(tipo=tipo, codigo=codigo)
        ).scalar_one_or_none()

    @staticmethod
    def codigos(tipo):
        return {
            m.codigo
            for m in db.session.execute(
                db.select(Maestra).filter_by(tipo=tipo)
            ).scalars()
        }

    def to_dict(self):
        return {"id": self.id, "tipo": self.tipo, "codigo": self.codigo, "valor": self.valor}


class Cliente(db.Model):
    """Usuario del sistema. `rol_id` apunta a `Maestra` (tipo `rol`)."""

    __tablename__ = "cliente"

    id = db.Column(db.Integer, primary_key=True)
    nombre = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(180), nullable=False, unique=True, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    rol_id = db.Column(db.Integer, db.ForeignKey("maestra.id", ondelete="RESTRICT"), nullable=False)
    activo = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())
    creado_en = db.Column(db.DateTime, nullable=False, server_default=func.now())

    rol_ref = db.relationship("Maestra", lazy="joined")
    canchas = db.relationship("Cancha", back_populates="dueno", lazy="select")
    reservas = db.relationship("Reserva", back_populates="cliente", lazy="select")

    # --- password -----------------------------------------------------------
    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    # --- serialización ------------------------------------------------------
    @property
    def rol(self):
        return self.rol_ref.codigo if self.rol_ref else None

    def to_dict(self):
        return {
            "id": self.id,
            "nombre": self.nombre,
            "email": self.email,
            "rol": self.rol,
            "activo": self.activo,
        }


class Cancha(db.Model):
    """Cancha sintética. `dueno_id` es el aislamiento multi-dueño (spec.md 3.4)."""

    __tablename__ = "cancha"

    id = db.Column(db.Integer, primary_key=True)
    nombre = db.Column(db.String(120), nullable=False)
    ubicacion = db.Column(db.String(200), nullable=False)
    foto = db.Column(db.String(500), nullable=False, default="", server_default="")
    activo = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())
    dueno_id = db.Column(db.Integer, db.ForeignKey("cliente.id", ondelete="RESTRICT"), nullable=False)
    creado_en = db.Column(db.DateTime, nullable=False, server_default=func.now())

    dueno = db.relationship("Cliente", back_populates="canchas")
    horarios = db.relationship(
        "Horario", back_populates="cancha", lazy="select", cascade="all, delete-orphan"
    )
    reservas = db.relationship("Reserva", back_populates="cancha", lazy="select")

    def to_dict(self, con_dueno=False):
        data = {"id": self.id, "nombre": self.nombre, "ubicacion": self.ubicacion, "foto": self.foto}
        if con_dueno:
            data["activo"] = self.activo
            data["dueno_id"] = self.dueno_id
        return data


class Horario(db.Model):
    """Slot y tarifa de una cancha. `dia` sigue la convención ISO: 0 = lunes."""

    __tablename__ = "horario"
    __table_args__ = (
        UniqueConstraint("cancha_id", "dia", "hora_inicio", name="uq_horario_cancha_dia_inicio"),
        CheckConstraint("dia >= 0 AND dia <= 6", name="ck_horario_dia_iso"),
        CheckConstraint("hora_fin > hora_inicio", name="ck_horario_orden"),
    )

    id = db.Column(db.Integer, primary_key=True)
    cancha_id = db.Column(db.Integer, db.ForeignKey("cancha.id", ondelete="CASCADE"), nullable=False)
    dia = db.Column(db.SmallInteger, nullable=False)
    hora_inicio = db.Column(db.Time, nullable=False)
    hora_fin = db.Column(db.Time, nullable=False)
    tarifa = db.Column(db.Numeric(10, 2), nullable=False)

    cancha = db.relationship("Cancha", back_populates="horarios")
    reservas = db.relationship("Reserva", back_populates="horario", lazy="select")

    def to_dict(self):
        return {
            "id": self.id,
            "cancha_id": self.cancha_id,
            "dia": self.dia,
            "hora_inicio": self.hora_inicio.strftime("%H:%M"),
            "hora_fin": self.hora_fin.strftime("%H:%M"),
            "tarifa": float(self.tarifa),
        }


class Reserva(db.Model):
    """Reserva de un slot por un cliente.

    El índice UNIQUE parcial `(cancha_id, horario_id, fecha) WHERE estado != 'cancelada'`
    es la fuente del `409` de spec.md 3.2: un slot sólo admite una reserva viva por día.
    Al ser parcial, una reserva cancelada libera el slot para otra reserva sin perder su
    histórico, que es lo que la disponibilidad promete al cliente.
    """

    __tablename__ = "reserva"
    __table_args__ = (
        Index(
            "uq_reserva_slot_fecha",
            "cancha_id",
            "horario_id",
            "fecha",
            unique=True,
            sqlite_where=text("estado != 'cancelada'"),
            postgresql_where=text("estado != 'cancelada'"),
        ),
    )

    id = db.Column(db.Integer, primary_key=True)
    cliente_id = db.Column(db.Integer, db.ForeignKey("cliente.id", ondelete="RESTRICT"), nullable=False)
    cancha_id = db.Column(db.Integer, db.ForeignKey("cancha.id", ondelete="RESTRICT"), nullable=False)
    horario_id = db.Column(db.Integer, db.ForeignKey("horario.id", ondelete="RESTRICT"), nullable=False)
    fecha = db.Column(db.Date, nullable=False)
    estado = db.Column(db.String(20), nullable=False, default=ESTADO_PENDIENTE_PAGO)
    creado_en = db.Column(db.DateTime, nullable=False, server_default=func.now())

    cliente = db.relationship("Cliente", back_populates="reservas")
    cancha = db.relationship("Cancha", back_populates="reservas")
    horario = db.relationship("Horario", back_populates="reservas")
    pago = db.relationship("Pago", back_populates="reserva", uselist=False, lazy="select")

    def to_dict(self):
        return {
            "reserva_id": self.id,
            "cancha": {
                "id": self.cancha.id,
                "nombre": self.cancha.nombre,
                "ubicacion": self.cancha.ubicacion,
            },
            "horario": {
                "id": self.horario.id,
                "hora_inicio": self.horario.hora_inicio.strftime("%H:%M"),
                "hora_fin": self.horario.hora_fin.strftime("%H:%M"),
                "tarifa": float(self.horario.tarifa),
            },
            "fecha": self.fecha.isoformat(),
            "estado": self.estado,
            "pago": self.pago.to_dict() if self.pago else None,
        }

    def to_dict_gestion(self):
        """Lo mismo que `to_dict` más quién reservó (spec.md 3.4).

        El dueño necesita saber a quién le prestó la cancha, pero no necesita el correo:
        incluirlo expondría el dato personal del cliente a un tercero sin que el contrato
        lo pida.
        """
        datos = self.to_dict()
        datos["cancha"]["activo"] = self.cancha.activo
        datos["cliente"] = {"id": self.cliente.id, "nombre": self.cliente.nombre}
        return datos


class Pago(db.Model):
    """Pago de una reserva. `reserva_id` UNIQUE: una reserva, un pago."""

    __tablename__ = "pago"

    id = db.Column(db.Integer, primary_key=True)
    reserva_id = db.Column(db.Integer, db.ForeignKey("reserva.id", ondelete="CASCADE"), nullable=False, unique=True)
    monto = db.Column(db.Numeric(10, 2), nullable=False)
    metodo = db.Column(db.String(20), nullable=False, default=METODO_MOCK)
    estado = db.Column(db.String(20), nullable=False, default=PAGO_PENDIENTE)
    gateway_ref = db.Column(db.String(255))
    creado_en = db.Column(db.DateTime, nullable=False, server_default=func.now())
    actualizado_en = db.Column(
        db.DateTime, nullable=False, server_default=func.now(), onupdate=func.now()
    )

    reserva = db.relationship("Reserva", back_populates="pago")

    def to_dict(self):
        return {
            "id": self.id,
            "reserva_id": self.reserva_id,
            "monto": float(self.monto) if isinstance(self.monto, Decimal) else self.monto,
            "metodo": self.metodo,
            "estado": self.estado,
        }


__all__ = [
    "db",
    "CATALOGOS",
    "Maestra",
    "Cliente",
    "Cancha",
    "Horario",
    "Reserva",
    "Pago",
    "ROL_CLIENTE",
    "ROL_DUENO",
    "ROL_ADMIN",
    "ESTADO_PENDIENTE_PAGO",
    "ESTADO_CONFIRMADA",
    "ESTADO_CANCELADA",
    "PAGO_PENDIENTE",
    "PAGO_APROBADO",
    "PAGO_RECHAZADO",
    "METODO_STRIPE",
    "METODO_MOCK",
    "time",
    "datetime",
]

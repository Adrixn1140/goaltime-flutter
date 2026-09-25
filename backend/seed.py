"""Datos de prueba (spec.md, Fase 2 del plan).

Crea catálogos, 1 admin, 2 dueños, 3 canchas (dos de un dueño, una del otro: así el
aislamiento por `dueno_id` se puede comprobar de verdad), 7 días de horarios y
1 cliente. Es **idempotente**: se puede ejecutar tantas veces como haga falta.

    flask seed        # con el venv activo
    python seed.py    # alternativa sin el comando de Flask
"""

from datetime import time

from extensions import db
from models import (
    CATALOGOS,
    ROL_ADMIN,
    ROL_CLIENTE,
    ROL_DUENO,
    Cancha,
    Cliente,
    Horario,
    Maestra,
)

PASSWORD_PRUEBA = "Goaltime123!"

USUARIOS = [
    ("admin@goaltime.test", "Administración GoalTime", ROL_ADMIN),
    ("dueno1@goaltime.test", "Diego Ownes", ROL_DUENO),
    ("dueno2@goaltime.test", "Sara Dueña", ROL_DUENO),
    ("cliente@goaltime.test", "Carla Cliente", ROL_CLIENTE),
]

CANCHAS = [
    # (dueño, nombre, ubicación, tarifa de todos sus slots)
    ("dueno1@goaltime.test", "Cancha El Rodadero", "Cra 9 #12-45, Riohacha", 60000),
    ("dueno1@goaltime.test", "Cancha Mar de Cisneros", "Cra 7 #30-10, Riohacha", 72000),
    ("dueno2@goaltime.test", "Cancha La Bocana", "Cra 3 #8-22, Riohacha", 55000),
]

# (hora_inicio, hora_fin) — 7 días (lunes=0) con los mismos tres slots
SLOTS = [
    (time(8, 0), time(10, 0)),
    (time(10, 0), time(12, 0)),
    (time(16, 0), time(18, 0)),
]


def _cargar_catalogos():
    for tipo, entradas in CATALOGOS.items():
        for codigo, valor in entradas.items():
            if Maestra.por_codigo(tipo, codigo) is None:
                db.session.add(Maestra(tipo=tipo, codigo=codigo, valor=valor))
    db.session.flush()


def _crear_usuarios():
    clientes = {}
    for email, nombre, rol_codigo in USUARIOS:
        cliente = db.session.execute(db.select(Cliente).filter_by(email=email)).scalar_one_or_none()
        if cliente is None:
            rol = Maestra.por_codigo("rol", rol_codigo)
            cliente = Cliente(nombre=nombre, email=email, rol_id=rol.id)
            cliente.set_password(PASSWORD_PRUEBA)
            db.session.add(cliente)
            db.session.flush()
        clientes[rol_codigo] = clientes.get(rol_codigo, {})
        clientes[rol_codigo][email] = cliente
    return {email: cliente for grupo in clientes.values() for email, cliente in grupo.items()}


def _crear_canchas(usuarios):
    for email_dueno, nombre, ubicacion, tarifa in CANCHAS:
        dueno = usuarios[email_dueno]
        cancha = db.session.execute(
            db.select(Cancha).filter_by(nombre=nombre, dueno_id=dueno.id)
        ).scalar_one_or_none()
        if cancha is None:
            cancha = Cancha(nombre=nombre, ubicacion=ubicacion, dueno_id=dueno.id)
            db.session.add(cancha)
            db.session.flush()
        _crear_horarios(cancha, tarifa)


def _crear_horarios(cancha, tarifa):
    for dia in range(7):
        for hora_inicio, hora_fin in SLOTS:
            existe = db.session.execute(
                db.select(Horario).filter_by(
                    cancha_id=cancha.id, dia=dia, hora_inicio=hora_inicio
                )
            ).scalar_one_or_none()
            if existe is None:
                db.session.add(
                    Horario(
                        cancha_id=cancha.id,
                        dia=dia,
                        hora_inicio=hora_inicio,
                        hora_fin=hora_fin,
                        tarifa=tarifa,
                    )
                )
    db.session.flush()


def ejecutar_seed():
    db.create_all()
    _cargar_catalogos()
    usuarios = _crear_usuarios()
    _crear_canchas(usuarios)
    db.session.commit()

    canchas = db.session.execute(db.select(Cancha)).scalars().all()
    horarios = db.session.execute(db.select(Horario)).scalars().all()
    print("Datos de prueba listos (idempotente).")
    print(f"  roles en catálogo : {len(Maestra.codigos('rol'))}")
    print(f"  usuarios          : {len(usuarios)}")
    print(f"  canchas           : {len(canchas)}")
    print(f"  horarios          : {len(horarios)}")
    print(f"\n  Credenciales (password: {PASSWORD_PRUEBA})")
    for email, _, rol_codigo in USUARIOS:
        print(f"    {rol_codigo:8s} {email}")


if __name__ == "__main__":
    from app import app

    with app.app_context():
        ejecutar_seed()

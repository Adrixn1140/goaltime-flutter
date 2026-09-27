"""Fixtures compartidas.

`conftest.py` inserta la raíz de `backend/` en `sys.path` porque el proyecto usa el
layout plano de Flask (módulos de primer nivel: `app`, `models`, `config`).

Los datos de prueba se **confirman** (`commit`), no sólo se vuelcan: varios endpoints
hacen `rollback` al detectar un conflicto, y si las fixtures vivieran en la transacción
pendiente ese rollback se llevaría por delante al cliente, la cancha y el horario, con
lo que las pruebas de atomicidad y de `409` no podrían distinguir un bug de un artefacto
del andamiaje.
"""

import sys
from datetime import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import create_app  # noqa: E402
from config import TestConfig  # noqa: E402
from extensions import db  # noqa: E402
from models import (  # noqa: E402
    CATALOGOS,
    ROL_CLIENTE,
    ROL_DUENO,
    Cancha,
    Cliente,
    Horario,
    Maestra,
)


@pytest.fixture()
def app():
    aplicacion = create_app(TestConfig)
    with aplicacion.app_context():
        # El `drop_all` de arranque no es desconfianza: es idempotencia. Una corrida
        # interrumpida deja las tablas y sus filas en PostgreSQL, y la siguiente falla con
        # `duplicate key` en los catálogos al empezar, sin que nadie haya tocado el
        # código. En SQLite el esquema vive en memoria y nunca pasa; con una base de
        # verdad, pasar es obligatorio.
        db.drop_all()
        db.create_all()
        _cargar_catalogos()
        yield aplicacion
        db.session.remove()
        db.drop_all()
        # `dispose()` no es opcional cuando la base es PostgreSQL. Cada test crea su propia
        # app y por tanto su propio engine con su propio pool; sin cerrar ese pool, las
        # conexiones se quedan vivas con transacciones abiertas y `DROP TABLE` del test
        # siguiente se queda esperando un bloqueo que nadie va a soltar, y agota el
        # `pool_timeout` de 30 segundos por operación, que es exactamente como se ve desde
        # fuera: 30 segundos por test y ningún fallo. En SQLite no se nota, porque cada
        # engine abre su base en memoria y no hay nadie bloqueando a nadie.
        db.engine.dispose()


@pytest.fixture()
def client(app):
    return app.test_client()


def _cargar_catalogos():
    for tipo, entradas in CATALOGOS.items():
        for codigo, valor in entradas.items():
            db.session.add(Maestra(tipo=tipo, codigo=codigo, valor=valor))
    db.session.commit()


def _crear_cliente(email, rol_codigo, nombre="Usuario Prueba", password="Goaltime123!"):
    rol = Maestra.por_codigo("rol", rol_codigo)
    cliente = Cliente(nombre=nombre, email=email, rol_id=rol.id)
    cliente.set_password(password)
    db.session.add(cliente)
    db.session.commit()
    return cliente


@pytest.fixture()
def cliente(app):
    return _crear_cliente("cliente@test.co", ROL_CLIENTE, "Carla Cliente")


@pytest.fixture()
def dueno(app):
    return _crear_cliente("dueno@test.co", ROL_DUENO, "Diego Ownes")


@pytest.fixture()
def dueno_otro(app):
    """Un segundo dueño: sirve para comprobar que la gestión no se sale de su cuenta.

    Sin él, una fuga entre dueños pasaría inadvertida en casi todos los tests, porque
    comparar contra el `404` de un id inexistente da el mismo resultado que comparar
    contra el `404` de una cancha ajena.
    """
    return _crear_cliente("dueno2@test.co", ROL_DUENO, "Sara Ownes")


@pytest.fixture()
def admin(app):
    return _crear_cliente("admin@test.co", "admin", "Admin GoalTime")


@pytest.fixture()
def cancha(app, dueno):
    cancha = Cancha(nombre="Cancha Prueba", ubicacion="Cra 1 #2-3", dueno_id=dueno.id)
    db.session.add(cancha)
    db.session.commit()
    return cancha


@pytest.fixture()
def horario(app, cancha):
    horario = Horario(
        cancha_id=cancha.id, dia=0, hora_inicio=time(8, 0), hora_fin=time(10, 0), tarifa=60000
    )
    db.session.add(horario)
    db.session.commit()
    return horario

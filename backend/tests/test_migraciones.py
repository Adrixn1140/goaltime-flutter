"""Guardián anti-drift: el esquema no puede apartarse de los modelos (spec.md 7.5).

Hay una forma de cambiar `models.py` sin que nadie se entere: agregar una columna al
modelo y no escribir la migración. Los tests siguen en verde —Ellos usan
`db.create_all()` sobre una base efímera—, la app sigue en verde en SQLite y el primer
que lo nota es el despliegue, en PostgreSQL, con un `UndefinedColumn` en producción.

`alembic check` es lo que lo atrapa: compara el esquema real de la base contra
`db.metadata` y falla si ve diferencias. Estos tests comprueban dos cosas, y las dos
importan:

1. Que pasa con los modelos como están. Si el guardián dijera "differences" con el
   esquema correcto, nadie lo leería y la primera alerta real se perdería en un
   `xfail`.
2. **Que tiene dientes**: se agrega una columna a la base a mano y se verifica que
   `check` falla. Un guardián que no detecta nada es peor que ninguno, porque da
   confianza falsa.

La base es un SQLite temporal y se crea **migrando** (`upgrade head`), no con
`create_all()`: si la migración inicial no construyera el esquema completo, este archivo
lo notaría, que es justo lo que se le pide a §7.1.
"""

from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config as ConfigAlembic
from alembic.util import CommandError
from sqlalchemy import create_engine, text

from config import Config as ConfigApp

RAIZ = Path(__file__).resolve().parents[1]


def _config_para(url: str, monkeypatch) -> ConfigAlembic:
    """Configuración de Alembic apuntando a [url].

    `migrations/env.py` saca la URL de `Config.SQLALCHEMY_DATABASE_URI` —a propósito, para
    que migraciones y app no puedan usar bases distintas—, así que hay que mover esa clase
    y no el `sqlalchemy.url` de `alembic.ini`, que `env.py` sobrescribe.
    """
    monkeypatch.setattr(ConfigApp, "SQLALCHEMY_DATABASE_URI", url)
    cfg = ConfigAlembic(str(RAIZ / "alembic.ini"))
    cfg.set_main_option("script_location", str(RAIZ / "migrations"))
    return cfg


def _base_migrada(cfg: ConfigAlembic) -> None:
    command.upgrade(cfg, "head")


def test_sqlite_relativo_migra_la_misma_base_que_flask(tmp_path, monkeypatch):
    from flask import Flask
    from sqlalchemy import inspect

    import config
    from extensions import db

    monkeypatch.setattr(config, "BASE_DIR", tmp_path)
    monkeypatch.chdir(tmp_path)
    cfg = _config_para("sqlite:///goaltime.db", monkeypatch)
    _base_migrada(cfg)

    app = Flask(__name__, instance_path=str(tmp_path / "instance"))
    app.config.from_object(ConfigApp)
    db.init_app(app)
    with app.app_context():
        assert set(db.metadata.tables) <= set(inspect(db.engine).get_table_names())
    assert not (tmp_path / "goaltime.db").exists()


def test_preparar_demo_migra_y_siembra_sin_duplicar(tmp_path, monkeypatch):
    from app import create_app
    from extensions import db
    from models import Cliente, Cancha, Horario

    monkeypatch.setattr(ConfigApp, "SQLALCHEMY_DATABASE_URI", f"sqlite:///{tmp_path / 'demo.sqlite'}")
    app = create_app(ConfigApp)
    runner = app.test_cli_runner()
    for _ in range(2):
        resultado = runner.invoke(args=["preparar-demo"])
        assert resultado.exit_code == 0, resultado.output
    with app.app_context():
        assert db.session.query(Cliente).count() == 4
        assert db.session.query(Cancha).count() == 3
        assert db.session.query(Horario).count() == 63
        db.engine.dispose()
    respuesta = app.test_client().post("/api/login", json={"email": "cliente@goaltime.test", "password": "Goaltime123!"})
    assert respuesta.status_code == 200


def test_la_migracion_inicial_construye_el_esquema_que_dicen_los_modelos(tmp_path, monkeypatch):
    """Migrar desde cero tiene que dejar el esquema que describen los modelos.

    La lista de tablas no está escrita a mano sino que sale de `db.metadata`: una lista
    fija sólo comprobaría las tablas que alguien se acordaba de escribir, y el olvido
    sería justo el fallo que este archivo existe para cazar.
    """
    url = f"sqlite:///{tmp_path / 'deriva.sqlite'}"
    cfg = _config_para(url, monkeypatch)
    _base_migrada(cfg)

    motor = create_engine(url)
    with motor.connect() as conexion:
        tablas = {
            fila[0]
            for fila in conexion.execute(
                text("select name from sqlite_master where type = 'table'")
            )
        }
    motor.dispose()

    import models  # noqa: F401  (sin esto `db.metadata` está vacío)
    from extensions import db

    esperadas = set(db.metadata.tables)
    # Lo único que puede sobrar es infraestructura de la migración y de SQLite.
    intrusos = tablas - esperadas - {"alembic_version", "sqlite_sequence"}

    assert esperadas <= tablas, f"faltan tablas tras migrar: {sorted(esperadas - tablas)}"
    assert not intrusos, f"la migración creó tablas que ningún modelo declara: {sorted(intrusos)}"


def test_alembic_check_pasa_con_los_modelos_actuales(tmp_path, monkeypatch):
    """La condición de salida del guardián: sin diferencias, no dice nada."""
    url = f"sqlite:///{tmp_path / 'deriva.sqlite'}"
    cfg = _config_para(url, monkeypatch)
    _base_migrada(cfg)

    command.check(cfg)


def test_alembic_check_falla_si_una_columna_no_tiene_migracion(tmp_path, monkeypatch):
    """La parte que importa: el guardián detecta el olvido.

    Se reproduce el error humano —una columna en el modelo, ninguna migración— del lado
    de la base, que es donde `check` mira, y se espera el fallo.
    """
    url = f"sqlite:///{tmp_path / 'deriva.sqlite'}"
    cfg = _config_para(url, monkeypatch)
    _base_migrada(cfg)

    motor = create_engine(url)
    with motor.begin() as conexion:
        conexion.execute(text("ALTER TABLE cliente ADD COLUMN columna_sin_migracion TEXT"))
    motor.dispose()

    with pytest.raises(CommandError) as fallo:
        command.check(cfg)

    assert "cliente" in str(fallo.value)

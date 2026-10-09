"""Entorno de Alembic (spec.md 7.1).

Sólo tiene un trabajo real: entregarle a Alembic el `MetaData` de la aplicación y la URL
de `DATABASE_URL`, de modo que las migraciones y el modelo hablan del mismo esquema. El
resto es el andamiaje estándar, con tres decisiones que no son las de por defecto:

- `compare_type`: sin él, `alembic check` sólo detectaría tablas y columnas, y un
  `String(120)` que pasa a `String(180)` se iría sin avisar.
- `compare_server_default`, pero **sólo fuera de SQLite**: ver `_comparar_default`.
- `include_schemas=False` y sin `version_table`: el esquema es público y de una sola
  base; no hay nada que aislar.
- **`render_as_batch` sólo en SQLite.** PostgreSQL hace `ALTER TABLE` de verdad; SQLite
  no, y su forma de emularlo es re-crear la tabla y copiar los datos. Como los tests
  corren `upgrade head` sobre un archivo temporal, el modo batch es lo que permite que
  esa base efímera exista sin divergir de la de producción.
"""

import sys
from logging.config import fileConfig
from pathlib import Path

from alembic import context
from sqlalchemy import engine_from_config, pool
from sqlalchemy.engine import make_url

# Layout plano de Flask (módulos de primer nivel), igual que `tests/conftest.py`.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import models  # noqa: F401  (importa todos los modelos: sin esto, el MetaData está vacío)
from config import BASE_DIR, Config
from extensions import db

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

#: La URL sale del entorno, igual que la usa la app. Sin `DATABASE_URL` se cae al valor
#: de desarrollo, para que `alembic` sea utilizable sin `.env`.
_url = Config.SQLALCHEMY_DATABASE_URI
_parsed_url = make_url(_url)
if _parsed_url.get_backend_name() == "sqlite" and _parsed_url.database not in (None, "", ":memory:"):
    _database = Path(_parsed_url.database)
    if not _database.is_absolute():
        # Flask-SQLAlchemy resuelve SQLite relativo contra backend/instance,
        # no contra el directorio desde el que se ejecuta Alembic.
        _instance = BASE_DIR / "instance"
        _instance.mkdir(parents=True, exist_ok=True)
        _url = _parsed_url.set(database=(_instance / _database).resolve().as_posix()).render_as_string(hide_password=False)
config.set_main_option("sqlalchemy.url", _url.replace("%", "%%"))

#: `db.metadata` con todos los modelos ya importados arriba.
target_metadata = db.metadata

_es_sqlite = _url.startswith("sqlite")


#: ¿Comparar los `server_default`? Sólo donde la reflexión es fiel.
#:
#: En PostgreSQL `alembic check` los compara bien. En SQLite no: refleja
#: `DEFAULT ''` y `DEFAULT true` como texto crudo y no los puede emparejar con los objetos
#: tipados del modelo (`DefaultClause('')` contra `DefaultClause(TextClause)`), así que
#: las tres columnas con default dan drift falso. Se comprobó: en la misma base, sin
#: cambiar nada, `check` pasa en PostgreSQL y falla en SQLite. Por eso la comparación de
#: defaults vive en la corrida contra PostgreSQL (CI y `tool/verificar_integracion.sh`), y
#: la local en SQLite —que es donde corren los tests— compara estructura y tipos.
_comparar_default = not _es_sqlite


def run_migrations_offline() -> None:
    """Genera el SQL sin conectarse. Útil para revisar en el pull request qué va a
    tocar una migración antes de aplicarla."""
    context.configure(
        url=_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        compare_server_default=_comparar_default,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=_comparar_default,
            # Sólo SQLite lo necesita: PostgreSQL altera la tabla en el sitio.
            render_as_batch=_es_sqlite,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

"""Fábrica de la aplicación Flask (GoalTime API).

Punto de entrada: `flask --app app run --host=0.0.0.0 --port=5000`.
"""

from flask import Flask, jsonify
from sqlalchemy import event
from sqlalchemy.engine import Engine

from blueprints.admin import bp as admin_bp
from blueprints.asistente import bp as asistente_bp
from blueprints.auth import bp as auth_bp
from blueprints.canchas import bp as canchas_bp
from blueprints.disponibilidad import bp as disponibilidad_bp
from blueprints.equipos import bp as equipos_bp
from blueprints.gestion import bp as gestion_bp
from blueprints.pagos import bp as pagos_bp
from blueprints.reservas import bp as reservas_bp
from config import Config
from errors import error_response, registrar_handlers
from extensions import cors, db, jwt


@event.listens_for(Engine, "connect")
def _activar_claves_foraneas_sqlite(dbapi_connection, _record):
    """SQLite ignora las FK por omisión; sin esto, `ondelete` y el aislamiento
    multi-dueño no se upholden en desarrollo."""
    if dbapi_connection.__class__.__module__.startswith("sqlite3"):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


def create_app(config_object=Config):
    app = Flask(__name__)
    app.config.from_object(config_object)

    db.init_app(app)
    jwt.init_app(app)
    cors.init_app(app, resources={r"/api/*": {"origins": app.config["CORS_ORIGINS"]}})

    registrar_handlers(app)
    _registrar_errores_jwt(app)
    _registrar_health(app)
    _registrar_cli(app)

    app.register_blueprint(auth_bp, url_prefix="/api")
    app.register_blueprint(canchas_bp, url_prefix="/api")
    app.register_blueprint(disponibilidad_bp, url_prefix="/api")
    app.register_blueprint(equipos_bp, url_prefix="/api")
    app.register_blueprint(reservas_bp, url_prefix="/api")
    app.register_blueprint(pagos_bp, url_prefix="/api")
    app.register_blueprint(gestion_bp, url_prefix="/api")
    app.register_blueprint(admin_bp, url_prefix="/api")
    app.register_blueprint(asistente_bp, url_prefix="/api")

    return app


def _registrar_health(app):
    @app.get("/api/health")
    def health():
        return jsonify({"estado": "ok", "servicio": "goaltime-api", "version": "1.0.0"})


def _registrar_errores_jwt(app):
    """Los errores de JWT usan el mismo formato que el resto de la API."""

    @jwt.unauthorized_loader
    def _sin_token(_motivo):
        return error_response(401, "Debes iniciar sesión para continuar")

    @jwt.invalid_token_loader
    def _token_invalido(_motivo):
        return error_response(401, "La sesión no es válida")

    @jwt.expired_token_loader
    def _token_vencido(_jti, _claims):
        return error_response(401, "Tu sesión expiró, vuelve a iniciar sesión")

    @jwt.revoked_token_loader
    def _token_revocado(_jti, _claims):
        return error_response(401, "Tu sesión fue cerrada, vuelve a iniciar sesión")


def _registrar_cli(app):
    @app.cli.command("preparar-demo")
    def preparar_demo():
        """Migra y carga datos de prueba sin borrar datos existentes (desarrollo)."""
        from pathlib import Path
        from alembic import command
        from alembic.config import Config as AlembicConfig
        from seed import ejecutar_seed

        raiz = Path(__file__).resolve().parent
        cfg = AlembicConfig(str(raiz / "alembic.ini"))
        cfg.set_main_option("script_location", str(raiz / "migrations"))
        command.upgrade(cfg, "head")
        ejecutar_seed()
        print("Demo preparada. Inicia el servidor con flask --app app run --host=0.0.0.0 --port=5000")

    @app.cli.command("seed-catalogo")
    def seed_catalogo():
        """Siembra los catálogos de `maestra` (idempotente).

        Vive aparte de `flask seed` y del esquema porque son cosas distintas: el esquema
        lo migra Alembic (`alembic upgrade head`, spec.md 7.1) y los catálogos son datos.
        Una instalación real sólo necesita este comando; los usuarios los crea la gente.
        """
        from seed import cargar_catalogos

        print(f"Catálogos listos: {cargar_catalogos()} filas en `maestra`.")

    @app.cli.command("seed")
    def seed():
        """Crea usuarios, canchas y horarios de prueba (idempotente)."""
        from seed import ejecutar_seed

        ejecutar_seed()


app = create_app()

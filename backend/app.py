"""Fábrica de la aplicación Flask (GoalTime API).

Punto de entrada: `flask --app app run --host=0.0.0.0 --port=5000`.
"""

from flask import Flask, jsonify
from sqlalchemy import event
from sqlalchemy.engine import Engine

from blueprints.auth import bp as auth_bp
from blueprints.canchas import bp as canchas_bp
from blueprints.disponibilidad import bp as disponibilidad_bp
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
    app.register_blueprint(reservas_bp, url_prefix="/api")
    app.register_blueprint(pagos_bp, url_prefix="/api")

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
    @app.cli.command("init-db")
    def init_db():
        """Crea las tablas del catálogo `maestra` y el resto del esquema."""
        from models import CATALOGOS, Maestra

        db.create_all()
        for tipo, entradas in CATALOGOS.items():
            for codigo, valor in entradas.items():
                if Maestra.por_codigo(tipo, codigo) is None:
                    db.session.add(Maestra(tipo=tipo, codigo=codigo, valor=valor))
        db.session.commit()
        print("Tablas creadas y catálogos cargados.")

    @app.cli.command("seed")
    def seed():
        """Crea usuarios, canchas y horarios de prueba (idempotente)."""
        from seed import ejecutar_seed

        ejecutar_seed()


app = create_app()

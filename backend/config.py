"""Configuración por entorno.

Lee `.env` (ver `.env.example`) y expone un objeto `Config` por clase que Flask
consume vía `app.config.from_object`. Los valores por defecto permiten correr los
tests sin `.env`.
"""

import os
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent

load_dotenv(BASE_DIR / ".env")

#: Origenes permitidos por CORS. En desarrollo se abre con `*` porque la app se
#: sirve desde el emulador o el dispositivo; en produccion se acota a los dominios
#: reales (HEUR-5: no abrir más superficie de la necesaria).
CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*")


class Config:
    SECRET_KEY = os.getenv("JWT_SECRET_KEY", "dev-secret-cambiar-en-produccion")

    #: Ruta **relativa** a propósito: Flask-SQLAlchemy resuelve las rutas relativas de
    #: SQLite contra `app.instance_path`, así el archivo cae en `backend/instance/` y
    #: nunca junto al código. Con una ruta absoluta el `rm -f instance/goaltime.db` del
    #: README no borraría la base real y aparecería una segunda.
    SQLALCHEMY_DATABASE_URI = os.getenv("DATABASE_URL", "sqlite:///goaltime.db")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True}

    JWT_SECRET_KEY = SECRET_KEY
    #: Se lee en **horas** y no en el `JWT_ACCESS_TOKEN_EXPIRES` de flask-jwt-extended
    #: porque ese valor de configuración tiene que poder restarse a un `datetime`: sólo
    #: acepta `timedelta`, y un "12h" leído del entorno reventaría al firmar el token.
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=int(os.getenv("JWT_ACCESS_TOKEN_HOURS", "12")))

    #: Tope del cuerpo de la petición. Protege el webhook de un body abusivo
    #: (spec.md 3.3: nunca confiar en el body antes de verificar la firma).
    MAX_CONTENT_LENGTH = 64 * 1024

    PAGADORA = os.getenv("PAGADORA", "mock")
    STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "")
    STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")
    STRIPE_CURRENCY = os.getenv("STRIPE_CURRENCY", "cop")

    #: Base pública de la app; de aquí salen las URLs de retorno de Stripe Checkout.
    APP_URL_BASE = os.getenv("APP_URL_BASE", "http://localhost:5000")

    CORS_ORIGINS = CORS_ORIGINS


class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    JWT_SECRET_KEY = "test-secret-goaltime-suficientemente-largo"
    PAGADORA = "mock"

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

    # --- Asistente de lenguaje natural (spec.md 3.6) ---------------------------------------
    #: `mock` por omisión, no `ollama`. Es la decisión que permite que `pytest` y CI
    #: corran sin un modelo cargado: un test que necesita un LLM local no es un test, es
    #: una prueba de integración con una dependencia de 4 GB. Igual que `PAGADORA=mock`
    #: permite probar el flujo de pago sin claves de Stripe, aquí se prueba el asistente
    #: sin modelo.
    LLM_PROVEEDOR = os.getenv("LLM_PROVEEDOR", "mock")

    #: Ollama corre en local, así que no hay llave y no sale nada de la máquina. El modelo
    #: por omisión es de los que entran en la RAM que tiene este proyecto documentada
    #: (ver `PLAN.md` §3.1): con menos de 4 GB libres, un 7B no arranca.
    OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
    OLLAMA_MODELO = os.getenv("OLLAMA_MODELO", "qwen2.5:3b")

    #: Gemini sí sale a la red, así que la llave es del backend y nunca de la app: una
    #: llave dentro de un APK es una llave pública (spec.md 3.6 y 7.2).
    GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
    GEMINI_MODELO = os.getenv("GEMINI_MODELO", "gemini-3.6-flash")

    #: Canchas que el motor `mock` sabe nombrar. Separadas por coma porque en el mock son
    #: datos, no una consulta: el mock no toca la base, y por eso necesita que le digan
    #: qué canchas existen. Vacío significa "el mock no reconoce ninguna", que es un
    #: mock que siempre devuelve sugerencias de todas las canchas.
    LLM_MOCK_CANCHAS = tuple(
        c.strip() for c in os.getenv("LLM_MOCK_CANCHAS", "").split(",") if c.strip()
    )

    #: Base pública de la app; de aquí salen las URLs de retorno de Stripe Checkout.
    APP_URL_BASE = os.getenv("APP_URL_BASE", "http://localhost:5000")

    CORS_ORIGINS = CORS_ORIGINS


class TestConfig(Config):
    TESTING = True
    #: SQLite en memoria por omisión, porque `pytest` no debe depender de nada instalado.
    #:
    #: `TEST_DATABASE_URL` existe para el caso que SQLite no puede representar: varchar que
    #: no se aplican, `Numeric(10,2)` que acepta de más, orden por collation, índices
    #: parciales. Un job de CI que dice "probamos con PostgreSQL" mientras la suite corre
    #: sobre SQLite no prueba nada, y es peor que no tener ese job: da confianza que no
    #: está ganada. Con esta variable el job de PostgreSQL de `.github/workflows/ci.yml`
    #: corre la suite completa de verdad.
    SQLALCHEMY_DATABASE_URI = os.getenv("TEST_DATABASE_URL", "sqlite:///:memory:")
    JWT_SECRET_KEY = "test-secret-goaltime-suficientemente-largo"
    PAGADORA = "mock"
    #: El asistente se prueba contra el motor `mock` y **nunca** contra un proveedor real:
    #: un test que hable con Ollama o con Gemini deja de ser un test, y su primer síntoma
    #: es que alguien lo marca para saltárselo cuando va lento.
    LLM_PROVEEDOR = "mock"

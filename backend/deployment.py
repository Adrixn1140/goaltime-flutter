"""Configuración de despliegue sin conexiones ni secretos en los mensajes de error."""

from ipaddress import ip_address
import re
from urllib.parse import urlsplit

from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError


def normalizar_database_url(valor):
    # Supabase entrega postgresql://; el driver instalado en este proyecto es psycopg 3.
    try:
        url = make_url(valor)
    except (ArgumentError, TypeError):
        raise ValueError("DATABASE_URL no tiene un formato válido") from None
    if url.drivername in ("postgres", "postgresql"):
        url = url.set(drivername="postgresql+psycopg")
    return url.render_as_string(hide_password=False)


def opciones_motor(valor):
    opciones = {"pool_pre_ping": True}
    if make_url(valor).get_backend_name() == "postgresql":
        opciones.update(pool_size=2, max_overflow=0, pool_timeout=10, pool_recycle=300,
                        connect_args={"connect_timeout": 10, "prepare_threshold": None})
    return opciones


def es_https_publica(valor):
    try:
        url = urlsplit(valor)
        host = (url.hostname or "").lower().rstrip(".")
        if (url.scheme != "https" or not host or url.username is not None or url.password is not None
                or url.query or url.fragment or url.path not in ("", "/") or url.port not in (None, 443)):
            return False
        if host in ("localhost", "example.com", "example.org", "example.net") or host.endswith((".localhost", ".local", ".example", ".test", ".invalid")):
            return False
        try:
            return ip_address(host).is_global
        except ValueError:
            return bool(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+", host))
    except (ValueError, TypeError):
        return False


def validar_produccion(config):
    if config.get("GOALTIME_ENV") != "production":
        return
    if config.get("DEBUG") or config.get("TESTING"):
        raise ValueError("Producción no permite DEBUG ni TESTING")
    clave = config.get("JWT_SECRET_KEY", "")
    if not isinstance(clave, str) or len(clave) < 32 or clave.lower().startswith(("dev-", "cambiar", "test-", "reemplazar", "change", "your-")):
        raise ValueError("Producción requiere JWT_SECRET_KEY aleatoria de al menos 32 caracteres")
    url = make_url(config["SQLALCHEMY_DATABASE_URI"])
    if url.drivername != "postgresql+psycopg":
        raise ValueError("Producción requiere PostgreSQL con psycopg, no SQLite")
    if url.query.get("sslmode") not in ("require", "verify-ca", "verify-full"):
        raise ValueError("Producción requiere SSL en DATABASE_URL (sslmode=require o verify-full)")
    if not es_https_publica(config.get("APP_URL_BASE", "")):
        raise ValueError("APP_URL_BASE debe ser el origen HTTPS público de la API, sin /api")
    if config.get("PAGADORA") == "mock":
        if not config.get("ALLOW_MOCK_PAYMENTS"):
            raise ValueError("Pagos mock bloqueados en producción; para piloto sin cobros usa ALLOW_MOCK_PAYMENTS=1 explícitamente")
    elif config.get("PAGADORA") == "stripe":
        if not config.get("STRIPE_SECRET_KEY") or not config.get("STRIPE_WEBHOOK_SECRET"):
            raise ValueError("Stripe requiere sus claves en el servidor")
    else:
        raise ValueError("PAGADORA debe ser stripe o mock")

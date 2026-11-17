import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest
from sqlalchemy.exc import OperationalError

from app import create_app
from config import TestConfig
from deployment import es_https_publica, normalizar_database_url, opciones_motor, validar_produccion
from extensions import db
from models import Cliente

RAIZ = Path(__file__).resolve().parents[2]


def _config():
    return {"GOALTIME_ENV": "production", "DEBUG": False, "TESTING": False,
            "JWT_SECRET_KEY": "a" * 64,
            "SQLALCHEMY_DATABASE_URI": "postgresql+psycopg://user:secret@host/postgres?sslmode=require",
            "APP_URL_BASE": "https://goaltime.up.railway.app", "PAGADORA": "mock", "ALLOW_MOCK_PAYMENTS": True}


def test_configuracion_produccion_valida_sin_conectarse():
    validar_produccion(_config())


@pytest.mark.parametrize("campo,valor", [("DEBUG", True), ("TESTING", True),
    ("JWT_SECRET_KEY", "corta"), ("JWT_SECRET_KEY", "REEMPLAZAR_POR_UN_SECRETO_ALEATORIO_DE_64_CARACTERES"),
    ("SQLALCHEMY_DATABASE_URI", "sqlite:///goaltime.db"),
    ("SQLALCHEMY_DATABASE_URI", "postgresql+psycopg://user:secreto@host/db"),
    ("APP_URL_BASE", "http://localhost:5000"), ("APP_URL_BASE", "https://api.test"),
    ("ALLOW_MOCK_PAYMENTS", False), ("PAGADORA", "stripe")])
def test_produccion_rechaza_config_insegura_sin_filtrar_secretos(campo, valor):
    with pytest.raises(ValueError) as error:
        validar_produccion({**_config(), campo: valor})
    assert "user:secreto" not in str(error.value)
    assert "user:secret" not in str(error.value)


@pytest.mark.parametrize("esquema", ["postgres", "postgresql", "postgresql+psycopg"])
def test_supabase_url_usa_driver_instalado_y_conserva_password(esquema):
    url = normalizar_database_url(f"{esquema}://user:p%40ss%25word@host/postgres?sslmode=require")
    assert url.startswith("postgresql+psycopg://")
    from sqlalchemy.engine import make_url
    assert make_url(url).password == "p@ss%word"
    assert make_url(url).query["sslmode"] == "require"


def test_pool_pequeno_solo_para_postgresql():
    pg = opciones_motor("postgresql+psycopg://user:pass@host/db")
    assert pg["pool_size"] == 2 and pg["max_overflow"] == 0
    assert pg["connect_args"]["prepare_threshold"] is None
    assert "pool_size" not in opciones_motor("sqlite:///:memory:")


@pytest.mark.parametrize("url", ["http://api.up.railway.app", "https://localhost", "https://192.168.1.1",
    "https://127.0.0.1", "https://10.0.2.2", "https://api.local", "https://example.com",
    "https://api.up.railway.app/api", "https://user:secret@api.up.railway.app", "https://api.up.railway.app?q=1"])
def test_origen_https_no_admite_config_local(url):
    assert not es_https_publica(url)


def test_ready_comprueba_base_y_no_expone_excepciones(client, app, monkeypatch):
    assert client.get("/api/ready").status_code == 200
    def fallo():
        raise OperationalError("URL-con-password-secreta", {}, Exception("dato privado"))
    monkeypatch.setattr(db.engine, "connect", fallo)
    respuesta = client.get("/api/ready")
    assert respuesta.status_code == 503
    assert "password" not in respuesta.get_data(as_text=True)
    assert "privado" not in respuesta.get_data(as_text=True)


def test_ready_falla_sin_migraciones():
    app = create_app(TestConfig)
    assert app.test_client().get("/api/ready").status_code == 503
    with app.app_context():
        db.engine.dispose()


def test_cli_demo_bloqueada_en_produccion(app):
    app.config["GOALTIME_ENV"] = "production"
    for comando in ("seed", "preparar-demo"):
        respuesta = app.test_cli_runner().invoke(args=[comando])
        assert respuesta.exit_code != 0
    assert db.session.query(Cliente).count() == 0


def test_admin_se_crea_sin_password_visible_y_sin_promover_otra_cuenta(app, cliente):
    runner = app.test_cli_runner()
    password = "Una-clave-segura-123!"
    respuesta = runner.invoke(args=["crear-admin", "--nombre", "Admin Real", "--email", "admin@real.test"], input=f"{password}\n{password}\n")
    assert respuesta.exit_code == 0, respuesta.output
    assert password not in respuesta.output
    usuario = db.session.execute(db.select(Cliente).where(Cliente.email == "admin@real.test")).scalar_one()
    assert usuario.rol == "admin" and usuario.check_password(password)
    duplicado = runner.invoke(args=["crear-admin", "--nombre", "Admin Real", "--email", cliente.email], input=f"{password}\n{password}\n")
    assert duplicado.exit_code != 0
    assert db.session.get(Cliente, cliente.id).rol == "cliente"


def _modulo(ruta, nombre):
    spec = importlib.util.spec_from_file_location(nombre, ruta)
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


def test_rls_cubre_todas_las_tablas_y_sqlite_no_cambia(monkeypatch):
    modulo = _modulo(RAIZ / "backend/migrations/versions/0004_privacidad_postgres.py", "migracion_rls")
    assert set(db.metadata.tables) <= set(modulo.TABLAS)
    sentencias = []
    monkeypatch.setattr(modulo.op, "get_bind", lambda: SimpleNamespace(dialect=SimpleNamespace(name="postgresql")))
    monkeypatch.setattr(modulo.op, "execute", lambda sql: sentencias.append(str(sql)))
    modulo.upgrade()
    assert len(sentencias) == len(modulo.TABLAS)
    assert all("ENABLE ROW LEVEL SECURITY" in sql for sql in sentencias)
    sentencias.clear()
    monkeypatch.setattr(modulo.op, "get_bind", lambda: SimpleNamespace(dialect=SimpleNamespace(name="sqlite")))
    modulo.upgrade()
    assert sentencias == []


def test_compilacion_no_depende_de_dispositivo_y_exige_firma(tmp_path):
    modulo = _modulo(RAIZ / "tool/compilar_apk.py", "compilar_apk")
    assert modulo.validar_url("https://goaltime.up.railway.app/") == "https://goaltime.up.railway.app"
    for url in ("http://10.0.2.2:5000", "https://localhost", "https://api.test", "https://api.up.railway.app/api", "https://api.com&calc.exe"):
        with pytest.raises(ValueError):
            modulo.validar_url(url)
    with pytest.raises(ValueError, match="key.properties"):
        modulo.validar_firma(tmp_path)
    android = tmp_path / "android"
    android.mkdir()
    (android / "key.properties").write_text("storeFile=release.jks\nstorePassword=secreto\nkeyAlias=goaltime\nkeyPassword=secreto\n", encoding="utf-8")
    with pytest.raises(ValueError, match="keystore"):
        modulo.validar_firma(tmp_path)
    (android / "release.jks").write_bytes(b"test")
    modulo.validar_firma(tmp_path)

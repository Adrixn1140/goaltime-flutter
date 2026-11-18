"""Preflight antes de migrar la base remota o abrir Gunicorn."""

import sys

from config import Config
from deployment import validar_produccion


def main():
    try:
        validar_produccion({nombre: getattr(Config, nombre) for nombre in dir(Config) if nombre.isupper()})
    except ValueError as error:
        print(f"Configuración incompleta: {error}", file=sys.stderr)
        return 1
    print("Configuración de arranque validada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

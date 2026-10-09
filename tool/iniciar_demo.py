"""Arranque local portable: migraciones + seed + servidor, sin borrar datos."""

import importlib.util
from pathlib import Path
import subprocess
import sys


def main():
    backend = Path(__file__).resolve().parents[1] / "backend"
    if any(importlib.util.find_spec(modulo) is None for modulo in ("flask", "alembic", "flask_sqlalchemy")):
        print("Usa el Python del entorno virtual de backend e instala backend/requirements.txt.")
        return 1
    preparar = subprocess.run(
        [sys.executable, "-m", "flask", "--app", "app", "preparar-demo"], cwd=backend
    )
    if preparar.returncode:
        print("No se pudo preparar la base. El servidor no se iniciará.")
        return preparar.returncode
    print("Demo local en http://127.0.0.1:5000. Usa datos ficticios. Ctrl+C para detener.", flush=True)
    try:
        return subprocess.run(
            [sys.executable, "-m", "flask", "--app", "app", "run", "--host=0.0.0.0", "--port=5000"],
            cwd=backend,
        ).returncode
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())

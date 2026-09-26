# GoalTime API en contenedor (spec.md 7.3).
#
# 3.12 y no la 3.14 del venv local: es la versión con ruedas disponibles para todos los
# paquetes pinneados, y una imagen que se construye siempre vale más que una que depende
# de lo que se encuentre instalado en la máquina.

FROM python:3.12-slim

# `-p /var/lib/apt/lists/*` en el mismo RUN para no dejar el índice de apt en la capa.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv

# Las dependencias van en su propia capa: mientras requirements.txt no cambie, docker
# reutiliza la instalación y rebuildear el código no reinstala nada.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# El código se copia después y sin el .venv del desarrollo, que pesa más que la imagen.
COPY alembic.ini migrations/ ./
COPY . .

# Sin root: si el contenedor se compromete, el atacante ya no es root.
RUN useradd --create-home --uid 1000 goaltime \
    && chown -R goaltime:goaltime /srv
USER goaltime

EXPOSE 5000

# `alembic upgrade head` antes de arrancar es la diferencia entre esto y un despliegue que
# funciona en la máquina de quien lo probó: el esquema lo migra Alembic, no create_all().
# `flask seed-catalogo` siembra los catálogos que el dominio necesita para funcionar.
# `flask seed` (usuarios, canchas y horarios de prueba) no está en la línea de arranque a
# propósito: una instalación real no siembra cuentas de demostración.
CMD ["sh", "-c", "alembic upgrade head && flask seed-catalogo && gunicorn --bind 0.0.0.0:5000 --workers 2 --access-logfile - app:app"]

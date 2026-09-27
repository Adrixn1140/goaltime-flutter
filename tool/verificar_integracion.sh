#!/usr/bin/env bash
#
# Levanta el backend real y corre el contrato de la app contra él.
#
# `flutter test` a secas no habla con la red: los tests usan dobles (`test/support/fake_api.dart`)
# y el contrato real se salta sin `GOALTIME_API_URL`. Este script es el que junta las dos
# piezas: compose arriba, esquema migrado, catálogos sembrados, `/api/health` respondiendo y
# el contrato ejecutándose contra todo eso.
#
#   tool/verificar_integracion.sh              # levanta, corre y desmonta
#   tool/verificar_integracion.sh --keep       # deja los contenedores arriba
#   tool/verificar_integracion.sh --volumes    # además borra el volumen de Postgres
#
# Con `--volumes` el backend arranca desde una base vacía, que es la prueba de que
# `alembic upgrade head` y `flask seed-catalogo` bastan para tener un sistema que funciona.
set -euo pipefail

cd "$(dirname "$0")/.."

MANTENER=0
VOLUMENES=()
for arg in "$@"; do
  case "$arg" in
    --keep) MANTENER=1 ;;
    --volumes) VOLUMENES=("-v") ;;
    -h | --help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg" >&2
      exit 2
      ;;
  esac
done

# El API necesita el secreto de JWT y nadie lo tiene por defecto. Sin esto `docker compose up`
# falla con un error que habla de variables y no de qué hacer.
if [ ! -f .env ]; then
  if [ -f .env.compose.example ]; then
    cp .env.compose.example .env
    echo "==> Creé .env a partir de .env.compose.example (cambiá JWT_SECRET_KEY si esto sale de tu máquina)."
  else
    echo "Falta .env y no está .env.compose.example para copiar." >&2
    exit 1
  fi
fi

DC=(docker compose --env-file .env)

lavantar() {
  if [ ${#VOLUMENES[@]} -gt 0 ]; then
    echo "==> Bajando el stack y el volumen de Postgres (arranque en frío)"
  else
    echo "==> Bajando el stack (se conservan los datos)"
  fi
  "${DC[@]}" down "${VOLUMENES[@]}" >/dev/null 2>&1 || true
  echo "==> Levantando el backend"
  "${DC[@]}" up -d --build
}

limpiar() {
  if [ "$MANTENER" -eq 1 ]; then
    echo "==> Containers arriba (--keep). Para bajarlos: docker compose down"
  else
    echo "==> Bajando el stack"
    "${DC[@]}" down >/dev/null 2>&1 || true
  fi
}
trap limpiar EXIT

lavantar

# Esperar a que la API conteste. `/api/health` no toca la base, así que responde antes de que
# el esquema esté listo: por eso el seed va después y el contrato, más tarde todavía.
echo "==> Esperando a que la API responda"
LISTO=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 5 http://127.0.0.1:5000/api/health >/dev/null 2>&1; then
    LISTO=1
    break
  fi
  sleep 2
done
if [ "$LISTO" -ne 1 ]; then
  echo "La API no respondió a /api/health. Logs:" >&2
  docker compose logs api --tail 40 >&2
  exit 1
fi

echo "==> Semejando usuarios, canchas y horarios de prueba"
docker compose exec -T api flask seed >/dev/null

echo "==> Corriendo el contrato de la app contra el backend real"
GOALTIME_API_URL=http://127.0.0.1:5000 flutter test test/contrato_real_test.dart

echo
echo "Contrato verificado contra el backend real."

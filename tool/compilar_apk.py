"""APK release sin dispositivo. Requiere firma propia y una API pública ya preparada."""

import argparse
from ipaddress import ip_address
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import urlopen

RAIZ = Path(__file__).resolve().parents[1]


def validar_url(valor):
    try:
        url = urlsplit(valor)
        host = (url.hostname or "").lower().rstrip(".")
        if (url.scheme != "https" or not host or url.username is not None or url.password is not None
                or url.path not in ("", "/") or url.query or url.fragment or url.port not in (None, 443)):
            raise ValueError()
        if host in ("localhost", "example.com", "example.org", "example.net") or host.endswith((".localhost", ".local", ".test", ".example", ".invalid")):
            raise ValueError()
        try:
            direccion = ip_address(host)
        except ValueError:
            if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+", host):
                raise ValueError()
        else:
            # Se exige un dominio para el certificado y la distribución Android.
            raise ValueError()
        return valor.rstrip("/")
    except (TypeError, ValueError):
        raise ValueError("Usa el origen HTTPS real de Railway, sin /api, IP local ni claves") from None


def validar_firma(raiz):
    archivo = raiz / "android" / "key.properties"
    if not archivo.is_file():
        raise ValueError("Falta android/key.properties. Crea y respalda tu firma según docs/PRODUCCION.md")
    props = {}
    for linea in archivo.read_text(encoding="utf-8").splitlines():
        if linea.strip() and not linea.lstrip().startswith(("#", "!")) and "=" in linea:
            k, v = linea.split("=", 1)
            props[k.strip()] = v.strip()
    if not all(props.get(k) for k in ("storeFile", "storePassword", "keyAlias", "keyPassword")):
        raise ValueError("key.properties requiere storeFile, storePassword, keyAlias y keyPassword")
    if not (raiz / "android" / props["storeFile"]).is_file():
        raise ValueError("No existe el keystore. Usa una ruta con / en key.properties y no reemplaces una firma existente")


def comprobar_api(origen):
    try:
        with urlopen(origen + "/api/ready", timeout=30) as respuesta:
            # Solo endpoints propios; no construir contra un HTML de error o un login.
            destino = urlsplit(respuesta.url)
            if destino.scheme != "https" or destino.netloc != urlsplit(origen).netloc:
                raise ValueError("La comprobación redirigió fuera de la API HTTPS esperada")
            cuerpo = json.loads(respuesta.read(16384))
            if cuerpo.get("estado") != "ok" or cuerpo.get("servicio") != "goaltime-api":
                raise ValueError("La API no devolvió una comprobación de preparación válida")
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError, AttributeError):
        raise ValueError("La API no está lista. Revisa /api/ready, variables y logs de Railway antes de compilar") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", required=True, help="Origen HTTPS público de Railway, sin /api")
    parser.add_argument("--split-per-abi", action="store_true", help="APKs separados y más pequeños por arquitectura")
    args = parser.parse_args()
    try:
        origen = validar_url(args.api_url)
        validar_firma(RAIZ)
        flutter = shutil.which("flutter")
        if not flutter:
            raise ValueError("Flutter no está en PATH")
        comprobar_api(origen)
    except ValueError as error:
        print(f"No se compiló: {error}", file=sys.stderr)
        return 1
    comando = [flutter, "build", "apk", "--release", f"--dart-define=API_BASE_URL={origen}"]
    if args.split_per_abi:
        comando.append("--split-per-abi")
    print("API preparada y firma encontrada. Compilando sin teléfono conectado…", flush=True)
    resultado = subprocess.run(comando, cwd=RAIZ)
    if resultado.returncode == 0:
        print("APK generado en build/app/outputs/flutter-apk/. Prueba la instalación y las funciones con datos móviles.")
    return resultado.returncode


if __name__ == "__main__":
    raise SystemExit(main())

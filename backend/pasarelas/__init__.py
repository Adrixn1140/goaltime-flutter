"""Selección de la pasarela de pago según `PAGADORA`.

`stripe_pasarela` sólo se importa cuando corresponde, de modo que los tests y la
demostración funcionan sin el SDK de Stripe instalado ni claves configuradas.
"""

from flask import current_app

from pasarelas.base import PasarelaPago
from pasarelas.mock_pasarela import MockPasarela

_cache: dict[tuple, PasarelaPago] = {}


def obtener_pasarela(config=None) -> PasarelaPago:
    config = config or current_app.config
    nombre = config.get("PAGADORA", "mock").lower()
    clave = (
        nombre,
        config.get("STRIPE_SECRET_KEY"),
        config.get("STRIPE_WEBHOOK_SECRET"),
        config.get("STRIPE_CURRENCY"),
        config.get("APP_URL_BASE"),
    )
    if clave in _cache:
        return _cache[clave]

    if nombre == "mock":
        pasarela: PasarelaPago = MockPasarela(config.get("APP_URL_BASE", "http://localhost:5000"))
    elif nombre == "stripe":
        from pasarelas.stripe_pasarela import StripePasarela

        pasarela = StripePasarela(
            secret_key=config.get("STRIPE_SECRET_KEY", ""),
            webhook_secret=config.get("STRIPE_WEBHOOK_SECRET", ""),
            moneda=config.get("STRIPE_CURRENCY", "cop"),
        )
    else:
        raise RuntimeError(f"PAGADORA desconocida: {nombre!r}. Usa 'mock' o 'stripe'.")

    _cache[clave] = pasarela
    return pasarela

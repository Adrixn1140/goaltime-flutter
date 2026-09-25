"""Pasarela real: Stripe Checkout (modo test en desarrollo).

Reglas de seguridad aplicadas aquí, no en el blueprint:

1. El cuerpo del webhook **nunca** se parsea antes de verificar la firma
   (`stripe.Webhook.construct_event`), y la tolerancia por defecto es de 5 minutos.
2. El pago se identifica por `metadata.pago_id`, que fija el backend al crear la sesión;
   el `cliente_email` que reporta Stripe no se usa para nada.
3. El monto lo calcula el backend (`horario.tarifa`) y se envía en la sesión; el webhook
   no puede alterarlo.
"""

import stripe

try:  # stripe >= 12 retiró el módulo público `stripe.error`
    from stripe.error import SignatureVerificationError
except ImportError:  # pragma: no cover - depende de la versión del SDK
    from stripe._webhook import SignatureVerificationError

from pasarelas.base import (
    TIPO_APROBADO,
    TIPO_RECHAZADO,
    DatosCheckout,
    EventoDesconocido,
    EventoPago,
    FirmaInvalida,
    PasarelaPago,
)

EVENTO_APROBADO = "checkout.session.completed"
EVENTOS_RECHAZADOS = ("checkout.session.expired", "payment_intent.payment_failed")


class StripePasarela(PasarelaPago):
    metodo = "stripe"

    def __init__(self, secret_key, webhook_secret, moneda="cop"):
        if not secret_key:
            raise RuntimeError(
                "Falta STRIPE_SECRET_KEY. Configura PAGADORA=mock para desarrollo sin claves."
            )
        stripe.api_key = secret_key
        self.webhook_secret = webhook_secret
        self.moneda = moneda

    def crear_checkout(self, datos: DatosCheckout):
        session = stripe.checkout.Session.create(
            mode="payment",
            customer_email=datos.correo,
            line_items=[
                {
                    "quantity": 1,
                    "price_data": {
                        "currency": datos.moneda,
                        # Stripe trabaja en la unidad mínima de la moneda: pesos sin decimales.
                        "unit_amount": int(round(datos.monto)),
                        "product_data": {"name": datos.descripcion},
                    },
                }
            ],
            metadata={"pago_id": str(datos.pago_id)},
            success_url=datos.url_exito,
            cancel_url=datos.url_cancelacion,
        )
        return session.url

    def verificar_evento(self, cuerpo, cabeceras):
        firma = cabeceras.get("Stripe-Signature")
        if not firma or not self.webhook_secret:
            raise FirmaInvalida("Falta la cabecera Stripe-Signature o el secreto configurado")
        try:
            evento = stripe.Webhook.construct_event(cuerpo, firma, self.webhook_secret)
        except SignatureVerificationError as exc:
            raise FirmaInvalida("Firma del webhook no válida") from exc
        except ValueError as exc:
            raise FirmaInvalida("Cuerpo del webhook ilegible") from exc

        tipo_evento = evento["type"]
        objeto = evento["data"]["object"]
        # `construct_event` devuelve un `StripeObject`, no un dict: se accede por índice
        # y con `.to_dict()`, porque `.get()` y la iteración están bloqueadas a propósito
        # por el SDK para no confundir un recurso con un diccionario.
        metadatos = objeto.to_dict().get("metadata") if "metadata" in objeto else None
        pago_id = (metadatos or {}).get("pago_id")
        if pago_id is None:
            raise EventoDesconocido("El evento no trae metadata.pago_id")
        try:
            pago_id = int(pago_id)
        except (TypeError, ValueError) as exc:
            raise EventoDesconocido("metadata.pago_id no es un identificador válido") from exc

        if tipo_evento == EVENTO_APROBADO:
            tipo = TIPO_APROBADO
        elif tipo_evento in EVENTOS_RECHAZADOS:
            tipo = TIPO_RECHAZADO
        else:
            # Evento auténtico que no nos interesa: se ignora sin error.
            return None

        return EventoPago(
            tipo=tipo,
            referencia=objeto["id"],
            id_evento=evento["id"],
            pago_id=pago_id,
        )

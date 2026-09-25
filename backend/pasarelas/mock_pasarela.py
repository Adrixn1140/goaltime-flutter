"""Pasarela simulada: permite tests y demostraciones sin claves de Stripe.

`crear_checkout` devuelve una URL ilustrativa (no hay página real que abrir) y el flujo
se cierra con `POST /api/pagos/{id}/simular`, que atraviesa la misma lógica de
confirmación que el webhook de Stripe. `verificar_evento` no se usa —una pasarela
simulada no recibe webhooks—, pero la interfaz lo exige, así que rechaza la llamada.
"""

from pasarelas.base import (
    TIPO_APROBADO,
    TIPO_RECHAZADO,
    DatosCheckout,
    EventoDesconocido,
    EventoPago,
    FirmaInvalida,
    PasarelaPago,
)


class MockPasarela(PasarelaPago):
    metodo = "mock"

    def __init__(self, url_base):
        self.url_base = url_base.rstrip("/")

    def crear_checkout(self, datos: DatosCheckout):
        return f"{self.url_base}/checkout/simulado/{datos.pago_id}?monto={datos.monto:.0f}"

    def evento(self, pago_id, resultado, referencia=None):
        """Construye el evento que produciría la pasarela real (usado por `/simular`).

        Se construye aquí y no en el blueprint para que la demostración y los tests
        ejerciten el mismo recorrido de datos que el webhook: sólo cambia quién lo
        produce, no quién lo interpreta.
        """
        if resultado not in (TIPO_APROBADO, TIPO_RECHAZADO):
            raise EventoDesconocido(f"Resultado desconocido: {resultado}")
        return EventoPago(
            tipo=resultado,
            referencia=referencia or f"mock_{pago_id}",
            id_evento=f"mock_evt_{pago_id}",
            pago_id=pago_id,
        )

    def verificar_evento(self, cuerpo, cabeceras):
        raise FirmaInvalida("La pasarela simulada no recibe webhooks")

"""Interfaz de pasarela de pago.

El resto de la API no sabe si el pago lo procesa Stripe o la pasarela simulada: sólo
conoce `crear_checkout` y `verificar_evento`. Añadir Wompi, PayU o ePayco en el futuro
es escribir un módulo nuevo con estas dos operaciones.
"""

from abc import ABC, abstractmethod
from collections.abc import Mapping
from dataclasses import dataclass

#: Resultado de un evento de pago, en el vocabulario del catálogo `estado_pago`.
TIPO_APROBADO = "aprobado"
TIPO_RECHAZADO = "rechazado"


class FirmaInvalida(Exception):
    """La firma del webhook no es válida o el evento está fuera de la ventana temporal."""


class EventoDesconocido(Exception):
    """El evento es auténtico pero no corresponde a ningún pago conocido."""


@dataclass(frozen=True)
class EventoPago:
    """Evento ya verificado, listo para aplicarse a un `Pago`."""

    tipo: str  # TIPO_APROBADO | TIPO_RECHAZADO
    referencia: str | None = None  # identificador de la sesión en la pasarela
    id_evento: str | None = None
    pago_id: int | None = None  # lo fija el backend en `metadata.pago_id`


@dataclass(frozen=True)
class DatosCheckout:
    """Lo que el backend necesita para abrir una sesión de pago.

    El monto y la descripción los calcula el backend, nunca la app.
    """

    pago_id: int
    monto: float
    moneda: str
    descripcion: str
    correo: str
    url_exito: str
    url_cancelacion: str


class PasarelaPago(ABC):
    """Contrato mínimo de una pasarela."""

    #: código del catálogo `metodo_pago` que se guarda en `pago.metodo`
    metodo: str

    @abstractmethod
    def crear_checkout(self, datos: DatosCheckout) -> str:
        """Devuelve la URL a la que la app debe enviar al usuario."""

    @abstractmethod
    def verificar_evento(self, cuerpo: bytes, cabeceras: Mapping[str, str]) -> EventoPago:
        """Valida la autenticidad del webhook y lo traduce a `EventoPago`."""

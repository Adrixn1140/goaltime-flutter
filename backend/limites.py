"""Topes de longitud de los textos, leídos de las columnas (spec.md 7.6).

Cada constante sale de la columna, no de un número escrito a mano. La razón es concreta
y la encontró PostgreSQL: `Cliente.email` es `varchar(180)` y la validación de `register`
no comprobaba su longitud, así que un email largo terminaba en la base. En SQLite —que
ignora los `varchar(n)`— se guardaba sin quejarse y la API respondía `201`; en PostgreSQL
la misma petición devolvía `500` con `value too long for type varchar(180)` en el log.

Un tope validado devuelve `400` con el número, que es lo que la app sabe mostrar. Y al
leerlo de la columna, cambiar `String(120)` a `String(200)` no deja un `120` olvidado en
un blueprint: la validación se mueve con ella.
"""

from models import Cancha, Cliente, Horario

NOMBRE = Cliente.__table__.c.nombre.type.length
EMAIL = Cliente.__table__.c.email.type.length
UBICACION = Cancha.__table__.c.ubicacion.type.length
FOTO = Cancha.__table__.c.foto.type.length

#: Tope de `Numeric(10, 2)`: 10^(10-2) - 10^-2. PostgreSQL lanza `numeric field overflow` si
#: se pasa, y devuelve 500; SQLite guarda el valor sin rechistar. El mismo motivo que los
#: `varchar(n)`, y también encontrado levantando el backend contra PostgreSQL.
_tarifa = Horario.__table__.c.tarifa.type
TARIFA_MAXIMA = 10 ** (_tarifa.precision - _tarifa.scale) - 1 / 10**_tarifa.scale

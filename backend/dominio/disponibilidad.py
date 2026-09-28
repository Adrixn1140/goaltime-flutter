"""Reglas de disponibilidad, sin HTTP (spec.md 3.2 y 3.6).

Existe porque la lógica de slots la necesitan dos callers con perfiles distintos:

- `GET /api/disponibilidad`, que devuelve **todos** los slots de la ventana, ocupados y
  libres, para que la app pueda deshabilitar con un motivo (HEUR-5).
- El asistente de lenguaje natural (spec.md 3.6), que sólo quiere **sugerencias
  reservables**, o sea los `disponible=True` de una franja concreta.

Antes de este módulo esa lógica vivía dentro del blueprint `disponibilidad`, y el
blueprint tenía que importarla desde allí: `reservas.py` sacaba `parse_fecha` y
`slot_vencido` de otro blueprint. Eso es una dependencia en dirección equivocada —un
endpoint que usa las reglas de otro endpoint—, y obliga a que lo que es una regla de
negocio muda se mantenga importable desde la capa HTTP. Aquí vive lo que es regla, y los
blueprints quedan como la capa fina que traduce HTTP.

La regla en sí no cambia: extraerla es para que haya un solo lugar donde viva, no una
oportunidad de redefinirla. Los 36 tests de `tests/test_disponibilidad.py` cubren el
comportamiento anterior y siguen pasando sin modificarse.
"""

import re
from datetime import date, datetime, timedelta

from dominio.errores import DominioInvalido, FranjaInvalida
from extensions import db
from models import ESTADO_CANCELADA, Cancha, Horario, Reserva

#: La ventana de spec.md 3.2 es de 6 días contados desde `fecha_inicio`, no un calendario.
DIAS_VENTANA = 6

FORMATO_FECHA = "%Y-%m-%d"
FORMATO_HORA = "%H:%M"

#: Estrictos a propósito. Un `strptime` por sí solo acepta `2026-9-4`, y la app debe poder
#: fiarse de que recibe siempre el mismo formato.
PATRON_FECHA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
PATRON_HORA = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")

MOTIVO_OCUPADO = "ocupado"
MOTIVO_TRANSCURRIDO = "transcurrido"

#: Límites de franja del asistente (spec.md 3.6). **Definidos aquí porque §3.2 no los
#: define**: la spec llama a `franja` un "filtro de §3.2" y §3.2 no tiene ninguno, así que
#: las fronteras hay que decidirlas en algún sitio, y este es el sitio. Son las
#: convencionales de una cancha y se documentan para que quien las cambie sepa que el
#: asistente cambia con ellas.
#:
#: El criterio es la **hora de inicio** del slot, y las fronteras son medias: una franja
#: que se solapara con la siguiente haría que las 12:00 cumplieran dos, y un slot no puede
#: estar en dos sitios a la vez.
FRANJA_MAÑANA = "mañana"
FRANJA_TARDE = "tarde"
FRANJA_NOCHE = "noche"
FRANJA_CUALQUIERA = "cualquiera"

FRANJAS = (FRANJA_MAÑANA, FRANJA_TARDE, FRANJA_NOCHE, FRANJA_CUALQUIERA)

_HORA_LIMITE_MAÑANA = 6
_HORA_LIMITE_TARDE = 12
_HORA_LIMITE_NOCHE = 18


def parse_fecha(texto):
    """Devuelve `date` o `None` si el texto no es una fecha ISO válida.

    El formato es estricto (`YYYY-MM-DD`): `strptime` por sí solo acepta `2026-9-4`
    y la app debe poder fiarse de que recibe siempre el mismo formato.
    """
    if not isinstance(texto, str) or not PATRON_FECHA.match(texto):
        return None
    try:
        return datetime.strptime(texto, FORMATO_FECHA).date()
    except ValueError:
        return None


def slot_vencido(fecha, hora_inicio, ahora=None):
    """True si el slot ya no es seleccionable por hora: fecha pasada, o la hora de
    inicio del día en curso ya pasó."""
    ahora = ahora or datetime.now()
    if fecha < ahora.date():
        return True
    return fecha == ahora.date() and hora_inicio <= ahora.time()


def parse_hora(texto):
    """Devuelve un `time` o `None` si el texto no es una hora `HH:MM` válida.

    Comparte la forma estricta de `parse_fecha` porque la usa la gestión del dueño
    (§3.4): un `int` como `8` o un `8:00` se rechazarían en la base pero pasarían un
    `strptime` mal usado, y el dueño vería el error a la hora de reservar, no al crear
    el horario.
    """
    if not isinstance(texto, str) or not PATRON_HORA.match(texto):
        return None
    try:
        return datetime.strptime(texto, FORMATO_HORA).time()
    except ValueError:
        return None


def en_franja(hora_inicio, franja):
    """True si la hora de inicio del slot cae en la franja.

    `cualquiera` incluye todo, y es el valor por omisión: el asistente usa `cualquiera`
    cuando la persona no dijo hora, que es el caso más común.
    """
    if franja == FRANJA_CUALQUIERA:
        return True
    hora = hora_inicio.hour
    if franja == FRANJA_MAÑANA:
        return _HORA_LIMITE_MAÑANA <= hora < _HORA_LIMITE_TARDE
    if franja == FRANJA_TARDE:
        return _HORA_LIMITE_TARDE <= hora < _HORA_LIMITE_NOCHE
    if franja == FRANJA_NOCHE:
        return hora >= _HORA_LIMITE_NOCHE
    raise FranjaInvalida(f"Franja desconocida: {franja!r}. Usa una de: {', '.join(FRANJAS)}.")


def resolver_cancha_por_id(cancha_id):
    """Cancha activa con ese id, o `None`.

    Devuelve `None` para "no existe" y para "existe pero está desactivada" a propósito:
    el endpoint responde el mismo `404` en ambos casos, y en el catálogo de un cliente
    una cancha desactivada no debe ser adivinable.
    """
    try:
        cancha_id = int(cancha_id)
    except (TypeError, ValueError):
        return None
    cancha = db.session.get(Cancha, cancha_id)
    if cancha is None or not cancha.activo:
        return None
    return cancha


def resolver_cancha_por_nombre(texto):
    """Cancha activa cuyo nombre coincide con `texto`, o `None`.

    El asistente recibe **texto**, no un id (spec.md 3.6): el modelo no conoce
    identificadores, y pedirle uno lo invitaría a inventarlo. Que lo resuelva el backend
    es lo que hace que una sugerencia sea real y no una alucinación con forma de cita.

    La coincidencia es por subcadena, sin distinguir mayúsculas ni acentos, para que
    "palmeras" encuentre "Las Palmeras". Ante varias coincidencias gana la más corta por
    nombre: es la más específica, y devolver una lista para que el modelo elija metería
    una decisión más en su tablero.

    `None` no es un error 404 aquí: es una respuesta legítima que el modelo va a redactar
    como "no encontré esa cancha", que es justo el comportamiento que se busca cuando el
    usuario nombra mal una cancha.
    """
    if not isinstance(texto, str) or not texto.strip():
        return None

    consulta = db.select(Cancha).where(Cancha.activo.is_(True)).order_by(Cancha.nombre)
    candidatos = [c for c in db.session.execute(consulta).scalars() if _coincide(c.nombre, texto)]
    if not candidatos:
        return None
    return min(candidatos, key=lambda c: (len(c.nombre), c.id))


def _coincide(nombre, texto):
    """Subcadena sin distinguir mayúsculas, minúsculas ni acentos."""
    return _sin_acentos(texto.strip().lower()) in _sin_acentos(nombre.lower())


def _sin_acentos(texto):
    """Quita diacríticos con el decomposition Unicode, sin el `unidecode` de terceros.

    `unicodedata.normalize` deja la `ñ` como un solo carácter (`n`), que es lo que se
    quiere aquí: "pinon" encuentra "Piñón" y "manana" encuentra "Mañana".
    """
    import unicodedata as ud

    return "".join(c for c in ud.normalize("NFD", texto) if not ud.combining(c))


def calcular_slots(cancha, fecha_inicio, franja=FRANJA_CUALQUIERA, ahora=None):
    """Slots de la ventana de 6 días que empiezan en `fecha_inicio`, para una cancha.

    Devuelve **todos** los slots, ocupados y libres, en orden de fecha y hora. Cada uno
    lleva su `motivo` cuando no es seleccionable, que es lo que permite a la app
    deshabilitarlo con un motivo en vez de dejar que el usuario descubra el `409` al
    reservar (HEUR-5).

    `cancha` viene ya resuelta: el endpoint lo resuelve por id y el asistente por nombre,
    y ninguno de los dos callers debería repetir el filtro de `activo`.

    `franja` es el añadido del asistente (spec.md 3.6) y filtra por hora de inicio. El
    endpoint de §3.2 siempre pasa `cualquiera` y por eso su comportamiento no cambia: los
    36 tests de disponibilidad siguen pasando porque el filtro es identidad para ese
    valor.
    """
    if franja not in FRANJAS:
        raise FranjaInvalida(f"Franja desconocida: {franja!r}. Usa una de: {', '.join(FRANJAS)}.")

    fechas = [fecha_inicio + timedelta(days=dias) for dias in range(DIAS_VENTANA)]

    horarios = db.session.execute(
        db.select(Horario)
        .where(Horario.cancha_id == cancha.id, Horario.dia.in_({f.weekday() for f in fechas}))
        .order_by(Horario.hora_inicio)
    ).scalars().all()

    if not horarios:
        return []

    # Una reserva cancelada libera el slot, así que no cuenta como ocupada.
    ocupados = {
        (horario_id, fecha)
        for horario_id, fecha in db.session.execute(
            db.select(Reserva.horario_id, Reserva.fecha).where(
                Reserva.cancha_id == cancha.id,
                Reserva.fecha.in_(fechas),
                Reserva.estado != ESTADO_CANCELADA,
            )
        ).all()
    }

    ahora = ahora or datetime.now()
    slots = []
    for fecha in fechas:
        for horario in horarios:
            if horario.dia != fecha.weekday():
                continue
            if not en_franja(horario.hora_inicio, franja):
                continue
            if (horario.id, fecha) in ocupados:
                slots.append(_slot(horario, fecha, False, MOTIVO_OCUPADO))
            elif slot_vencido(fecha, horario.hora_inicio, ahora):
                slots.append(_slot(horario, fecha, False, MOTIVO_TRANSCURRIDO))
            else:
                slots.append(_slot(horario, fecha, True, None))

    return slots


def slots_reservables(cancha, fecha_inicio, franja=FRANJA_CUALQUIERA, ahora=None, limite=3):
    """Los slots que de verdad se pueden reservar, como sugerencias del asistente.

    Es `calcular_slots` filtrado por `disponible`, que es la diferencia entre lo que el
    endpoint de §3.2 muestra y lo que el asistente puede proponer: sugerir un slot ocupado
    es peor que no sugerir nada.

    `limite` acota cuántos vuelven al modelo. Un catálogo de 300 slots libres es contexto
    que no cambia la redacción y sí encarece la llamada; tres son suficientes para que la
    respuesta diga "hay" y ofrezca opciones.
    """
    slots = calcular_slots(cancha, fecha_inicio, franja=franja, ahora=ahora)
    libres = [s for s in slots if s["disponible"]]
    return libres[:limite] if limite is not None else libres


def ventana_de_fechas(fecha_inicio):
    """Las 6 fechas de la ventana, para mensajes de error y de ayuda al modelo."""
    return [fecha_inicio + timedelta(days=dias) for dias in range(DIAS_VENTANA)]


def fecha_en_ventana(texto, hoy=None):
    """La fecha que pidió el modelo, o `DominioInvalido` si no es una fecha usable.

    A diferencia de `parse_fecha`, esto **lanza** en vez de devolver `None`. La diferencia
    es quién decide qué hacer con el fallo: `GET /api/disponibilidad` lo tradujo a un 400
    porque el dato venía de un query param que el usuario escribió; aquí viene de una
    decisión del modelo, y para ese caso hay una regla distinta: una fecha que no existe
    no es "no hay disponibilidad", es una decisión inválida que hay que reportar como
    `422`. La spec lo pide así en la tabla de errores de §3.6.
    """
    fecha = parse_fecha(texto)
    if fecha is None:
        raise DominioInvalido(f"La fecha {texto!r} no tiene el formato YYYY-MM-DD.")
    hoy = hoy or date.today()
    if not hoy <= fecha < hoy + timedelta(days=DIAS_VENTANA):
        ventana = ventana_de_fechas(hoy)
        raise DominioInvalido(
            f"La fecha {fecha.isoformat()} está fuera de la ventana de {DIAS_VENTANA} días. "
            f"Las fechas válidas son de {ventana[0].isoformat()} a {ventana[-1].isoformat()}."
        )
    return fecha


def _slot(horario, fecha, disponible, motivo):
    return {
        "horario_id": horario.id,
        "fecha": fecha.isoformat(),
        "hora_inicio": horario.hora_inicio.strftime(FORMATO_HORA),
        "hora_fin": horario.hora_fin.strftime(FORMATO_HORA),
        "tarifa": float(horario.tarifa),
        "disponible": disponible,
        "motivo": motivo,
    }

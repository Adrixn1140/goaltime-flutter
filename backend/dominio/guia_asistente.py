"""Ayuda determinista y consultas locales, sin enviar datos personales a un LLM."""

import re
import unicodedata

from dominio.arbitros import perfiles_publicados
from extensions import db
from models import Equipo


def orientar(mensaje, usuario_id):
    texto = "".join(c for c in unicodedata.normalize("NFD", mensaje.lower()) if unicodedata.category(c) != "Mn")
    if re.search(r"\b(arbitro\w*|arbitraje|silbato)\b", texto):
        accion = [{"destino": "arbitros", "etiqueta": "Ver árbitros"}]
        if re.search(r"\b(public\w*|registr\w*|perfil|ofrecer|cuenta)\b|\b(ser|soy)\s+arbitro", texto):
            return ("Para ofrecer tus servicios, cierra sesión y elige Árbitro al registrarte. "
                    "Completa Mi perfil arbitral con ciudad, contacto, experiencia y tarifa COP por partido. "
                    "Activa Publicar perfil solo si autorizas mostrar esos datos. Puedes ocultarlo cuando quieras. "
                    "Disponible no garantiza agenda; aún no hay contratación ni pagos de árbitros.", accion)
        ciudad = re.search(r"\ben\s+([\wáéíóúñü\s-]+)", mensaje, re.IGNORECASE)
        q = ciudad.group(1).strip(" ?.! ")[:100] if ciudad else ""
        disponible = True if "disponible" in texto else None
        if "no disponible" in texto:
            disponible = False
        perfiles = db.session.execute(perfiles_publicados(q, disponible).limit(5)).scalars().all()
        if not perfiles:
            return ("No encontré árbitros publicados que coincidan con tu búsqueda. "
                    "Prueba otra ciudad o desactiva Solo disponibles en el directorio. No inventaré perfiles ni tarifas.", accion)
        lineas = [f"• {p.usuario.nombre} · {p.ciudad} · ${p.tarifa:,.2f} COP/partido · "
                  f"{'Disponible' if p.disponible else 'No disponible'}" for p in perfiles]
        return ("Estos son hasta 5 perfiles publicados, ordenados por tarifa:\n" + "\n".join(lineas) +
                "\nTarifas orientativas; consulta contacto y disponibilidad con el árbitro. No he contratado a nadie.", accion)
    if re.search(r"\b(equipo\w*|jugador\w*|miembro\w*|plantilla\w*)\b", texto):
        accion = [{"destino": "equipos", "etiqueta": "Ir a mis equipos"}]
        if re.search(r"\b(mis|cuantos|mostrar|ver|lista|tengo)\b", texto) and not re.search(r"\b(como|anadir|agregar|crear|editar|eliminar)\b", texto):
            equipos = db.session.execute(db.select(Equipo).where(Equipo.cliente_id == usuario_id).order_by(Equipo.id.desc())).scalars().all()
            if not equipos:
                return ("Todavía no tienes equipos. En Equipos pulsa Crear equipo y luego Añadir jugador.", accion)
            resumen = "; ".join(f"{e.nombre}: {len(e.jugadores)} jugadores" for e in equipos[:10])
            return (f"Tienes {len(equipos)} equipos. {resumen}. "
                    "Abre la plantilla para gestionarla; no mostraré documentos ni celulares en el chat.", accion)
        return ("En Equipos pulsa Crear equipo, escribe su nombre y abre la plantilla. Añadir jugador pide "
                "nombre, apellido, documento (5–20 dígitos) y celular (10–15 dígitos). "
                "Puedes editar o retirar jugadores y renombrar o eliminar el equipo con confirmación. "
                "No se repite un documento dentro del mismo equipo. No hay invitaciones de cuentas ni torneos todavía; "
                "solo tú administras tus plantillas. No he modificado ningún dato.", accion)
    if re.search(r"\b(ayuda|funciones|puedes|torneo\w*)\b", texto):
        return ("Puedo buscar canchas libres, orientarte para gestionar equipos y consultar árbitros publicados "
                "con sus tarifas. Prueba: 'mis equipos', 'cómo añadir jugadores' o 'árbitros disponibles en Riohacha'. "
                "No creo plantillas, no contrato árbitros ni organizo torneos automáticamente. Cada consulta es independiente.",
                [{"destino": "equipos", "etiqueta": "Mis equipos"}, {"destino": "arbitros", "etiqueta": "Árbitros"}])
    return None

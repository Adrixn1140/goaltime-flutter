"""Cierra acceso directo por Data API; la aplicación usa exclusivamente Flask."""

from alembic import op

revision = "p4b1117privacidad"
down_revision = "a3b1030arbitros"
branch_labels = None
depends_on = None

TABLAS = ("maestra", "cliente", "equipo", "jugador", "perfil_arbitro", "cancha", "horario", "reserva", "pago", "alembic_version")


def upgrade():
    if op.get_bind().dialect.name == "postgresql":
        for tabla in TABLAS:
            op.execute(f'ALTER TABLE "{tabla}" ENABLE ROW LEVEL SECURITY')


def downgrade():
    # No se vuelve a exponer información privada al retroceder la versión.
    pass

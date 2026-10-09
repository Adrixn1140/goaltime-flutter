"""Equipos y jugadores: avance demostrativo hacia torneos."""

from alembic import op
import sqlalchemy as sa

revision = "e2a91009equipos"
down_revision = "086fbc434d9a"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("equipo",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("nombre", sa.String(80), nullable=False),
        sa.Column("cliente_id", sa.Integer(), sa.ForeignKey("cliente.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("creado_en", sa.DateTime(), server_default=sa.func.now(), nullable=False))
    op.create_index("ix_equipo_cliente_id", "equipo", ["cliente_id"])
    op.create_table("jugador",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("equipo_id", sa.Integer(), sa.ForeignKey("equipo.id", ondelete="CASCADE"), nullable=False),
        sa.Column("nombre", sa.String(80), nullable=False),
        sa.Column("apellido", sa.String(80), nullable=False),
        sa.Column("documento", sa.String(20), nullable=False),
        sa.Column("celular", sa.String(15), nullable=False),
        sa.UniqueConstraint("equipo_id", "documento", name="uq_jugador_equipo_documento"))
    op.create_index("ix_jugador_equipo_id", "jugador", ["equipo_id"])


def downgrade():
    op.drop_table("jugador")
    op.drop_table("equipo")

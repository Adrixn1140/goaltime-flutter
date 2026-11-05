"""Rol y perfiles arbitrales, sin publicar cuentas automáticamente."""

from alembic import op
import sqlalchemy as sa

revision = "a3b1030arbitros"
down_revision = "e2a91009equipos"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "perfil_arbitro",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("cliente_id", sa.Integer(), sa.ForeignKey("cliente.id", ondelete="RESTRICT"), nullable=False, unique=True),
        sa.Column("ciudad", sa.String(100), nullable=False),
        sa.Column("celular", sa.String(15), nullable=False),
        sa.Column("experiencia", sa.Integer(), nullable=False),
        sa.Column("biografia", sa.String(500), nullable=False),
        sa.Column("tarifa", sa.Numeric(10, 2), nullable=False),
        sa.Column("disponible", sa.Boolean(), nullable=False),
        sa.Column("publicado", sa.Boolean(), nullable=False),
        sa.CheckConstraint("tarifa > 0 AND tarifa <= 10000000", name="ck_arbitro_tarifa"),
        sa.CheckConstraint("experiencia >= 0 AND experiencia <= 60", name="ck_arbitro_experiencia"),
    )
    # También actualiza instalaciones existentes: no exige volver a sembrar datos.
    tabla = sa.table("maestra", sa.column("tipo", sa.String), sa.column("codigo", sa.String), sa.column("valor", sa.String))
    conexion = op.get_bind()
    existe = conexion.execute(sa.select(tabla.c.codigo).where(tabla.c.tipo == "rol", tabla.c.codigo == "arbitro")).first()
    if not existe:
        conexion.execute(tabla.insert().values(tipo="rol", codigo="arbitro", valor="Árbitro"))


def downgrade():
    # El rol se conserva: puede haber cuentas que lo referencian.
    op.drop_table("perfil_arbitro")

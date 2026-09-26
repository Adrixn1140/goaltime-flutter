"""esquema inicial

El esquema completo del dominio (spec.md 2 y 7.1), revisado a mano sobre lo que generó
Alembic contra una PostgreSQL vacía. La revisión encontró **una** diferencia real:

- Los `creado_en` / `actualizado_en` salieron como `sa.text('now()')`, que es una cadena
  fija. En PostgreSQL funciona, pero en SQLite —que es donde corren los tests— el
  `DEFAULT now()` es un error de arranque: SQLite no tiene esa función (tiene
  `datetime('now')`). Además `alembic check` lo reportaría como drift, porque el modelo
  declara `func.now()` y no el texto. Aquí van como `sa.func.now()`, que SQLAlchemy
  traduce por dialecto igual que el modelo.

El resto del diff sí coincide con los modelos: los dos `CHECK` de horario, los tres
`ondelete`, el índice único de email, el `Numeric(10,2)` y el índice **parcial**
`uq_reserva_slot_fecha` con su `postgresql_where` (sin él, en PostgreSQL el índice sería
único sobre todo y una reserva cancelada bloquearía el slot).

Revision ID: b0a62a23551a
Revises:
Create Date: 2026-09-25 22:17:06.107950
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'b0a62a23551a'
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('maestra',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('tipo', sa.String(length=30), nullable=False),
    sa.Column('codigo', sa.String(length=30), nullable=False),
    sa.Column('valor', sa.String(length=80), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('tipo', 'codigo', name='uq_maestra_tipo_codigo')
    )
    op.create_index(op.f('ix_maestra_tipo'), 'maestra', ['tipo'], unique=False)
    op.create_table('cliente',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('nombre', sa.String(length=120), nullable=False),
    sa.Column('email', sa.String(length=180), nullable=False),
    sa.Column('password_hash', sa.String(length=255), nullable=False),
    sa.Column('rol_id', sa.Integer(), nullable=False),
    sa.Column('activo', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('creado_en', sa.DateTime(), server_default=sa.func.now(), nullable=False),
    sa.ForeignKeyConstraint(['rol_id'], ['maestra.id'], ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_cliente_email'), 'cliente', ['email'], unique=True)
    op.create_table('cancha',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('nombre', sa.String(length=120), nullable=False),
    sa.Column('ubicacion', sa.String(length=200), nullable=False),
    sa.Column('foto', sa.String(length=500), server_default='', nullable=False),
    sa.Column('activo', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('dueno_id', sa.Integer(), nullable=False),
    sa.Column('creado_en', sa.DateTime(), server_default=sa.func.now(), nullable=False),
    sa.ForeignKeyConstraint(['dueno_id'], ['cliente.id'], ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('horario',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('cancha_id', sa.Integer(), nullable=False),
    sa.Column('dia', sa.SmallInteger(), nullable=False),
    sa.Column('hora_inicio', sa.Time(), nullable=False),
    sa.Column('hora_fin', sa.Time(), nullable=False),
    sa.Column('tarifa', sa.Numeric(precision=10, scale=2), nullable=False),
    sa.CheckConstraint('dia >= 0 AND dia <= 6', name='ck_horario_dia_iso'),
    sa.CheckConstraint('hora_fin > hora_inicio', name='ck_horario_orden'),
    sa.ForeignKeyConstraint(['cancha_id'], ['cancha.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('cancha_id', 'dia', 'hora_inicio', name='uq_horario_cancha_dia_inicio')
    )
    op.create_table('reserva',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('cliente_id', sa.Integer(), nullable=False),
    sa.Column('cancha_id', sa.Integer(), nullable=False),
    sa.Column('horario_id', sa.Integer(), nullable=False),
    sa.Column('fecha', sa.Date(), nullable=False),
    sa.Column('estado', sa.String(length=20), nullable=False),
    sa.Column('creado_en', sa.DateTime(), server_default=sa.func.now(), nullable=False),
    sa.ForeignKeyConstraint(['cancha_id'], ['cancha.id'], ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['cliente_id'], ['cliente.id'], ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['horario_id'], ['horario.id'], ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('uq_reserva_slot_fecha', 'reserva', ['cancha_id', 'horario_id', 'fecha'], unique=True, sqlite_where=sa.text("estado != 'cancelada'"), postgresql_where=sa.text("estado != 'cancelada'"))
    op.create_table('pago',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('reserva_id', sa.Integer(), nullable=False),
    sa.Column('monto', sa.Numeric(precision=10, scale=2), nullable=False),
    sa.Column('metodo', sa.String(length=20), nullable=False),
    sa.Column('estado', sa.String(length=20), nullable=False),
    sa.Column('gateway_ref', sa.String(length=255), nullable=True),
    sa.Column('creado_en', sa.DateTime(), server_default=sa.func.now(), nullable=False),
    sa.Column('actualizado_en', sa.DateTime(), server_default=sa.func.now(), nullable=False),
    sa.ForeignKeyConstraint(['reserva_id'], ['reserva.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('reserva_id')
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('pago')
    op.drop_index('uq_reserva_slot_fecha', table_name='reserva', sqlite_where=sa.text("estado != 'cancelada'"), postgresql_where=sa.text("estado != 'cancelada'"))
    op.drop_table('reserva')
    op.drop_table('horario')
    op.drop_table('cancha')
    op.drop_index(op.f('ix_cliente_email'), table_name='cliente')
    op.drop_table('cliente')
    op.drop_index(op.f('ix_maestra_tipo'), table_name='maestra')
    op.drop_table('maestra')

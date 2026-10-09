"""empty message

Revision ID: 086fbc434d9a
Revises: b0a62a23551a
Create Date: 2026-10-08 07:30:20.923508

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '086fbc434d9a'
down_revision: Union[str, Sequence[str], None] = 'b0a62a23551a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass

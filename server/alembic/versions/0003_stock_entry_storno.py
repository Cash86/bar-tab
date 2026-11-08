"""stock entry storno columns

Revision ID: 0003
Revises: 0002
"""

import sqlalchemy as sa

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("stock_entries") as batch:
        batch.add_column(sa.Column("cancelled_at", sa.DateTime(), nullable=True))
        batch.add_column(sa.Column("cancelled_by_device_id", sa.String(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("stock_entries") as batch:
        batch.drop_column("cancelled_by_device_id")
        batch.drop_column("cancelled_at")

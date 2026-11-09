"""drinks.is_keg: kegs become their own drink kind

Revision ID: 0005
Revises: 0004
"""

import sqlalchemy as sa

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("drinks") as batch:
        batch.add_column(
            sa.Column("is_keg", sa.Boolean(), nullable=False, server_default=sa.false())
        )


def downgrade() -> None:
    with op.batch_alter_table("drinks") as batch:
        batch.drop_column("is_keg")

"""settlement snapshots

Revision ID: 0004
Revises: 0003
"""

import sqlalchemy as sa

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "settlements",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("period_id", sa.String(36), nullable=False),
        sa.Column("token", sa.String(), nullable=False),
        sa.Column("figures_json", sa.Text(), nullable=False),
        sa.Column("mail_status", sa.String(), nullable=False),
        sa.Column("mail_error", sa.String(), nullable=True),
        sa.Column("mailed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint(
            "mail_status IN ('pending', 'sent', 'failed', 'skipped')",
            name="ck_settlements_mail_status_valid",
        ),
        sa.ForeignKeyConstraint(
            ["period_id"], ["periods.id"], name="fk_settlements_period_id_periods"
        ),
        sa.PrimaryKeyConstraint("id", name="pk_settlements"),
        sa.UniqueConstraint("period_id", name="uq_settlements_period_id"),
        sa.UniqueConstraint("token", name="uq_settlements_token"),
    )


def downgrade() -> None:
    op.drop_table("settlements")

"""initial schema

Revision ID: 0001
Revises:
"""

import sqlalchemy as sa

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    ]


def upgrade() -> None:
    op.create_table(
        "price_tiers",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_price_tiers"),
        sa.UniqueConstraint("name", name="uq_price_tiers_name"),
    )
    op.create_table(
        "persons",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("price_tier_id", sa.String(36), nullable=False),
        sa.Column("is_hidden", sa.Boolean(), nullable=False),
        sa.Column("is_collective", sa.Boolean(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_persons"),
        sa.ForeignKeyConstraint(
            ["price_tier_id"], ["price_tiers.id"], name="fk_persons_price_tier_id_price_tiers"
        ),
    )
    op.create_table(
        "drink_groups",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("color", sa.String(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_drink_groups"),
        sa.UniqueConstraint("name", name="uq_drink_groups_name"),
        sa.CheckConstraint(
            "color GLOB '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]'",
            name="ck_drink_groups_color_format",
        ),
    )
    op.create_table(
        "drinks",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("group_id", sa.String(36), nullable=False),
        sa.Column("crate_size", sa.Integer(), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("is_hidden", sa.Boolean(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_drinks"),
        sa.ForeignKeyConstraint(
            ["group_id"], ["drink_groups.id"], name="fk_drinks_group_id_drink_groups"
        ),
        sa.CheckConstraint("crate_size >= 1", name="ck_drinks_crate_size_positive"),
    )
    op.create_table(
        "drink_prices",
        sa.Column("drink_id", sa.String(36), nullable=False),
        sa.Column("price_tier_id", sa.String(36), nullable=False),
        sa.Column("price_cents", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("drink_id", "price_tier_id", name="pk_drink_prices"),
        sa.ForeignKeyConstraint(
            ["drink_id"], ["drinks.id"], name="fk_drink_prices_drink_id_drinks"
        ),
        sa.ForeignKeyConstraint(
            ["price_tier_id"],
            ["price_tiers.id"],
            name="fk_drink_prices_price_tier_id_price_tiers",
        ),
        sa.CheckConstraint("price_cents >= 0", name="ck_drink_prices_price_non_negative"),
    )
    op.create_table(
        "periods",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("started_at", sa.DateTime(), nullable=False),
        sa.Column("closed_at", sa.DateTime(), nullable=True),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_periods"),
    )
    op.create_index(
        "uq_periods_single_open",
        "periods",
        [sa.text("(1)")],  # constant key: at most one row may have closed_at IS NULL
        unique=True,
        sqlite_where=sa.text("closed_at IS NULL"),
    )
    op.create_table(
        "stock_entries",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("period_id", sa.String(36), nullable=False),
        sa.Column("drink_id", sa.String(36), nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_stock_entries"),
        sa.ForeignKeyConstraint(
            ["period_id"], ["periods.id"], name="fk_stock_entries_period_id_periods"
        ),
        sa.ForeignKeyConstraint(
            ["drink_id"], ["drinks.id"], name="fk_stock_entries_drink_id_drinks"
        ),
        sa.CheckConstraint(
            "kind IN ('opening', 'delivery', 'count')", name="ck_stock_entries_kind_valid"
        ),
    )
    op.create_table(
        "bookings",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("period_id", sa.String(36), nullable=False),
        sa.Column("person_id", sa.String(36), nullable=False),
        sa.Column("drink_id", sa.String(36), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("unit_price_cents", sa.Integer(), nullable=False),
        sa.Column("booked_at", sa.DateTime(), nullable=False),
        sa.Column("received_at", sa.DateTime(), nullable=False),
        sa.Column("device_id", sa.String(), nullable=False),
        sa.Column("is_late", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_bookings"),
        sa.ForeignKeyConstraint(
            ["period_id"], ["periods.id"], name="fk_bookings_period_id_periods"
        ),
        sa.ForeignKeyConstraint(
            ["person_id"], ["persons.id"], name="fk_bookings_person_id_persons"
        ),
        sa.ForeignKeyConstraint(["drink_id"], ["drinks.id"], name="fk_bookings_drink_id_drinks"),
    )
    op.create_table(
        "app_settings",
        sa.Column("key", sa.String(), nullable=False),
        sa.Column("value", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("key", name="pk_app_settings"),
    )


def downgrade() -> None:
    for table in (
        "app_settings",
        "bookings",
        "stock_entries",
        "periods",
        "drink_prices",
        "drinks",
        "drink_groups",
        "persons",
        "price_tiers",
    ):
        op.drop_table(table)

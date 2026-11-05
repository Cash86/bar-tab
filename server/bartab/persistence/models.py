from datetime import datetime
from typing import Literal

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Index,
    String,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from bartab.persistence.db import Base, UtcDateTime

ID_LENGTH = 36  # UUID4 string

StockKind = Literal["opening", "delivery", "count"]


class _Timestamps:
    """Set by repository code from the injected Clock, never by the database."""

    created_at: Mapped[datetime] = mapped_column(UtcDateTime)
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime)


class PriceTier(_Timestamps, Base):
    __tablename__ = "price_tiers"

    id: Mapped[str] = mapped_column(String(ID_LENGTH), primary_key=True)
    name: Mapped[str] = mapped_column(String, unique=True)
    sort_order: Mapped[int]


class Person(_Timestamps, Base):
    __tablename__ = "persons"

    id: Mapped[str] = mapped_column(String(ID_LENGTH), primary_key=True)
    name: Mapped[str]
    price_tier_id: Mapped[str] = mapped_column(ForeignKey("price_tiers.id"))
    is_hidden: Mapped[bool] = mapped_column(default=False)
    is_collective: Mapped[bool] = mapped_column(default=False)
    is_active: Mapped[bool] = mapped_column(default=True)


class DrinkGroup(_Timestamps, Base):
    __tablename__ = "drink_groups"
    __table_args__ = (
        CheckConstraint("color GLOB '#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]"
                        "[0-9A-Fa-f][0-9A-Fa-f]'", name="color_format"),
    )  # fmt: skip

    id: Mapped[str] = mapped_column(String(ID_LENGTH), primary_key=True)
    name: Mapped[str] = mapped_column(String, unique=True)
    sort_order: Mapped[int]
    color: Mapped[str]  # "#RRGGBB"


class Drink(_Timestamps, Base):
    __tablename__ = "drinks"
    __table_args__ = (CheckConstraint("crate_size >= 1", name="crate_size_positive"),)

    id: Mapped[str] = mapped_column(String(ID_LENGTH), primary_key=True)
    name: Mapped[str]
    group_id: Mapped[str] = mapped_column(ForeignKey("drink_groups.id"))
    crate_size: Mapped[int]
    sort_order: Mapped[int]
    is_hidden: Mapped[bool] = mapped_column(default=False)
    is_active: Mapped[bool] = mapped_column(default=True)


class DrinkPrice(Base):
    __tablename__ = "drink_prices"
    __table_args__ = (CheckConstraint("price_cents >= 0", name="price_non_negative"),)

    drink_id: Mapped[str] = mapped_column(ForeignKey("drinks.id"), primary_key=True)
    price_tier_id: Mapped[str] = mapped_column(ForeignKey("price_tiers.id"), primary_key=True)
    price_cents: Mapped[int]


class Period(_Timestamps, Base):
    __tablename__ = "periods"
    __table_args__ = (
        Index(
            "uq_periods_single_open",
            text("(1)"),  # constant key: NULLs are distinct, so index a constant instead
            unique=True,
            sqlite_where=text("closed_at IS NULL"),
        ),
    )

    id: Mapped[str] = mapped_column(String(ID_LENGTH), primary_key=True)
    started_at: Mapped[datetime] = mapped_column(UtcDateTime)
    closed_at: Mapped[datetime | None] = mapped_column(UtcDateTime, default=None)


class StockEntry(_Timestamps, Base):
    __tablename__ = "stock_entries"
    __table_args__ = (
        CheckConstraint("kind IN ('opening', 'delivery', 'count')", name="kind_valid"),
    )

    id: Mapped[str] = mapped_column(String(ID_LENGTH), primary_key=True)
    period_id: Mapped[str] = mapped_column(ForeignKey("periods.id"))
    drink_id: Mapped[str] = mapped_column(ForeignKey("drinks.id"))
    kind: Mapped[str]
    quantity: Mapped[int]


class Booking(_Timestamps, Base):
    __tablename__ = "bookings"

    id: Mapped[str] = mapped_column(String(ID_LENGTH), primary_key=True)
    period_id: Mapped[str] = mapped_column(ForeignKey("periods.id"))
    person_id: Mapped[str] = mapped_column(ForeignKey("persons.id"))
    drink_id: Mapped[str] = mapped_column(ForeignKey("drinks.id"))
    quantity: Mapped[int]
    unit_price_cents: Mapped[int]
    booked_at: Mapped[datetime] = mapped_column(UtcDateTime)
    received_at: Mapped[datetime] = mapped_column(UtcDateTime)
    device_id: Mapped[str]
    is_late: Mapped[bool]
    cancelled_at: Mapped[datetime | None] = mapped_column(UtcDateTime, nullable=True)
    cancelled_by_device_id: Mapped[str | None]


class AppSetting(Base):
    __tablename__ = "app_settings"

    key: Mapped[str] = mapped_column(primary_key=True)
    value: Mapped[str]

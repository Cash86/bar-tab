from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class ErrorResponse(BaseModel):
    detail: str


class LockedResponse(BaseModel):
    detail: Literal["locked"]
    retry_after: int


class AdminSessionRequest(BaseModel):
    pin: str = Field(pattern=r"^\d{4,8}$")


class PinChangeRequest(BaseModel):
    current_pin: str
    new_pin: str = Field(pattern=r"^\d{4,8}$")


class AdminSessionResponse(BaseModel):
    token: str
    expires_in: int


class PriceTierOut(BaseModel):
    id: str
    name: str
    sort_order: int


class PersonOut(BaseModel):
    id: str
    name: str
    price_tier_id: str
    is_hidden: bool
    is_collective: bool
    is_active: bool


class GroupOut(BaseModel):
    id: str
    name: str
    sort_order: int
    color: str


class DrinkOut(BaseModel):
    id: str
    name: str
    group_id: str
    crate_size: int
    sort_order: int
    is_hidden: bool
    is_active: bool
    is_keg: bool
    prices: dict[str, int]  # price_tier_id -> cents


class CatalogResponse(BaseModel):
    price_tiers: list[PriceTierOut]
    persons: list[PersonOut]
    groups: list[GroupOut]
    drinks: list[DrinkOut]
    etag: str


class BookingIn(BaseModel):
    """Range checks (quantity, price) happen per item in the route, not here."""

    id: UUID
    person_id: str
    drink_id: str
    quantity: int
    unit_price_cents: int
    booked_at: datetime


class BookingBatchRequest(BaseModel):
    bookings: list[BookingIn] = Field(min_length=1, max_length=200)


class BookingResult(BaseModel):
    id: str
    status: Literal["accepted", "duplicate", "conflict", "rejected"]
    reason: (
        Literal[
            "unknown_person",
            "unknown_drink",
            "invalid_quantity",
            "invalid_price",
            "invalid_booked_at",
        ]
        | None
    ) = None


class BookingBatchResponse(BaseModel):
    results: list[BookingResult]


class TabsResponse(BaseModel):
    period_started_at: datetime
    tabs: dict[str, int]  # person_id -> cents


class RankingsResponse(BaseModel):
    overall: dict[str, int]  # drink_id -> number of bookings
    persons: dict[str, dict[str, int]]  # person_id -> drink_id -> number of bookings


class AdminBookingOut(BaseModel):
    id: str
    person_id: str
    drink_id: str
    quantity: int
    unit_price_cents: int
    booked_at: datetime
    is_late: bool
    cancelled_at: datetime | None


class AdminBookingsResponse(BaseModel):
    bookings: list[AdminBookingOut]


class PersonCreate(BaseModel):
    name: str
    price_tier_id: str
    is_hidden: bool
    is_collective: bool


class PersonUpdate(PersonCreate):
    is_active: bool


class DrinkCreate(BaseModel):
    name: str
    group_id: str
    crate_size: int = Field(ge=1)
    is_hidden: bool
    is_keg: bool = False
    prices: dict[str, int]  # price_tier_id -> cents


class DrinkUpdate(DrinkCreate):
    is_active: bool


class GroupWrite(BaseModel):
    name: str
    color: str = Field(pattern=r"^#[0-9A-Fa-f]{6}$")


class TierWrite(BaseModel):
    name: str


class OrderWrite(BaseModel):
    ids: list[str]


class DeliveryIn(BaseModel):
    """Range checks (quantity) and drink existence happen in the repository."""

    id: UUID
    drink_id: str
    quantity: int


class DeliveryBatchRequest(BaseModel):
    deliveries: list[DeliveryIn] = Field(min_length=1, max_length=200)


class DeliveryOut(BaseModel):
    id: str
    drink_id: str
    quantity: int
    created_at: datetime
    cancelled_at: datetime | None


class DeliveriesResponse(BaseModel):
    deliveries: list[DeliveryOut]


class StockDrinkOut(BaseModel):
    drink_id: str
    name: str
    group_id: str
    group_name: str
    crate_size: int
    expected: int


class StockResponse(BaseModel):
    period_id: str | None  # the open period; a count draft belongs to it
    opening_count_allowed: bool
    drinks: list[StockDrinkOut]  # the drinks to count, in count order


class CountIn(BaseModel):
    """Range check (quantity) happens in the route, so it answers invalid_quantity."""

    drink_id: str
    quantity: int


class CountsRequest(BaseModel):
    counts: list[CountIn]


class CloseRequest(CountsRequest):
    token: str


class DrinkLineOut(BaseModel):
    drink_id: str
    name: str
    group_id: str
    opening: int
    delivered: int
    booked: int
    expected: int
    counted: int
    shrinkage: int  # expected - counted, units; negative = more found than expected
    value_cents: int
    has_price: bool  # False: no price in the valuation tier, valued at 0


class GroupLineOut(BaseModel):
    group_id: str
    name: str
    opening: int
    delivered: int
    booked: int
    expected: int
    counted: int
    shrinkage: int
    value_cents: int
    has_price: bool  # False when any drink of the group has no price in the valuation tier


class SettlementReviewOut(BaseModel):
    token: str
    valuation_tier_name: str
    drinks: list[DrinkLineOut]
    groups: list[GroupLineOut]
    persons_total_cents: int
    hidden_total_cents: int
    grand_total_cents: int
    shrinkage_total_cents: int


MailStatusOut = Literal["pending", "sent", "failed", "skipped"]


class SettlementCloseOut(BaseModel):
    period_id: str
    closed_at: datetime
    mail_status: MailStatusOut


class ResendOut(BaseModel):
    mail_status: MailStatusOut


class SettingsResponse(BaseModel):
    recipients: list[str]
    valuation_tier_id: str | None  # as chosen; may name a tier that no longer exists
    effective_valuation_tier_id: str  # the tier the next settlement is valued with
    last_settlement: SettlementCloseOut | None


class RecipientsWrite(BaseModel):
    """The address syntax check happens in the route, so it answers invalid_email."""

    recipients: list[str]


class ValuationTierWrite(BaseModel):
    tier_id: str

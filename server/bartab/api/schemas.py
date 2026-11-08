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

from pydantic import BaseModel


class AdminSessionRequest(BaseModel):
    pin: str


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

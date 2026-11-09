"""Pure settlement computation: amounts owed, stock reconciliation and shrinkage value."""

import hashlib
import json
from collections.abc import Iterable
from dataclasses import dataclass, field, fields
from datetime import datetime
from typing import Any

from bartab.domain.stock import DrinkStock, group_totals


@dataclass(frozen=True)
class PersonIn:
    id: str
    name: str
    tier_id: str
    is_hidden: bool
    is_collective: bool


@dataclass(frozen=True)
class TierIn:
    id: str
    name: str
    sort_order: int
    is_active: bool


@dataclass(frozen=True)
class DrinkIn:
    id: str
    name: str
    group_id: str
    group_name: str
    crate_size: int
    is_active: bool


@dataclass(frozen=True)
class BookingIn:
    person_id: str
    drink_id: str
    quantity: int
    unit_price_cents: int
    booked_at: datetime
    cancelled_at: datetime | None
    is_late: bool


@dataclass(frozen=True)
class StockIn:
    drink_id: str
    kind: str  # "opening" or "delivery"
    quantity: int
    created_at: datetime
    cancelled_at: datetime | None


@dataclass(frozen=True)
class PersonLine:
    person_id: str
    name: str
    tier_id: str
    quantities_by_group: dict[str, int]
    amount_cents: int


@dataclass(frozen=True)
class DrinkLine:
    drink_id: str
    name: str
    group_id: str
    opening: int
    delivered: int
    booked: int
    expected: int
    counted: int | None
    shrinkage: int | None
    value_cents: int
    has_price: bool


@dataclass(frozen=True)
class Settlement:
    period_id: str
    started_at: datetime
    ended_at: datetime
    valuation_tier_id: str
    valuation_tier_name: str
    persons: list[PersonLine]
    hidden: list[PersonLine]
    drinks: list[DrinkLine]
    group_totals: dict[str, DrinkLine]
    persons_total_cents: int
    hidden_total_cents: int
    grand_total_cents: int
    shrinkage_total_cents: int
    deliveries: list[StockIn]
    cancelled_deliveries: list[StockIn]
    cancelled_bookings: list[BookingIn]
    person_drink: dict[str, dict[str, int]]
    tier_names: dict[str, str]
    # names of every person, drink and group the figures reference (bookings, cancelled ones
    # included, stock entries and counted drinks); drinks and groups in sort order
    person_names: dict[str, str] = field(default_factory=dict)
    drink_names: dict[str, str] = field(default_factory=dict)
    group_names: dict[str, str] = field(default_factory=dict)


def effective_valuation_tier(tiers: Iterable[TierIn], chosen_id: str | None) -> TierIn:
    active = sorted((t for t in tiers if t.is_active), key=lambda t: t.sort_order)
    for tier in active:
        if tier.id == chosen_id:
            return tier
    if not active:
        raise ValueError("no active price tier")
    return active[0]


def _booked_by_drink(bookings: Iterable[BookingIn]) -> dict[str, int]:
    booked: dict[str, int] = {}
    for b in bookings:
        if b.cancelled_at is None:
            booked[b.drink_id] = booked.get(b.drink_id, 0) + b.quantity
    return booked


def _stock_sums(stocks: Iterable[StockIn], kind: str) -> dict[str, int]:
    sums: dict[str, int] = {}
    for s in stocks:
        if s.kind == kind and s.cancelled_at is None:
            sums[s.drink_id] = sums.get(s.drink_id, 0) + s.quantity
    return sums


def _drink_stocks(
    drinks: Iterable[DrinkIn],
    stocks: Iterable[StockIn],
    bookings: Iterable[BookingIn],
    counts: dict[str, int] | None,
) -> dict[str, DrinkStock]:
    stocks = list(stocks)
    opening = _stock_sums(stocks, "opening")
    delivered = _stock_sums(stocks, "delivery")
    booked = _booked_by_drink(bookings)
    return {
        d.id: DrinkStock(
            d.id,
            d.group_id,
            opening.get(d.id, 0),
            delivered.get(d.id, 0),
            booked.get(d.id, 0),
            None if counts is None else counts.get(d.id),
        )
        for d in drinks
    }


def expected_stock(
    drinks: Iterable[DrinkIn], stocks: Iterable[StockIn], bookings: Iterable[BookingIn]
) -> dict[str, int]:
    """Opening + delivered - booked per drink, cancelled entries left out."""
    return {d: s.expected for d, s in _drink_stocks(drinks, stocks, bookings, None).items()}


def drinks_to_count(
    drinks: Iterable[DrinkIn], stocks: Iterable[StockIn], bookings: Iterable[BookingIn]
) -> list[DrinkIn]:
    drinks = list(drinks)
    expected = expected_stock(drinks, stocks, bookings)
    return [d for d in drinks if d.is_active or expected[d.id] != 0]


def _line(
    drink_id: str,
    name: str,
    ds: DrinkStock,
    price: int | None,
    previewing: bool,
) -> DrinkLine:
    shrinkage = ds.shrinkage
    value = 0 if shrinkage is None or price is None else shrinkage * price
    return DrinkLine(
        drink_id,
        name,
        ds.group_id,
        ds.opening,
        ds.delivered,
        ds.booked,
        ds.expected,
        None if previewing else ds.counted,
        shrinkage,
        value,
        price is not None,
    )


def _group_stocks(stocks: Iterable[DrinkStock], previewing: bool) -> dict[str, DrinkStock]:
    totals = group_totals(stocks)
    if previewing:
        return {
            g: DrinkStock("", g, t.opening, t.delivered, t.booked, None) for g, t in totals.items()
        }
    return totals


def compute_settlement(
    *,
    period_id: str,
    started_at: datetime,
    ended_at: datetime,
    persons: list[PersonIn],
    tiers: list[TierIn],
    drinks: list[DrinkIn],
    bookings: list[BookingIn],
    stocks: list[StockIn],
    prices: dict[tuple[str, str], int],
    counts: dict[str, int] | None,
    valuation_tier: TierIn,
) -> Settlement:
    to_count = drinks_to_count(drinks, stocks, bookings)
    if counts is not None:
        missing = [d.id for d in to_count if d.id not in counts]
        if missing:
            raise ValueError(f"missing counts for drinks: {missing}")
    group_of = {d.id: d.group_id for d in drinks}
    drink_stocks = _drink_stocks(to_count, stocks, bookings, counts)

    lines: list[DrinkLine] = []
    value_by_group: dict[str, int] = {}
    group_rank: dict[str, int] = {}
    for d in to_count:
        group_rank.setdefault(d.group_id, len(group_rank))
    for d in sorted(to_count, key=lambda d: group_rank[d.group_id]):
        price = prices.get((valuation_tier.id, d.id))
        line = _line(d.id, d.name, drink_stocks[d.id], price, counts is None)
        lines.append(line)
    group_names = {d.group_id: d.group_name for d in to_count}
    group_stocks = _group_stocks(drink_stocks.values(), counts is None)
    group_lines: dict[str, DrinkLine] = {}
    for gid, gs in group_stocks.items():
        value = sum(line.value_cents for line in lines if line.group_id == gid)
        value_by_group[gid] = value
        group_lines[gid] = DrinkLine(
            "",
            group_names[gid],
            gid,
            gs.opening,
            gs.delivered,
            gs.booked,
            gs.expected,
            gs.counted,
            gs.shrinkage,
            value,
            all(line.has_price for line in lines if line.group_id == gid),
        )

    tier_order = {t.id: t.sort_order for t in tiers}
    person_by_id = {p.id: p for p in persons}
    qty_by_group: dict[str, dict[str, int]] = {}
    amount: dict[str, int] = {}
    person_drink: dict[str, dict[str, int]] = {}
    for b in bookings:
        if b.cancelled_at is not None:
            continue
        if b.person_id not in person_by_id:
            raise ValueError(f"booking for unknown person: {b.person_id}")
        if b.drink_id not in group_of:
            raise ValueError(f"booking for unknown drink: {b.drink_id}")
        groups = qty_by_group.setdefault(b.person_id, {})
        gid = group_of[b.drink_id]
        groups[gid] = groups.get(gid, 0) + b.quantity
        amount[b.person_id] = amount.get(b.person_id, 0) + b.quantity * b.unit_price_cents
        per_drink = person_drink.setdefault(b.person_id, {})
        per_drink[b.drink_id] = per_drink.get(b.drink_id, 0) + b.quantity

    def person_lines(hidden: bool) -> list[PersonLine]:
        chosen = [p for p in persons if p.id in amount and p.is_hidden == hidden]
        for p in chosen:
            if p.tier_id not in tier_order:
                raise ValueError(f"person {p.id} has unknown tier: {p.tier_id}")
        chosen.sort(key=lambda p: (tier_order[p.tier_id], p.name))
        return [
            PersonLine(p.id, p.name, p.tier_id, qty_by_group[p.id], amount[p.id]) for p in chosen
        ]

    visible, hidden = person_lines(False), person_lines(True)
    persons_total = sum(p.amount_cents for p in visible)
    hidden_total = sum(p.amount_cents for p in hidden)
    stocks = list(stocks)
    referenced_persons = {b.person_id for b in bookings}
    referenced_drinks = {d.id for d in to_count} | {b.drink_id for b in bookings}
    referenced_drinks |= {x.drink_id for x in stocks}
    named_drinks = [d for d in drinks if d.id in referenced_drinks]
    return Settlement(
        period_id=period_id,
        started_at=started_at,
        ended_at=ended_at,
        valuation_tier_id=valuation_tier.id,
        valuation_tier_name=valuation_tier.name,
        persons=visible,
        hidden=hidden,
        drinks=lines,
        group_totals=group_lines,
        persons_total_cents=persons_total,
        hidden_total_cents=hidden_total,
        grand_total_cents=persons_total + hidden_total,
        shrinkage_total_cents=sum(value_by_group.values()),
        deliveries=sorted(
            (s for s in stocks if s.kind == "delivery" and s.cancelled_at is None),
            key=lambda s: s.created_at,
        ),
        cancelled_deliveries=sorted(
            (s for s in stocks if s.kind == "delivery" and s.cancelled_at is not None),
            key=lambda s: s.created_at,
        ),
        cancelled_bookings=sorted(
            (b for b in bookings if b.cancelled_at is not None), key=lambda b: b.booked_at
        ),
        person_drink=person_drink,
        tier_names={t.id: t.name for t in tiers},
        person_names={p.id: p.name for p in persons if p.id in referenced_persons},
        drink_names={d.id: d.name for d in named_drinks},
        group_names={d.group_id: d.group_name for d in named_drinks},
    )


def figures_token(s: Settlement) -> str:
    payload = json.dumps(settlement_to_json(s), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def _dt(value: datetime | None) -> str | None:
    return None if value is None else value.isoformat()


def _undt(value: str | None) -> datetime | None:
    return None if value is None else datetime.fromisoformat(value)


def _booking_to_json(b: BookingIn) -> dict[str, Any]:
    return {
        "person_id": b.person_id,
        "drink_id": b.drink_id,
        "quantity": b.quantity,
        "unit_price_cents": b.unit_price_cents,
        "booked_at": _dt(b.booked_at),
        "cancelled_at": _dt(b.cancelled_at),
        "is_late": b.is_late,
    }


def _booking_from_json(d: dict[str, Any]) -> BookingIn:
    return BookingIn(
        d["person_id"],
        d["drink_id"],
        d["quantity"],
        d["unit_price_cents"],
        _undt(d["booked_at"]),  # type: ignore[arg-type]
        _undt(d["cancelled_at"]),
        d["is_late"],
    )


def _stock_to_json(s: StockIn) -> dict[str, Any]:
    return {
        "drink_id": s.drink_id,
        "kind": s.kind,
        "quantity": s.quantity,
        "created_at": _dt(s.created_at),
        "cancelled_at": _dt(s.cancelled_at),
    }


def _stock_from_json(d: dict[str, Any]) -> StockIn:
    return StockIn(
        d["drink_id"],
        d["kind"],
        d["quantity"],
        _undt(d["created_at"]),  # type: ignore[arg-type]
        _undt(d["cancelled_at"]),
    )


def _plain(obj: Any) -> dict[str, Any]:
    return {f.name: getattr(obj, f.name) for f in fields(obj)}


def settlement_to_json(s: Settlement) -> dict[str, Any]:
    return {
        "period_id": s.period_id,
        "started_at": _dt(s.started_at),
        "ended_at": _dt(s.ended_at),
        "valuation_tier_id": s.valuation_tier_id,
        "valuation_tier_name": s.valuation_tier_name,
        "persons": [_plain(p) for p in s.persons],
        "hidden": [_plain(p) for p in s.hidden],
        "drinks": [_plain(d) for d in s.drinks],
        "group_totals": {g: _plain(d) for g, d in s.group_totals.items()},
        "persons_total_cents": s.persons_total_cents,
        "hidden_total_cents": s.hidden_total_cents,
        "grand_total_cents": s.grand_total_cents,
        "shrinkage_total_cents": s.shrinkage_total_cents,
        "deliveries": [_stock_to_json(x) for x in s.deliveries],
        "cancelled_deliveries": [_stock_to_json(x) for x in s.cancelled_deliveries],
        "cancelled_bookings": [_booking_to_json(b) for b in s.cancelled_bookings],
        "person_drink": s.person_drink,
        "tier_names": s.tier_names,
        "person_names": s.person_names,
        "drink_names": s.drink_names,
        "group_names": s.group_names,
    }


def settlement_from_json(d: dict[str, Any]) -> Settlement:
    return Settlement(
        period_id=d["period_id"],
        started_at=_undt(d["started_at"]),  # type: ignore[arg-type]
        ended_at=_undt(d["ended_at"]),  # type: ignore[arg-type]
        valuation_tier_id=d["valuation_tier_id"],
        valuation_tier_name=d["valuation_tier_name"],
        persons=[PersonLine(**p) for p in d["persons"]],
        hidden=[PersonLine(**p) for p in d["hidden"]],
        drinks=[DrinkLine(**x) for x in d["drinks"]],
        group_totals={g: DrinkLine(**x) for g, x in d["group_totals"].items()},
        persons_total_cents=d["persons_total_cents"],
        hidden_total_cents=d["hidden_total_cents"],
        grand_total_cents=d["grand_total_cents"],
        shrinkage_total_cents=d["shrinkage_total_cents"],
        deliveries=[_stock_from_json(x) for x in d["deliveries"]],
        cancelled_deliveries=[_stock_from_json(x) for x in d["cancelled_deliveries"]],
        cancelled_bookings=[_booking_from_json(b) for b in d["cancelled_bookings"]],
        person_drink=d["person_drink"],
        tier_names=d["tier_names"],
        person_names=d.get("person_names", {}),
        drink_names=d.get("drink_names", {}),
        group_names=d.get("group_names", {}),
    )

"""Master data, bookings and deliveries shared by the settlement and settings API tests."""

from bartab.persistence import deliveries, repos
from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier

# d3 is inactive but has stock, d2 is booked by a hidden account without a delivery
COUNTS = {"d1": 7, "d2": 0, "d3": 4}


def seed(app) -> None:
    clock = app.state.clock
    now = clock.now()
    stamps = {"created_at": now, "updated_at": now}
    with app.state.session_factory() as session:
        session.add_all(
            [
                PriceTier(id="t1", name="Member", sort_order=1, **stamps),
                PriceTier(id="t2", name="Guest", sort_order=2, **stamps),
                DrinkGroup(id="g2", name="Soft", sort_order=2, color="#112233", **stamps),
                DrinkGroup(id="g1", name="Beer", sort_order=1, color="#445566", **stamps),
            ]
        )
        session.flush()
        session.add_all(
            [
                Person(id="pa", name="Alice", price_tier_id="t1", **stamps),
                Person(id="ph", name="Keg", price_tier_id="t1", is_hidden=True, **stamps),
                Drink(id="d2", name="Cola", group_id="g2", crate_size=12, sort_order=0, **stamps),
                Drink(id="d1", name="Lager", group_id="g1", crate_size=20, sort_order=5, **stamps),
                Drink(
                    id="d3",
                    name="Old",
                    group_id="g1",
                    crate_size=24,
                    sort_order=1,
                    is_active=False,
                    **stamps,
                ),
            ]
        )
        session.flush()
        session.add_all(
            [
                DrinkPrice(drink_id="d1", price_tier_id="t1", price_cents=60),
                DrinkPrice(drink_id="d1", price_tier_id="t2", price_cents=150),
                DrinkPrice(drink_id="d2", price_tier_id="t1", price_cents=100),
            ]
        )
        session.flush()
        deliveries.add_deliveries(session, clock, [("e1", "d1", 10), ("e2", "d3", 4)])
        book(session, clock, "b1", person="pa", drink="d1", qty=2, price=60)
        book(session, clock, "b2", person="ph", drink="d2", qty=1, price=100)
        session.commit()


def book(session, clock, bid, *, person="pa", drink="d1", qty=1, price=60) -> None:
    repos.add_booking(
        session,
        id=bid,
        person_id=person,
        drink_id=drink,
        quantity=qty,
        unit_price_cents=price,
        booked_at=clock.now(),
        device_id="dev",
        clock=clock,
    )


def counts_body(counts: dict[str, int]) -> list[dict]:
    return [{"drink_id": d, "quantity": q} for d, q in counts.items()]

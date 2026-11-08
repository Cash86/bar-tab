from datetime import UTC, datetime

import pytest

from bartab.domain.clock import FixedClock
from bartab.persistence import deliveries
from bartab.persistence.models import Drink, DrinkGroup, StockEntry


@pytest.fixture
def clock():
    return FixedClock(datetime(2026, 11, 2, 18, 0, tzinfo=UTC))


@pytest.fixture
def s(db_session, clock):
    now = clock.now()
    stamps = {"created_at": now, "updated_at": now}
    db_session.add(DrinkGroup(id="g", name="Beer", sort_order=1, color="#112233", **stamps))
    db_session.flush()
    db_session.add(Drink(id="d", name="Lager", group_id="g", crate_size=20, sort_order=1, **stamps))
    db_session.commit()
    return db_session


def test_unknown_drink_stores_nothing(s, clock):
    with pytest.raises(deliveries.UnknownDrink):
        deliveries.add_deliveries(s, clock, [("a", "d", 1), ("b", "x", 1)])
    assert s.query(StockEntry).count() == 0


def test_duplicate_id_inside_batch_with_different_content_conflicts(s, clock):
    with pytest.raises(deliveries.DeliveryConflict):
        deliveries.add_deliveries(s, clock, [("a", "d", 1), ("a", "d", 2)])
    assert s.query(StockEntry).count() == 0


def test_duplicate_id_inside_batch_with_same_content_is_stored_once(s, clock):
    result = deliveries.add_deliveries(s, clock, [("a", "d", 1), ("a", "d", 1)])
    assert [e.id for e in result] == ["a", "a"]
    assert s.query(StockEntry).count() == 1


def test_invalid_quantity_stores_nothing(s, clock):
    with pytest.raises(deliveries.InvalidQuantity):
        deliveries.add_deliveries(s, clock, [("a", "d", 1), ("b", "d", 0)])
    assert s.query(StockEntry).count() == 0

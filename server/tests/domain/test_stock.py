import pytest

from bartab.domain.stock import DrinkStock, group_totals


def _stock(opening, delivered, booked, counted, drink_id="d1", group_id="g1"):
    return DrinkStock(drink_id, group_id, opening, delivered, booked, counted)


@pytest.mark.parametrize(
    ("opening", "delivered", "booked", "counted", "expected", "shrinkage"),
    [
        (100, 40, 30, 105, 110, 5),
        (100, 40, 30, None, 110, None),
        (100, 40, 30, 113, 110, -3),
        (0, 0, 0, 0, 0, 0),
    ],
)
def test_expected_and_shrinkage(opening, delivered, booked, counted, expected, shrinkage):
    stock = _stock(opening, delivered, booked, counted)
    assert stock.expected == expected
    assert stock.shrinkage == shrinkage


def test_group_totals_sums_per_group():
    totals = group_totals(
        [
            _stock(10, 5, 3, 11, "a", "g1"),
            _stock(20, 0, 8, 10, "b", "g1"),
            _stock(7, 1, 2, 6, "c", "g2"),
        ]
    )
    assert set(totals) == {"g1", "g2"}
    assert totals["g1"] == DrinkStock("", "g1", 30, 5, 11, 21)
    assert totals["g2"] == DrinkStock("", "g2", 7, 1, 2, 6)


def test_group_totals_uncounted_member_makes_counted_none():
    totals = group_totals([_stock(10, 0, 0, 10, "a"), _stock(10, 0, 0, None, "b")])
    assert totals["g1"].counted is None
    assert totals["g1"].shrinkage is None

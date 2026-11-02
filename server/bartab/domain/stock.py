from collections.abc import Iterable
from dataclasses import dataclass


@dataclass(frozen=True)
class DrinkStock:
    drink_id: str
    group_id: str
    opening: int
    delivered: int
    booked: int
    counted: int | None

    @property
    def expected(self) -> int:
        return self.opening + self.delivered - self.booked

    @property
    def shrinkage(self) -> int | None:
        if self.counted is None:
            return None
        return self.expected - self.counted


def group_totals(stocks: Iterable[DrinkStock]) -> dict[str, DrinkStock]:
    totals: dict[str, DrinkStock] = {}
    for s in stocks:
        prev = totals.get(s.group_id) or DrinkStock("", s.group_id, 0, 0, 0, 0)
        counted = None if prev.counted is None or s.counted is None else prev.counted + s.counted
        totals[s.group_id] = DrinkStock(
            "",
            s.group_id,
            prev.opening + s.opening,
            prev.delivered + s.delivered,
            prev.booked + s.booked,
            counted,
        )
    return totals

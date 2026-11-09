"""Names and column order of a settlement, tolerant of snapshots without the name maps."""

from bartab.domain.settlement import Settlement


def person_names_of(s: Settlement) -> dict[str, str]:
    return {**{p.person_id: p.name for p in [*s.persons, *s.hidden]}, **s.person_names}


def drink_names_of(s: Settlement) -> dict[str, str]:
    return {**{d.drink_id: d.name for d in s.drinks}, **s.drink_names}


def group_name(s: Settlement, group_id: str) -> str:
    if group_id in s.group_names:
        return s.group_names[group_id]
    if group_id in s.group_totals:
        return s.group_totals[group_id].name
    return group_id


def booked_group_ids(s: Settlement) -> list[str]:
    """Counted groups and groups anyone booked, in sort order (older snapshots: counted first)."""
    booked = [g for p in [*s.persons, *s.hidden] for g in p.quantities_by_group]
    wanted = set(s.group_totals) | set(booked)
    order = dict.fromkeys([*s.group_names, *s.group_totals, *booked])
    return [g for g in order if g in wanted]


def booked_drink_ids(s: Settlement) -> list[str]:
    """Counted drinks and drinks anyone booked, in sort order (older snapshots: counted first)."""
    counted = [d.drink_id for d in s.drinks]
    booked = [d for per in s.person_drink.values() for d in per]
    wanted = set(counted) | set(booked)
    order = dict.fromkeys([*s.drink_names, *counted, *booked])
    return [d for d in order if d in wanted]

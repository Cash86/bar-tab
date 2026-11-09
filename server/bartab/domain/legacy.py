"""Plan an import of the legacy system's CSV files (pure; the CLI writes the plan to the DB).

The mapping (a JSON file outside git) holds every club-specific decision. Roles are the keys
of ``Mapping.tiers`` plus the literal role ``hidden``. In drink.csv the two price columns
(``Aktivenpreis``, ``Altherrenpreis``) belong to the first and the second role of
``Mapping.tiers`` in that order.
"""

import csv
import io
import re
from dataclasses import dataclass, field

from bartab.domain.names import MAX_DRINK, MAX_GROUP, MAX_PERSON, MAX_TIER, name_key

PLACEHOLDER_CENTS = 1_000_000
HIDDEN = "hidden"
_USER_COLUMNS = 2
_DRINK_COLUMNS = 5
_EURO = re.compile(r"([0-9]+)(?:\.([0-9]{1,2}))?")


class LegacyError(Exception):
    """The input cannot be imported; the message lists every problem found."""


@dataclass(frozen=True)
class ExtraDrink:
    name: str
    group: str
    crate_size: int
    prices: dict[str, int]
    is_keg: bool = False


@dataclass(frozen=True)
class Mapping:
    tiers: dict[str, str]
    hidden_tier: str
    groups: dict[str, str]
    group_order: list[str]
    collective: list[str] = field(default_factory=list)
    kegs: list[str] = field(default_factory=list)
    person_rename: dict[str, str] = field(default_factory=dict)
    rename: dict[str, str] = field(default_factory=dict)
    word_replacements: dict[str, str] = field(default_factory=dict)
    price_overrides: dict[str, dict[str, int]] = field(default_factory=dict)
    extra_drinks: list[ExtraDrink] = field(default_factory=list)


@dataclass(frozen=True)
class PlannedPerson:
    name: str
    tier: str
    is_hidden: bool
    is_collective: bool


@dataclass(frozen=True)
class PlannedDrink:
    name: str
    group: str
    crate_size: int
    is_hidden: bool
    is_keg: bool
    prices: dict[str, int]


@dataclass(frozen=True)
class ImportPlan:
    tiers: list[str]
    groups: list[str]
    persons: list[PlannedPerson]
    drinks: list[PlannedDrink]
    report: list[str]


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _str_dict(value: object, key: str, problems: list[str]) -> dict[str, str]:
    if not isinstance(value, dict) or not all(
        isinstance(k, str) and isinstance(v, str) for k, v in value.items()
    ):
        problems.append(f"mapping.{key} must be an object of strings")
        return {}
    return dict(value)


def _str_list(value: object, key: str, problems: list[str]) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        problems.append(f"mapping.{key} must be a list of strings")
        return []
    return list(value)


def _prices(value: object, where: str, problems: list[str]) -> dict[str, int]:
    if not isinstance(value, dict) or not all(
        isinstance(k, str) and _is_int(v) and v >= 0 for k, v in value.items()
    ):
        problems.append(f"{where} must map roles to non-negative integer cents")
        return {}
    return dict(value)


def _extra_drink(raw: object, problems: list[str]) -> ExtraDrink | None:
    keys = {"name", "group", "crate_size", "prices", "is_keg"}
    if not isinstance(raw, dict):
        problems.append("mapping.extra_drinks entries must be objects")
        return None
    unknown = sorted(set(raw) - keys)
    if unknown:
        problems.append(f"mapping.extra_drinks: unknown keys {unknown}")
    name, group = raw.get("name"), raw.get("group")
    crate, is_keg = raw.get("crate_size"), raw.get("is_keg", False)
    if not isinstance(name, str) or not isinstance(group, str):
        problems.append("mapping.extra_drinks: name and group must be strings")
        return None
    if not _is_int(crate) or crate < 1:
        problems.append(f"mapping.extra_drinks {name!r}: crate_size must be an integer >= 1")
        return None
    if not isinstance(is_keg, bool):
        problems.append(f"mapping.extra_drinks {name!r}: is_keg must be a boolean")
        return None
    prices = _prices(raw.get("prices"), f"mapping.extra_drinks {name!r} prices", problems)
    return ExtraDrink(name, group, crate, prices, is_keg)


def parse_mapping(data: dict) -> Mapping:
    problems: list[str] = []
    allowed = {f for f in Mapping.__dataclass_fields__}
    if not isinstance(data, dict):
        raise LegacyError("mapping must be a JSON object")
    for key in sorted(set(data) - allowed):
        problems.append(f"mapping: unknown key {key!r}")
    for key in ("tiers", "hidden_tier", "groups", "group_order"):
        if key not in data:
            problems.append(f"mapping: missing key {key!r}")
    tiers = _str_dict(data.get("tiers", {}), "tiers", problems)
    hidden_tier = data.get("hidden_tier", "")
    if not isinstance(hidden_tier, str):
        problems.append("mapping.hidden_tier must be a string")
        hidden_tier = ""
    overrides: dict[str, dict[str, int]] = {}
    raw_overrides = data.get("price_overrides", {})
    if not isinstance(raw_overrides, dict):
        problems.append("mapping.price_overrides must be an object")
    else:
        for drink, prices in raw_overrides.items():
            overrides[drink] = _prices(prices, f"mapping.price_overrides {drink!r}", problems)
    extras = []
    raw_extras = data.get("extra_drinks", [])
    if not isinstance(raw_extras, list):
        problems.append("mapping.extra_drinks must be a list")
        raw_extras = []
    for raw in raw_extras:
        extra = _extra_drink(raw, problems)
        if extra is not None:
            extras.append(extra)
    mapping = Mapping(
        tiers=tiers,
        hidden_tier=hidden_tier,
        groups=_str_dict(data.get("groups", {}), "groups", problems),
        group_order=_str_list(data.get("group_order", []), "group_order", problems),
        collective=_str_list(data.get("collective", []), "collective", problems),
        kegs=_str_list(data.get("kegs", []), "kegs", problems),
        person_rename=_str_dict(data.get("person_rename", {}), "person_rename", problems),
        rename=_str_dict(data.get("rename", {}), "rename", problems),
        word_replacements=_str_dict(
            data.get("word_replacements", {}), "word_replacements", problems
        ),
        price_overrides=overrides,
        extra_drinks=extras,
    )
    if problems:
        raise LegacyError("\n".join(problems))
    return mapping


def decode_legacy(raw: bytes) -> str:
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    try:
        text = raw.decode("cp1252")
    except UnicodeDecodeError as exc:
        raise LegacyError(f"file is not valid cp1252: {exc}") from exc
    return text.replace("\r\n", "\n").replace("\r", "\n")


def prettify(legacy_name: str, mapping: Mapping) -> str:
    if legacy_name in mapping.rename:
        return mapping.rename[legacy_name]
    words = [w.capitalize() for w in legacy_name.split("_") if w]
    return " ".join(mapping.word_replacements.get(w, w) for w in words)


def euro_to_cents(text: str) -> int:
    match = _EURO.fullmatch(text.strip())
    if match is None:
        raise LegacyError(f"invalid price {text!r}")
    euros, fraction = match.groups()
    return int(euros) * 100 + int((fraction or "").ljust(2, "0"))


def _rows(text: str, columns: int, what: str, problems: list[str]) -> list[list[str]]:
    reader = csv.reader(io.StringIO(text))
    numbered = [(reader.line_num, r) for r in reader if any(c.strip() for c in r)]
    if not numbered or len(numbered[0][1]) != columns:
        problems.append(f"{what}: header must have {columns} columns")
        return []
    body = numbered[1:]
    for number, row in body:
        if len(row) != columns:
            problems.append(f"{what} line {number}: expected {columns} columns, got {len(row)}")
    return [r for _, r in body if len(r) == columns]


def _check_length(kind: str, value: str, limit: int, problems: list[str]) -> None:
    if not value.strip() or len(value.strip()) > limit:
        problems.append(f"{kind} {value!r} is empty or longer than {limit} characters")


def _check_mapping(mapping: Mapping, problems: list[str]) -> list[str]:
    roles = list(mapping.tiers)
    if len(roles) != 2:
        problems.append("mapping.tiers must have exactly two roles (one per price column)")
    if HIDDEN in mapping.tiers:
        problems.append(f"mapping.tiers must not use the reserved role {HIDDEN!r}")
    if mapping.hidden_tier not in mapping.tiers:
        problems.append(f"mapping.hidden_tier {mapping.hidden_tier!r} is not a role in tiers")
    for tier in mapping.tiers.values():
        _check_length("tier", tier, MAX_TIER, problems)
    if len({name_key(t) for t in mapping.tiers.values()}) < len(mapping.tiers):
        problems.append("mapping.tiers: duplicate tier names")
    for group in mapping.group_order:
        _check_length("group", group, MAX_GROUP, problems)
    if len({name_key(g) for g in mapping.group_order}) < len(mapping.group_order):
        problems.append("mapping.group_order: duplicate group names")
    for drink, prices in mapping.price_overrides.items():
        unknown = sorted(set(prices) - set(roles))
        if unknown:
            problems.append(f"price_overrides {drink!r}: unknown roles {unknown}")
    for extra in mapping.extra_drinks:
        _check_length("drink", extra.name, MAX_DRINK, problems)
        if extra.group not in mapping.group_order:
            problems.append(f"extra drink {extra.name!r}: group {extra.group!r} not in group_order")
        if set(extra.prices) != set(roles):
            problems.append(f"extra drink {extra.name!r}: prices need exactly the roles {roles}")
    return roles


def _plan_persons(
    users_csv: str, mapping: Mapping, problems: list[str], report: list[str]
) -> list[PlannedPerson]:
    persons: list[PlannedPerson] = []
    seen: set[str] = set()
    legacy_names: set[str] = set()
    for legacy, role in _rows(users_csv, _USER_COLUMNS, "user.csv", problems):
        legacy, role = legacy.strip(), role.strip()
        legacy_names.add(legacy)
        name = mapping.person_rename.get(legacy, legacy)
        if name != legacy:
            report.append(f"renamed person {legacy!r} to {name!r}")
        _check_length("person", name, MAX_PERSON, problems)
        if name_key(name) in seen:
            problems.append(f"duplicate person {name!r}")
        seen.add(name_key(name))
        if role == HIDDEN:
            tier = mapping.tiers.get(mapping.hidden_tier, "")
        elif role in mapping.tiers:
            tier = mapping.tiers[role]
        else:
            problems.append(f"person {name!r}: unknown role {role!r}")
            continue
        persons.append(PlannedPerson(name, tier, role == HIDDEN, legacy in mapping.collective))
    for key, names in (
        ("collective", mapping.collective),
        ("person_rename", mapping.person_rename),
    ):
        for legacy in names:
            if legacy not in legacy_names:
                problems.append(f"{key} {legacy!r} matches no person")
    return persons


def _plan_drinks(
    drinks_csv: str, mapping: Mapping, roles: list[str], problems: list[str], report: list[str]
) -> list[PlannedDrink]:
    drinks: list[PlannedDrink] = []
    legacy_names: set[str] = set()
    for sort, group_col, *price_cols, crate_text in _rows(
        drinks_csv, _DRINK_COLUMNS, "drink.csv", problems
    ):
        legacy = sort.strip()
        legacy_names.add(legacy)
        name = prettify(legacy, mapping)
        _check_length("drink", name, MAX_DRINK, problems)
        group = mapping.groups.get(legacy)
        if group is None:
            problems.append(f"drink {legacy!r} has no entry in mapping.groups")
        elif group not in mapping.group_order:
            problems.append(f"drink {legacy!r}: group {group!r} not in group_order")
        try:
            crate = int(crate_text.strip())
            if crate < 1:
                raise ValueError
        except ValueError:
            problems.append(f"drink {legacy!r}: invalid crate size {crate_text!r}")
            crate = 1
        prices: dict[str, int] = {}
        for role, text in zip(roles, price_cols, strict=False):
            try:
                cents = euro_to_cents(text)
            except LegacyError as exc:
                problems.append(f"drink {legacy!r}: {exc}")
                continue
            if cents >= PLACEHOLDER_CENTS:
                report.append(f"drink {name!r}: placeholder price for {role} imported as 0")
                cents = 0
            prices[mapping.tiers[role]] = cents
        for role, cents in mapping.price_overrides.get(legacy, {}).items():
            if role in mapping.tiers:
                prices[mapping.tiers[role]] = cents
        is_keg = legacy in mapping.kegs
        if legacy in mapping.rename:
            report.append(f"drink {legacy!r} renamed to {name!r}")
        drinks.append(
            PlannedDrink(
                name,
                group or "",
                crate,
                group_col.strip() == HIDDEN and not is_keg,
                is_keg,
                prices,
            )
        )
    for key, names in (
        ("kegs", mapping.kegs),
        ("rename", list(mapping.rename)),
        ("price_overrides", list(mapping.price_overrides)),
        ("groups", list(mapping.groups)),
    ):
        for name in names:
            if name not in legacy_names:
                problems.append(f"{key} {name!r} matches no drink in drink.csv")
    return drinks


def build_plan(users_csv: str, drinks_csv: str, mapping: Mapping) -> ImportPlan:
    problems: list[str] = []
    report: list[str] = []
    roles = _check_mapping(mapping, problems)
    persons = _plan_persons(users_csv, mapping, problems, report)
    drinks = _plan_drinks(drinks_csv, mapping, roles, problems, report)
    for extra in mapping.extra_drinks:
        drinks.append(
            PlannedDrink(
                extra.name,
                extra.group,
                extra.crate_size,
                False,
                extra.is_keg,
                {mapping.tiers[r]: c for r, c in extra.prices.items() if r in mapping.tiers},
            )
        )
    seen: set[str] = set()
    for drink in drinks:
        if name_key(drink.name) in seen:
            problems.append(f"duplicate drink {drink.name!r}")
        seen.add(name_key(drink.name))
    if problems:
        raise LegacyError("\n".join(problems))
    return ImportPlan(
        tiers=list(mapping.tiers.values()),
        groups=list(mapping.group_order),
        persons=persons,
        drinks=drinks,
        report=report,
    )

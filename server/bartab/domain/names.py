MAX_PERSON, MAX_DRINK, MAX_GROUP, MAX_TIER = 20, 24, 16, 16


class InvalidName(ValueError):
    """The name is empty after trimming or longer than allowed."""


def clean_name(raw: str, max_length: int) -> str:
    name = raw.strip()
    if not name or len(name) > max_length:
        raise InvalidName(raw)
    return name


def name_key(name: str) -> str:
    """Key for the per-kind uniqueness check (case-insensitive, trimmed)."""
    return name.strip().casefold()

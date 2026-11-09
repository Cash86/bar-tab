"""German money formatting for integer cents."""


def format_cents(cents: int) -> str:
    sign = "−" if cents < 0 else ""
    euros, rest = divmod(abs(cents), 100)
    return f"{sign}{euros:,}".replace(",", ".") + f",{rest:02d} €"

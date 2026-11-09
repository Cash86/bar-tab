"""German plain-text mail subjects and bodies for the settlement and the monthly interim mail."""

from datetime import datetime
from zoneinfo import ZoneInfo

from bartab.domain.settlement import Settlement
from bartab.reports.money import format_cents


def local_date(value: datetime, tz: str) -> str:
    return value.astimezone(ZoneInfo(tz)).strftime("%d.%m.%Y")


def settlement_mail(s: Settlement, tz: str) -> tuple[str, str]:
    subject = f"bar-tab: Abrechnung {local_date(s.started_at, tz)} – {local_date(s.ended_at, tz)}"
    body = "\n".join(
        [
            "Die Abrechnung ist abgeschlossen. Das PDF mit allen Einzelheiten hängt an.",
            "",
            f"Mitglieder: {format_cents(s.persons_total_cents)}",
            f"Versteckte Konten: {format_cents(s.hidden_total_cents)}",
            f"Gesamt: {format_cents(s.grand_total_cents)}",
            f"Schwund (bewertet mit {s.valuation_tier_name}): "
            f"{format_cents(s.shrinkage_total_cents)}",
            "",
        ]
    )
    return subject, body


def monthly_mail(preview: Settlement, overdue: int | None, month_label: str) -> tuple[str, str]:
    lines: list[str] = []
    if overdue is not None:
        lines += [f"Inventur überfällig seit {overdue} Tagen", ""]
    lines += ["Zwischenstand, keine Abrechnung", ""]
    drink_names = {d.drink_id: d.name for d in preview.drinks}
    lines.append("Verbrauch je Person:")
    for p in [*preview.persons, *preview.hidden]:
        lines.append(f"{p.name}: {format_cents(p.amount_cents)}")
        for drink_id, qty in preview.person_drink.get(p.person_id, {}).items():
            lines.append(f"  {qty} × {drink_names.get(drink_id, drink_id)}")
    lines += ["", "Erwarteter Bestand:"]
    for d in preview.drinks:
        lines.append(f"{d.name}: {d.expected}")
    lines.append("")
    return f"bar-tab: Zwischenstand {month_label}", "\n".join(lines)

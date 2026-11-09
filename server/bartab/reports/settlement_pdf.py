"""Settlement PDF (fpdf2, bundled DejaVu Sans for umlauts and the minus sign)."""

from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from fpdf import FPDF
from fpdf.enums import XPos, YPos

from bartab.domain.settlement import DrinkLine, PersonLine, Settlement
from bartab.reports.money import format_cents
from bartab.reports.names import (
    booked_drink_ids,
    booked_group_ids,
    drink_names_of,
    group_name,
    person_names_of,
)

FONT_DIR = Path(__file__).parent / "fonts"
FAMILY = "DejaVu"


APPENDIX_FIRST_COL = 50.0
APPENDIX_MIN_COL = 16.0


def appendix_blocks(n_drinks: int, epw: float) -> list[list[int]]:
    """Split drink column indexes into blocks that fit the width with >= 16 mm per column."""
    per_block = max(int((epw - APPENDIX_FIRST_COL) // APPENDIX_MIN_COL), 1)
    return [list(range(i, min(i + per_block, n_drinks))) for i in range(0, n_drinks, per_block)]


def appendix_col_width(block: list[int], epw: float) -> float:
    return (epw - APPENDIX_FIRST_COL) / max(len(block), 1)


def _local(value: datetime, tz: str) -> str:
    return value.astimezone(ZoneInfo(tz)).strftime("%d.%m.%Y %H:%M")


class _Pdf(FPDF):
    def __init__(self) -> None:
        super().__init__(orientation="L", format="A4")
        self.add_font(FAMILY, "", str(FONT_DIR / "DejaVuSans.ttf"))
        self.add_font(FAMILY, "B", str(FONT_DIR / "DejaVuSans-Bold.ttf"))
        self.set_auto_page_break(True, margin=12)
        self.set_margins(12, 12, 12)
        self.set_font(FAMILY, "", 9)
        self.add_page()

    def heading(self, text: str) -> None:
        self.ln(3)
        self.set_font(FAMILY, "B", 12)
        self.cell(0, 8, text, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
        self.set_font(FAMILY, "", 9)

    def line(self, text: str, bold: bool = False) -> None:
        self.set_font(FAMILY, "B" if bold else "", 9)
        self.cell(0, 5.5, text, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
        self.set_font(FAMILY, "", 9)

    def table(
        self,
        header: list[str],
        rows: list[list[str]],
        bold_last: bool = False,
        widths: list[float] | None = None,
    ) -> None:
        """Rows of text cells; the first column is left aligned, the others right aligned."""
        if widths is None:
            if len(header) == 1:
                widths = [self.epw]
            else:
                first = min(70.0, self.epw / 3)
                widths = [first] + [(self.epw - first) / (len(header) - 1)] * (len(header) - 1)

        def fit(text: str, width: float) -> str:
            if self.get_string_width(text) <= width - 2:
                return text
            while text and self.get_string_width(text + "…") > width - 2:
                text = text[:-1]
            return text + "…"

        def emit(cells: list[str], bold: bool) -> None:
            self.set_font(FAMILY, "B" if bold else "", 9)
            for i, (cell, w) in enumerate(zip(cells, widths, strict=True)):
                last = i == len(cells) - 1
                self.cell(
                    w,
                    5.5,
                    fit(cell, w),
                    border="B",
                    align="L" if i == 0 else "R",
                    new_x=XPos.LMARGIN if last else XPos.RIGHT,
                    new_y=YPos.NEXT if last else YPos.TOP,
                )
            self.set_font(FAMILY, "", 9)

        emit(header, True)
        for n, row in enumerate(rows):
            emit(row, bold_last and n == len(rows) - 1)


def _person_rows(people: list[PersonLine], group_ids: list[str]) -> list[list[str]]:
    return [
        [
            p.name,
            *[str(p.quantities_by_group.get(g, 0)) for g in group_ids],
            format_cents(p.amount_cents),
        ]
        for p in people
    ]


def render_settlement_pdf(s: Settlement, tz: str) -> bytes:
    pdf = _Pdf()
    shrink_group_ids = list(s.group_totals)
    group_ids = booked_group_ids(s)
    group_names = [group_name(s, g) for g in group_ids]
    drink_names = drink_names_of(s)
    person_names = person_names_of(s)
    person_header = ["Person", *group_names, "Betrag"]

    pdf.set_font(FAMILY, "B", 16)
    pdf.cell(0, 10, "bar-tab Abrechnung", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    pdf.set_font(FAMILY, "", 9)
    pdf.line(f"Zeitraum: {_local(s.started_at, tz)} – {_local(s.ended_at, tz)}")
    pdf.line(f"Schwund bewertet mit Preisstufe: {s.valuation_tier_name}")

    pdf.heading("Mitglieder je Preisstufe")
    tier_ids = list(dict.fromkeys(p.tier_id for p in s.persons))
    for tier_id in tier_ids:
        members = [p for p in s.persons if p.tier_id == tier_id]
        label = s.tier_names.get(tier_id, tier_id)
        pdf.line(f"Preisstufe {label}", bold=True)
        rows = _person_rows(members, group_ids)
        rows.append(
            [
                "Zwischensumme",
                *["" for _ in group_ids],
                format_cents(sum(p.amount_cents for p in members)),
            ]
        )
        pdf.table(person_header, rows, bold_last=True)
        pdf.ln(2)

    pdf.heading("Versteckte Konten")
    if s.hidden:
        pdf.table(person_header, _person_rows(s.hidden, group_ids))
    else:
        pdf.line("keine")

    pdf.heading("Summen")
    pdf.table(
        ["", "Betrag"],
        [
            ["Mitglieder", format_cents(s.persons_total_cents)],
            ["Versteckte Konten", format_cents(s.hidden_total_cents)],
            ["Gesamt", format_cents(s.grand_total_cents)],
        ],
        bold_last=True,
    )

    pdf.heading(f"Schwund (bewertet mit {s.valuation_tier_name})")
    shrink_header = [
        "Getränk",
        "Anfang",
        "Geliefert",
        "Gebucht",
        "Erwartet",
        "Gezählt",
        "Schwund",
        "Wert",
        "Hinweis",
    ]
    shrink_widths = [60.0, 20, 22, 22, 22, 22, 22, 33, 0]
    shrink_widths[-1] = pdf.epw - sum(shrink_widths[:-1])

    def shrink_row(name: str, line: DrinkLine) -> list[str]:
        counted = "" if line.counted is None else str(line.counted)
        shrink = "" if line.shrinkage is None else str(line.shrinkage)
        return [
            name,
            str(line.opening),
            str(line.delivered),
            str(line.booked),
            str(line.expected),
            counted,
            shrink,
            format_cents(line.value_cents),
            "" if line.has_price else "kein Preis",
        ]

    rows: list[list[str]] = []
    for gid in shrink_group_ids:
        for d in (d for d in s.drinks if d.group_id == gid):
            rows.append(shrink_row(d.name, d))
        g = s.group_totals[gid]
        rows.append(shrink_row(f"Summe {g.name}", g))
    rows.append(
        ["Schwund gesamt", "", "", "", "", "", "", format_cents(s.shrinkage_total_cents), ""]
    )
    pdf.table(shrink_header, rows, bold_last=True, widths=shrink_widths)

    pdf.heading("Lieferungen")
    if s.deliveries:
        pdf.table(
            ["Getränk", "Menge", "Erfasst"],
            [
                [drink_names.get(x.drink_id, x.drink_id), str(x.quantity), _local(x.created_at, tz)]
                for x in s.deliveries
            ],
        )
    else:
        pdf.line("keine")

    pdf.heading("Stornos")
    pdf.line("Stornierte Buchungen", bold=True)
    if s.cancelled_bookings:
        pdf.table(
            ["Person", "Getränk", "Menge", "Betrag", "Gebucht", "Storniert"],
            [
                [
                    person_names.get(b.person_id, b.person_id),
                    drink_names.get(b.drink_id, b.drink_id),
                    str(b.quantity),
                    format_cents(b.quantity * b.unit_price_cents),
                    _local(b.booked_at, tz),
                    _local(b.cancelled_at, tz) if b.cancelled_at else "",
                ]
                for b in s.cancelled_bookings
            ],
        )
    else:
        pdf.line("keine")
    pdf.line("Stornierte Lieferungen", bold=True)
    if s.cancelled_deliveries:
        pdf.table(
            ["Getränk", "Menge", "Erfasst", "Storniert"],
            [
                [
                    drink_names.get(x.drink_id, x.drink_id),
                    str(x.quantity),
                    _local(x.created_at, tz),
                    _local(x.cancelled_at, tz) if x.cancelled_at else "",
                ]
                for x in s.cancelled_deliveries
            ],
        )
    else:
        pdf.line("keine")

    pdf.add_page()
    pdf.heading("Anhang: Person × Getränk")
    drink_ids = booked_drink_ids(s)
    rows = []
    for p in [*s.persons, *s.hidden]:
        per = s.person_drink.get(p.person_id, {})
        rows.append([p.name, *[str(per.get(d, 0)) for d in drink_ids]])
    for n, block in enumerate(appendix_blocks(len(drink_ids), pdf.epw)):
        if n:
            pdf.ln(3)
        each = min(appendix_col_width(block, pdf.epw), 40.0)
        pdf.table(
            ["Person", *[drink_names.get(drink_ids[i], drink_ids[i]) for i in block]],
            [[r[0], *[r[1 + i] for i in block]] for r in rows],
            widths=[APPENDIX_FIRST_COL] + [each] * len(block),
        )

    return bytes(pdf.output())

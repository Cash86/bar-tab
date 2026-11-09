from dataclasses import replace
from datetime import UTC, datetime
from io import BytesIO

from pypdf import PdfReader

from bartab.domain.settlement import BookingIn, DrinkLine, PersonLine, Settlement, StockIn
from bartab.reports.settlement_pdf import (
    APPENDIX_FIRST_COL,
    appendix_blocks,
    appendix_col_width,
    render_settlement_pdf,
)

T = datetime(2026, 10, 5, 12, 0, tzinfo=UTC)


def make(no_price=False) -> Settlement:
    beer = DrinkLine("d1", "Pils", "g1", 10, 5, 7, 8, 6, 2, 120, True)
    cola = DrinkLine("d2", "Spezi", "g2", 4, 0, 1, 3, 3, 0, 0, not no_price)
    groups = {
        "g1": DrinkLine("", "Bier", "g1", 10, 5, 7, 8, 6, 2, 120, True),
        "g2": DrinkLine("", "Softdrinks", "g2", 4, 0, 1, 3, 3, 0, 0, not no_price),
    }
    return Settlement(
        period_id="per1",
        started_at=datetime(2026, 10, 1, tzinfo=UTC),
        ended_at=datetime(2026, 11, 1, tzinfo=UTC),
        valuation_tier_id="t1",
        valuation_tier_name="Aktive",
        persons=[PersonLine("p1", "Jörg Beispiel", "t1", {"g1": 7, "g2": 1}, 123456)],
        hidden=[PersonLine("p3", "Fass", "t1", {"g1": 1}, 150)],
        drinks=[beer, cola],
        group_totals=groups,
        persons_total_cents=123456,
        hidden_total_cents=150,
        grand_total_cents=123606,
        shrinkage_total_cents=120,
        deliveries=[StockIn("d1", "delivery", 5, T, None)],
        cancelled_deliveries=[StockIn("d1", "delivery", 2, T, T)],
        cancelled_bookings=[BookingIn("p1", "d1", 1, 150, T, T, False)],
        person_drink={"p1": {"d1": 7, "d2": 1}, "p3": {"d1": 1}},
        tier_names={"t1": "Aktive", "t2": "Gäste"},
    )


def text_of(pdf: bytes) -> str:
    assert pdf.startswith(b"%PDF")
    return "\n".join(p.extract_text() for p in PdfReader(BytesIO(pdf)).pages)


def test_pdf_contains_totals_and_umlauts():
    text = text_of(render_settlement_pdf(make(), "Europe/Berlin"))
    assert "Jörg Beispiel" in text
    assert "1.236,06 €" in text
    assert "Aktive" in text
    assert "Pils" in text


def test_pdf_marks_drink_without_price():
    text = text_of(render_settlement_pdf(make(no_price=True), "Europe/Berlin"))
    assert "kein Preis" in text


def test_pdf_without_marker_when_all_priced():
    text = text_of(render_settlement_pdf(make(), "Europe/Berlin"))
    assert "kein Preis" not in text


def test_pdf_value_and_marker_do_not_merge():
    text = text_of(render_settlement_pdf(make(no_price=True), "Europe/Berlin"))
    assert "00,00" not in text
    assert "0,00 €" in text


def test_pdf_headings_use_tier_names_not_ids():
    s = make()
    guest = PersonLine("p2", "Gast Muster", "t2-uuid", {"g1": 1}, 200)
    s = replace(
        s,
        persons=[*s.persons, guest],
        tier_names={"t1": "Aktive", "t2-uuid": "Gäste"},
    )
    text = text_of(render_settlement_pdf(s, "Europe/Berlin"))
    assert "Preisstufe Aktive" in text
    assert "Preisstufe Gäste" in text
    assert "t2-uuid" not in text


def test_pdf_with_many_drinks_renders():
    s = make()
    drinks = [replace(s.drinks[0], drink_id=f"d{i}", name=f"Getränk Nummer {i}") for i in range(15)]
    s = replace(s, drinks=drinks, person_drink={"p1": {d.drink_id: 1 for d in drinks}})
    text = text_of(render_settlement_pdf(s, "Europe/Berlin"))
    assert "Jörg Beispiel" in text


def test_pdf_appendix_with_25_drinks_fits_the_page():
    s = make()
    drinks = [replace(s.drinks[0], drink_id=f"d{i}", name=f"Drink{i:02d}") for i in range(25)]
    s = replace(s, drinks=drinks, person_drink={"p1": {d.drink_id: 1 for d in drinks}})
    text = text_of(render_settlement_pdf(s, "Europe/Berlin"))
    for d in drinks:
        assert d.name in text

    epw = 297 - 2 * 12
    blocks = appendix_blocks(len(drinks), epw)
    assert len(blocks) > 1
    assert sorted(i for b in blocks for i in b) == list(range(25))
    for block in blocks:
        assert APPENDIX_FIRST_COL + len(block) * appendix_col_width(block, epw) <= epw + 1e-6

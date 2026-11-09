from dataclasses import replace
from datetime import UTC, datetime

from bartab.domain.settlement import DrinkLine, PersonLine, Settlement
from bartab.reports.money import format_cents
from bartab.reports.texts import monthly_mail, settlement_mail


def test_format_cents():
    assert format_cents(150) == "1,50 €"
    assert format_cents(-80) == "−0,80 €"
    assert format_cents(0) == "0,00 €"
    assert format_cents(123456) == "1.234,56 €"
    assert format_cents(-123456) == "−1.234,56 €"
    assert format_cents(100000000) == "1.000.000,00 €"


def make_settlement(preview=False) -> Settlement:
    counted, shrink, value = (None, None, 0) if preview else (6, 2, 120)
    beer = DrinkLine("d1", "Pils", "g1", 10, 5, 7, 8, counted, shrink, value, True)
    group = DrinkLine("", "Bier", "g1", 10, 5, 7, 8, counted, shrink, value, True)
    anna = PersonLine("p1", "Anna", "t1", {"g1": 7}, 1050)
    return Settlement(
        period_id="per1",
        started_at=datetime(2026, 10, 1, 10, 0, tzinfo=UTC),
        ended_at=datetime(2026, 11, 1, 23, 30, tzinfo=UTC),
        valuation_tier_id="t1",
        valuation_tier_name="Aktive",
        persons=[anna],
        hidden=[PersonLine("p3", "Fass", "t1", {"g1": 1}, 150)],
        drinks=[beer],
        group_totals={"g1": group},
        persons_total_cents=1050,
        hidden_total_cents=150,
        grand_total_cents=1200,
        shrinkage_total_cents=0 if preview else 120,
        deliveries=[],
        cancelled_deliveries=[],
        cancelled_bookings=[],
        person_drink={"p1": {"d1": 7}, "p3": {"d1": 1}},
        tier_names={"t1": "Aktive"},
    )


def test_settlement_mail_subject_and_totals():
    subject, body = settlement_mail(make_settlement(), "Europe/Berlin")
    # 2026-11-01 23:30 UTC is already 2 November in Berlin
    assert subject == "bar-tab: Abrechnung 01.10.2026 – 02.11.2026"
    assert "10,50 €" in body
    assert "1,50 €" in body
    assert "12,00 €" in body
    assert "1,20 €" in body


def test_monthly_mail_overdue_line_first():
    subject, body = monthly_mail(make_settlement(True), 12, "November 2026")
    assert subject == "bar-tab: Zwischenstand November 2026"
    assert body.splitlines()[0] == "Inventur überfällig seit 12 Tagen"
    assert "Zwischenstand, keine Abrechnung" in body
    assert "Anna" in body
    assert "Pils" in body
    assert "10,50 €" in body
    assert "8" in body


def test_monthly_mail_without_overdue_line():
    _, body = monthly_mail(make_settlement(True), None, "November 2026")
    assert "überfällig" not in body
    assert body.splitlines()[0] == "Zwischenstand, keine Abrechnung"


def test_monthly_mail_names_sold_out_inactive_drink():
    s = make_settlement(True)
    s = replace(
        s,
        person_drink={"p1": {"d1": 7, "d9": 1}, "p3": {"d1": 1}},
        drink_names={"d1": "Pils", "d9": "Winterbock"},
    )
    _, body = monthly_mail(s, None, "November 2026")
    assert "1 × Winterbock" in body
    assert "d9" not in body

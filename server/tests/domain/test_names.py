import pytest

from bartab.domain.names import InvalidName, clean_name, name_key


def test_clean_name_trims():
    assert clean_name("  Pils  ", 24) == "Pils"


def test_clean_name_accepts_exact_max_length():
    assert clean_name("x" * 20, 20) == "x" * 20


def test_clean_name_rejects_too_long():
    with pytest.raises(InvalidName):
        clean_name("x" * 21, 20)


def test_clean_name_counts_code_points():
    name = "Ötti-Äpfel-Übermaß-2"
    assert len(name) == 20
    assert clean_name(name, 20) == name


def test_clean_name_rejects_blank():
    with pytest.raises(InvalidName):
        clean_name("   ", 20)


def test_name_key_casefolds():
    assert name_key("STRASSE") == name_key("straße")
    assert name_key("Ä") == name_key("ä")
    assert name_key(" Pils ") == "pils"

import pytest

from bartab.domain.legacy import (
    PLACEHOLDER_CENTS,
    LegacyError,
    build_plan,
    decode_legacy,
    euro_to_cents,
    parse_mapping,
    prettify,
)

USERS = "Name,Rolle\nKim Beispiel,Aktiv\nJörg Muster,AH\nGeist Eins,hidden\nKasse Eins,Aktiv\n"
DRINKS = (
    "Sorte,Gruppe,Aktivenpreis,Altherrenpreis,Kastengröße\n"
    "bier_hell,Bier,1.2,1.5,20\n"
    "oetti_cola,Limo,0.55,0.8,12\n"
    "fass_a,hidden,1.5,1.5,1\n"
    "altes_zeug,hidden,0.5,0.7,10\n"
    "teuer,Limo,10000,10000,6\n"
)


def mapping_data(**changes):
    data = {
        "tiers": {"Aktiv": "Aktive", "AH": "Alte"},
        "hidden_tier": "AH",
        "collective": ["Kasse Eins"],
        "groups": {
            "bier_hell": "Bier",
            "oetti_cola": "Limo",
            "fass_a": "Bier",
            "altes_zeug": "Limo",
            "teuer": "Limo",
        },
        "group_order": ["Bier", "Limo"],
        "kegs": ["fass_a"],
        "rename": {"fass_a": "Fass Alpha"},
        "word_replacements": {"Oetti": "Ötti"},
        "price_overrides": {"fass_a": {"Aktiv": 4500, "AH": 4500}},
        "extra_drinks": [
            {"name": "Malz", "group": "Limo", "crate_size": 20, "prices": {"Aktiv": 60, "AH": 120}}
        ],
    }
    data.update(changes)
    return data


def plan(users=USERS, drinks=DRINKS, **changes):
    return build_plan(users, drinks, parse_mapping(mapping_data(**changes)))


def test_reads_cp1252_crlf():
    raw = "Sorte,Kastengröße\r\nÖtti,1\r\n".encode("cp1252")
    assert decode_legacy(raw) == "Sorte,Kastengröße\nÖtti,1\n"


def test_prettify_with_replacements_and_rename():
    m = parse_mapping(mapping_data())
    assert prettify("oetti_cola", m) == "Ötti Cola"
    assert prettify("fass_a", m) == "Fass Alpha"
    assert prettify("bier_hell", m) == "Bier Hell"


@pytest.mark.parametrize(
    ("text", "cents"), [("1.2", 120), ("0.55", 55), ("144.28", 14428), ("3", 300), ("0", 0)]
)
def test_euro_to_cents_exact(text, cents):
    assert euro_to_cents(text) == cents


@pytest.mark.parametrize("text", ["1.234", "abc", "", "-1", "1,5"])
def test_euro_to_cents_rejects_junk(text):
    with pytest.raises(LegacyError):
        euro_to_cents(text)


def test_placeholder_price_becomes_zero_and_is_reported():
    p = plan()
    teuer = next(d for d in p.drinks if d.name == "Teuer")
    assert teuer.prices == {"Aktive": 0, "Alte": 0}
    assert PLACEHOLDER_CENTS == 1_000_000
    assert any("Teuer" in line and "placeholder" in line for line in p.report)


def test_roles_map_to_tiers_and_hidden_tier():
    p = plan()
    assert p.tiers == ["Aktive", "Alte"]
    by_name = {x.name: x for x in p.persons}
    assert by_name["Kim Beispiel"].tier == "Aktive"
    assert by_name["Jörg Muster"].tier == "Alte"
    assert not by_name["Jörg Muster"].is_hidden
    assert by_name["Geist Eins"].tier == "Alte"
    assert by_name["Geist Eins"].is_hidden


def test_collective_flagged():
    by_name = {x.name: x for x in plan().persons}
    assert by_name["Kasse Eins"].is_collective
    assert not by_name["Kim Beispiel"].is_collective


@pytest.mark.parametrize(
    "change",
    [
        {"collective": ["Nobody"]},
        {"kegs": ["nope"]},
        {"rename": {"nope": "X"}},
        {"price_overrides": {"nope": {"Aktiv": 1}}},
    ],
)
def test_unknown_mapping_name_aborts(change):
    with pytest.raises(LegacyError):
        plan(**change)


def test_unknown_group_name_in_mapping_aborts():
    groups = mapping_data()["groups"] | {"nope": "Bier"}
    with pytest.raises(LegacyError, match="nope"):
        plan(groups=groups)


def test_unknown_role_aborts():
    with pytest.raises(LegacyError, match="Chef"):
        plan(users="Name,Rolle\nKim Beispiel,Chef\n")


def test_drink_without_group_aborts():
    groups = mapping_data()["groups"]
    del groups["bier_hell"]
    with pytest.raises(LegacyError, match="bier_hell"):
        plan(groups=groups)


def test_group_missing_in_group_order_aborts():
    with pytest.raises(LegacyError, match="Limo"):
        plan(group_order=["Bier"])


def test_keg_not_hidden_and_hidden_drink_hidden():
    by_name = {d.name: d for d in plan().drinks}
    assert by_name["Fass Alpha"].is_keg
    assert not by_name["Fass Alpha"].is_hidden
    assert by_name["Altes Zeug"].is_hidden
    assert not by_name["Altes Zeug"].is_keg
    assert not by_name["Bier Hell"].is_hidden


def test_price_columns_follow_tier_order():
    by_name = {d.name: d for d in plan().drinks}
    assert by_name["Bier Hell"].prices == {"Aktive": 120, "Alte": 150}
    assert by_name["Bier Hell"].crate_size == 20


def test_price_overrides_win():
    by_name = {d.name: d for d in plan().drinks}
    assert by_name["Fass Alpha"].prices == {"Aktive": 4500, "Alte": 4500}


def test_extra_drink_appended():
    p = plan()
    last = p.drinks[-1]
    assert (last.name, last.group, last.crate_size) == ("Malz", "Limo", 20)
    assert last.prices == {"Aktive": 60, "Alte": 120}
    assert [d.name for d in p.drinks][:2] == ["Bier Hell", "Ötti Cola"]
    assert p.groups == ["Bier", "Limo"]


def test_too_long_name_aborts_and_collects_all_problems():
    users = "Name,Rolle\n" + "x" * 21 + ",Aktiv\nKim Beispiel,Chef\n"
    with pytest.raises(LegacyError) as err:
        plan(users=users)
    assert "x" * 21 in str(err.value)
    assert "Chef" in str(err.value)


def test_bad_header_aborts():
    with pytest.raises(LegacyError):
        plan(users="Name,Rolle,Extra\nA,Aktiv\n")


def test_parse_mapping_rejects_unknown_key():
    with pytest.raises(LegacyError, match="bogus"):
        parse_mapping(mapping_data(bogus=1))


def test_parse_mapping_rejects_wrong_type():
    with pytest.raises(LegacyError):
        parse_mapping(mapping_data(kegs="fass_a"))


def test_duplicate_tier_names_abort():
    with pytest.raises(LegacyError, match="duplicate tier"):
        plan(tiers={"Aktiv": "Aktive", "AH": "aktive"})


def test_duplicate_group_order_aborts():
    with pytest.raises(LegacyError, match="duplicate group"):
        plan(group_order=["Bier", "Limo", "Bier"])


def test_error_lines_are_real_file_lines():
    users = "Name,Rolle\n\nKim Beispiel,Aktiv\nKaputt,Aktiv,Extra\n"
    with pytest.raises(LegacyError, match=r"user\.csv line 4"):
        plan(users=users)


def test_euro_to_cents_rejects_non_ascii_digits():
    with pytest.raises(LegacyError):
        euro_to_cents("١.٢")


def test_decode_strips_utf8_bom():
    assert decode_legacy(b"\xef\xbb\xbfName,Rolle\n") == "Name,Rolle\n"


def test_bom_in_both_files_is_harmless():
    users = b"\xef\xbb\xbf" + USERS.encode("cp1252")
    drinks = b"\xef\xbb\xbf" + DRINKS.encode("cp1252")
    p = build_plan(decode_legacy(users), decode_legacy(drinks), parse_mapping(mapping_data()))
    assert len(p.persons) == 4
    assert len(p.drinks) == 6


def test_trailing_blank_lines_are_ignored():
    p = plan(users=USERS + "\n\n", drinks=DRINKS + "\r\n\r\n")
    assert len(p.persons) == 4
    assert len(p.drinks) == 6


@pytest.mark.parametrize("price", ["1.", "1,20"])
def test_drink_csv_rejects_malformed_price(price):
    drinks = DRINKS.replace("bier_hell,Bier,1.2,1.5", f'bier_hell,Bier,"{price}",1.5')
    with pytest.raises(LegacyError, match="bier_hell"):
        plan(drinks=drinks)


def test_hidden_collective_person_keeps_both_flags():
    p = plan(collective=["Geist Eins"])
    ghost = next(x for x in p.persons if x.name == "Geist Eins")
    assert ghost.is_hidden
    assert ghost.is_collective


def test_person_rename_applies_and_is_reported():
    p = plan(person_rename={"Kim Beispiel": "Kim B."})
    assert [x.name for x in p.persons][0] == "Kim B."
    assert "renamed person 'Kim Beispiel' to 'Kim B.'" in p.report


def test_person_rename_fixes_too_long_name():
    long_name = "Maximilian Beispielmann-Muster"
    users = USERS + f"{long_name},Aktiv\n"
    with pytest.raises(LegacyError, match="longer"):
        plan(users=users)
    p = plan(users=users, person_rename={long_name: "Max Beispielmann"})
    assert "Max Beispielmann" in [x.name for x in p.persons]


def test_collective_uses_legacy_name_even_if_renamed():
    p = plan(person_rename={"Kasse Eins": "Kasse"})
    kasse = next(x for x in p.persons if x.name == "Kasse")
    assert kasse.is_collective


def test_person_rename_unknown_key_aborts():
    with pytest.raises(LegacyError, match="person_rename 'Nobody'"):
        plan(person_rename={"Nobody": "X"})


def test_person_rename_to_duplicate_aborts():
    with pytest.raises(LegacyError, match="duplicate person"):
        plan(person_rename={"Kim Beispiel": "Jörg Muster"})


def test_placeholder_report_skipped_for_overridden_role():
    p = plan(price_overrides={"teuer": {"Aktiv": 100, "AH": 200}})
    teuer = next(d for d in p.drinks if d.name == "Teuer")
    assert teuer.prices == {"Aktive": 100, "Alte": 200}
    assert not any("Teuer" in line and "placeholder" in line for line in p.report)


def test_placeholder_report_kept_for_role_without_override():
    p = plan(price_overrides={"teuer": {"Aktiv": 100}})
    lines = [line for line in p.report if "Teuer" in line and "placeholder" in line]
    assert len(lines) == 1
    assert "AH" in lines[0]


@pytest.mark.parametrize("cents", [-1, PLACEHOLDER_CENTS, PLACEHOLDER_CENTS + 1])
def test_override_price_out_of_range_aborts(cents):
    with pytest.raises(LegacyError, match="price_overrides"):
        parse_mapping(mapping_data(price_overrides={"fass_a": {"Aktiv": cents}}))


def test_extra_drink_price_out_of_range_aborts():
    prices = {"Aktiv": PLACEHOLDER_CENTS}
    extra = {"name": "Malz", "group": "Limo", "crate_size": 20, "prices": prices}
    with pytest.raises(LegacyError, match="extra_drinks"):
        parse_mapping(mapping_data(extra_drinks=[extra]))


def test_renames_are_stripped():
    p = plan(person_rename={"Kim Beispiel": "  Kim B. "}, rename={"fass_a": " Fass Alpha "})
    assert "Kim B." in [x.name for x in p.persons]
    assert "Fass Alpha" in [d.name for d in p.drinks]


@pytest.mark.parametrize("key", ["person_rename", "rename"])
def test_blank_rename_aborts(key):
    legacy = "Kim Beispiel" if key == "person_rename" else "fass_a"
    with pytest.raises(LegacyError, match=key):
        parse_mapping(mapping_data(**{key: {legacy: "   "}}))

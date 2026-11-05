import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog.freezed.dart';

@freezed
abstract class PriceTier with _$PriceTier {
  const factory PriceTier({
    required String id,
    required String name,
    required int sortOrder,
  }) = _PriceTier;
}

@freezed
abstract class Person with _$Person {
  const factory Person({
    required String id,
    required String name,
    required String priceTierId,
    required bool isHidden,
    required bool isCollective,
    required bool isActive,
  }) = _Person;
}

@freezed
abstract class DrinkGroup with _$DrinkGroup {
  const factory DrinkGroup({
    required String id,
    required String name,
    required int sortOrder,

    /// ARGB colour value.
    required int color,
  }) = _DrinkGroup;
}

@freezed
abstract class Drink with _$Drink {
  const factory Drink({
    required String id,
    required String name,
    required String groupId,
    required int crateSize,
    required int sortOrder,
    required bool isHidden,
    required bool isActive,

    /// Price tier id to price in cents.
    required Map<String, int> prices,
  }) = _Drink;
}

/// Sort key: lowercase, umlauts as their base letter, ß as ss.
String _fold(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss');

/// Folded name, then raw name.
int _compareNames(String a, String b) {
  final c = _fold(a).compareTo(_fold(b));
  return c != 0 ? c : a.compareTo(b);
}

int _byNameThenId(Person a, Person b) {
  final c = _compareNames(a.name, b.name);
  return c != 0 ? c : a.id.compareTo(b.id);
}

@freezed
abstract class Catalog with _$Catalog {
  const factory Catalog({
    required List<PriceTier> tiers,
    required List<Person> persons,
    required List<DrinkGroup> groups,
    required List<Drink> drinks,
    required String etag,
  }) = _Catalog;

  const Catalog._();

  /// Every person, including hidden, inactive and collective ones, by name
  /// then id.
  List<Person> allPersonsByName() => [...persons]..sort(_byNameThenId);

  bool _isVisible(Person p) => p.isActive && !p.isHidden;

  /// Active, visible collective accounts, ordered by name.
  List<Person> collectiveAccounts() =>
      persons.where((p) => _isVisible(p) && p.isCollective).toList()
        ..sort(_byNameThenId);

  /// Visible, non-collective persons per tier; tiers by sort order, empty
  /// tiers omitted, persons by name then id.
  List<(PriceTier, List<Person>)> personsByTier() {
    final sortedTiers = [...tiers]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final result = <(PriceTier, List<Person>)>[];
    for (final tier in sortedTiers) {
      final members =
          persons
              .where(
                (p) =>
                    _isVisible(p) &&
                    !p.isCollective &&
                    p.priceTierId == tier.id,
              )
              .toList()
            ..sort(_byNameThenId);
      if (members.isNotEmpty) result.add((tier, members));
    }
    return result;
  }

  /// Orderable drinks for [p] per group; groups by sort order, empty groups
  /// omitted, drinks by sort order then name.
  List<(DrinkGroup, List<Drink>)> drinksFor(Person p) {
    final sortedGroups = [...groups]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final result = <(DrinkGroup, List<Drink>)>[];
    for (final group in sortedGroups) {
      final inGroup =
          drinks
              .where(
                (d) =>
                    d.groupId == group.id &&
                    d.isActive &&
                    !d.isHidden &&
                    d.prices.containsKey(p.priceTierId),
              )
              .toList()
            ..sort((a, b) {
              final c = a.sortOrder.compareTo(b.sortOrder);
              if (c != 0) return c;
              final n = _compareNames(a.name, b.name);
              return n != 0 ? n : a.id.compareTo(b.id);
            });
      if (inGroup.isNotEmpty) result.add((group, inGroup));
    }
    return result;
  }

  /// Price of [d] in cents for [p]'s tier, or null if not offered.
  int? priceFor(Drink d, Person p) => d.prices[p.priceTierId];
}

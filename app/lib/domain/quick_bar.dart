import 'catalog.dart';
import 'rankings.dart';

const kQuickBarSize = 4;

/// The drinks for a person's quick bar: their own most-booked drinks first,
/// then the overall most-booked ones. Only drinks the person can book appear.
List<Drink> quickBarDrinks(
  Catalog catalog,
  Person person,
  DrinkRankings? rankings, {
  int size = kQuickBarSize,
}) {
  if (rankings == null) return const [];
  final candidates = [
    for (final (_, drinks) in catalog.drinksFor(person)) ...drinks,
  ];
  final gridIndex = {for (final (i, d) in candidates.indexed) d.id: i};

  List<Drink> ranked(Map<String, int> counts) {
    final list = [
      for (final d in candidates)
        if ((counts[d.id] ?? 0) > 0) d,
    ];
    list.sort((a, b) {
      final c = counts[b.id]!.compareTo(counts[a.id]!);
      return c != 0 ? c : gridIndex[a.id]!.compareTo(gridIndex[b.id]!);
    });
    return list;
  }

  final own = ranked(rankings.persons[person.id] ?? const {});
  final ownIds = {for (final d in own) d.id};
  final rest = ranked(rankings.overall).where((d) => !ownIds.contains(d.id));
  return [...own, ...rest].take(size).toList();
}

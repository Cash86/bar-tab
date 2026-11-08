const maxPersonName = 20,
    maxDrinkName = 24,
    maxGroupName = 16,
    maxTierName = 16;

/// Trimmed name, or null when empty or longer than [max] (counted in runes).
String? cleanName(String raw, int max) {
  final name = raw.trim();
  if (name.isEmpty || name.runes.length > max) return null;
  return name;
}

/// Whether [name] equals another entry's name, ignoring case and surrounding
/// spaces. The server's casefold comparison is authoritative.
bool nameTaken(
  String name,
  Iterable<({String id, String name})> others, {
  String? exceptId,
}) {
  final wanted = name.trim().toLowerCase();
  return others.any(
    (o) => o.id != exceptId && o.name.trim().toLowerCase() == wanted,
  );
}

/// Single units for [crates] full crates plus loose [units].
int unitsOf({
  required int crates,
  required int units,
  required int crateSize,
}) => crates * crateSize + units;

/// Colours offered for drink groups, as '#RRGGBB'. Task 10 fills it.
const groupPalette = <String>[];

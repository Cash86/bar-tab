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

/// Colours offered for drink groups, as '#RRGGBB'. Saturated mid-tones with a
/// WCAG contrast of at least 3.0 against cream (#F3E7CF), the bottle green
/// (#16302A) and the chalkboard (#232724), so the group colour stays readable
/// on all three designs.
const groupPalette = <String>[
  '#EA1313', // red
  '#B1600E', // amber
  '#7B7B0A', // olive
  '#47840B', // lime green
  '#0B890B', // green
  '#0B894A', // emerald
  '#0B8484', // teal
  '#1275D9', // blue
  '#6363F2', // indigo
  '#9C47F0', // violet
  '#CD11CD', // magenta
  '#E2127A', // pink
];

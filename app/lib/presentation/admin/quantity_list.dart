import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/catalog.dart';
import '../../domain/master_data.dart' as md;
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../drinks/keypad.dart';

const int _maxDigits = 4;

/// Crates and loose units per drink id, edited with one shared keypad.
class QuantityLines extends ChangeNotifier {
  /// With [maxLineUnits] and [crateSizeOf], a digit that would take a line's
  /// total above [maxLineUnits] single units is ignored; without them only
  /// the digit count of a field is limited.
  QuantityLines({this.maxLineUnits, this.crateSizeOf});

  final int? maxLineUnits;
  final int Function(String drinkId)? crateSizeOf;

  final Map<String, int> _crates = {};
  final Map<String, int> _units = {};
  String? _selected;
  bool _crateFocus = true;

  /// The drink whose field the keypad edits, if any.
  String? get selected => _selected;

  /// Whether the keypad edits the crates field (else the units field).
  bool get crateFocused => _crateFocus;

  int cratesOf(String drinkId) => _crates[drinkId] ?? 0;
  int unitsOf(String drinkId) => _units[drinkId] ?? 0;

  /// Whether a value was typed for [drinkId]; an entered 0 counts, a drink
  /// that was only selected does not.
  bool hasEntry(String drinkId) =>
      _crates.containsKey(drinkId) || _units.containsKey(drinkId);

  /// Whether no value was typed for any drink.
  bool get isEmpty => _crates.isEmpty && _units.isEmpty;

  /// Selects [drinkId]; the crates field is focused first, the units field
  /// when the drink has no crates.
  void select(String drinkId, {bool hasCrates = true}) {
    _selected = drinkId;
    _crateFocus = hasCrates;
    notifyListeners();
  }

  void focusCrates(bool on) {
    _crateFocus = on;
    notifyListeners();
  }

  void digit(int d) {
    final id = _selected;
    if (id == null) return;
    final map = _crateFocus ? _crates : _units;
    final current = map[id] ?? 0;
    if ('$current'.length >= _maxDigits && current > 0) return;
    final next = current * 10 + d;
    final cap = maxLineUnits;
    final sizeOf = crateSizeOf;
    if (cap != null && sizeOf != null) {
      final total = md.unitsOf(
        crates: _crateFocus ? next : cratesOf(id),
        units: _crateFocus ? unitsOf(id) : next,
        crateSize: sizeOf(id),
      );
      if (total > cap) return;
    }
    map[id] = next;
    notifyListeners();
  }

  void backspace() {
    final id = _selected;
    if (id == null) return;
    final map = _crateFocus ? _crates : _units;
    map[id] = (map[id] ?? 0) ~/ 10;
    notifyListeners();
  }

  /// Entered counts per drink id; a drink with an entered 0 keeps its key.
  Map<String, dynamic> toJson() => {
    'crates': {..._crates},
    'units': {..._units},
  };

  /// Replaces all counts with those of [json] (see [toJson]).
  void restore(Map<String, dynamic> json) {
    Map<String, int> read(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value is int) e.key as String: e.value as int,
    };
    _crates
      ..clear()
      ..addAll(read(json['crates']));
    _units
      ..clear()
      ..addAll(read(json['units']));
    notifyListeners();
  }

  /// Drink id to single units, only where more than zero.
  Map<String, int> totals(Map<String, int> crateSizes) {
    final ids = {..._crates.keys, ..._units.keys};
    final result = <String, int>{};
    for (final id in ids) {
      final size = crateSizes[id];
      if (size == null) continue;
      final total = md.unitsOf(
        crates: cratesOf(id),
        units: unitsOf(id),
        crateSize: size,
      );
      if (total > 0) result[id] = total;
    }
    return result;
  }
}

/// Active drinks (hidden ones included) by group with a crates and a units
/// field each and a side panel with the keypad.
class QuantityList extends StatelessWidget {
  const QuantityList({
    super.key,
    required this.drinks,
    required this.groups,
    required this.lines,
    this.trailing,
  });

  final List<Drink> drinks;
  final List<DrinkGroup> groups;
  final QuantityLines lines;

  /// Extra text after a row's total, e.g. its amount; shown for units > 0.
  final String Function(Drink drink, int units)? trailing;

  @override
  Widget build(BuildContext context) {
    final sortedGroups = [...groups]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final byId = {for (final d in drinks) d.id: d};
    return ListenableBuilder(
      listenable: lines,
      builder: (context, _) => Row(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [for (final g in sortedGroups) ..._section(context, g)],
            ),
          ),
          SizedBox(
            width: 300,
            child: _Panel(lines: lines, drink: byId[lines.selected]),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(BuildContext context, DrinkGroup group) {
    final tokens = DesignTokens.of(context);
    final shown = [
      for (final d in drinks)
        if (d.groupId == group.id && d.isActive) d,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (shown.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(
          group.name,
          style: TextStyle(color: tokens.muted, fontSize: 18),
        ),
      ),
      for (final d in shown) _Row(drink: d, lines: lines, trailing: trailing),
    ];
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.drink,
    required this.lines,
    required this.trailing,
  });

  final Drink drink;
  final QuantityLines lines;
  final String Function(Drink, int)? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final selected = lines.selected == drink.id;
    final hasCrate = drink.crateSize > 1;
    final units = md.unitsOf(
      crates: lines.cratesOf(drink.id),
      units: lines.unitsOf(drink.id),
      crateSize: drink.crateSize,
    );
    final extra = trailing;
    return Material(
      key: Key('qty-row-${drink.id}'),
      color: selected ? tokens.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => lines.select(drink.id, hasCrates: hasCrate),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  drink.name,
                  style: TextStyle(color: tokens.text, fontSize: 22),
                ),
              ),
              if (hasCrate) ...[
                _Field(
                  key: Key('qty-crates-${drink.id}'),
                  text: AppLocalizations.of(
                    context,
                  ).quantityCratesField(lines.cratesOf(drink.id)),
                  focused: selected && lines.crateFocused,
                  onTap: () => lines.select(drink.id),
                ),
                const SizedBox(width: 8),
              ],
              _Field(
                key: Key('qty-units-${drink.id}'),
                text: '${lines.unitsOf(drink.id)}',
                focused: selected && !(hasCrate && lines.crateFocused),
                onTap: () => lines.select(drink.id, hasCrates: false),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  '= $units',
                  key: Key('qty-total-${drink.id}'),
                  textAlign: TextAlign.end,
                  style: TextStyle(color: tokens.text, fontSize: 22),
                ),
              ),
              if (extra != null)
                Container(
                  constraints: const BoxConstraints(minWidth: 110),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    units > 0 ? extra(drink, units) : '',
                    softWrap: false,
                    style: TextStyle(color: tokens.muted, fontSize: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.text,
    required this.focused,
    required this.onTap,
  });

  final String text;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          border: Border.all(
            color: focused ? tokens.accent : tokens.muted.withAlpha(90),
            width: focused ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(color: tokens.text, fontSize: 22)),
      ),
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({required this.lines, required this.drink});

  final QuantityLines lines;
  final Drink? drink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drink = this.drink;
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    if (drink == null) {
      return Center(
        child: Text(
          l10n.quantityHint,
          key: const Key('qty-hint'),
          style: TextStyle(color: tokens.muted, fontSize: 18),
        ),
      );
    }
    final hasCrate = drink.crateSize > 1;
    final crateFocus = hasCrate && lines.crateFocused;
    Widget chip(Key key, String label, int n, bool focused, bool crates) {
      return Expanded(
        child: InkWell(
          key: key,
          onTap: () => lines.focusCrates(crates),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: focused ? tokens.accent : tokens.muted.withAlpha(90),
                width: focused ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$label: $n',
              style: TextStyle(color: tokens.text, fontSize: 18),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(drink.name, style: TextStyle(color: tokens.text, fontSize: 24)),
          if (hasCrate)
            Text(
              l10n.quantityCrateSize(drink.crateSize),
              style: TextStyle(color: tokens.muted, fontSize: 16),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (hasCrate) ...[
                chip(
                  const Key('qty-chip-crates'),
                  l10n.quantityCrates,
                  lines.cratesOf(drink.id),
                  crateFocus,
                  true,
                ),
                const SizedBox(width: 8),
              ],
              chip(
                const Key('qty-chip-units'),
                l10n.quantitySingles,
                lines.unitsOf(drink.id),
                !crateFocus,
                false,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Keypad(
              crateLabel: null,
              design: ref.watch(appDesignProvider),
              onDigit: lines.digit,
              onCrate: () {},
              onBackspace: lines.backspace,
            ),
          ),
        ],
      ),
    );
  }
}

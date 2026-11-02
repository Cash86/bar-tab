import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../common/sync_indicator.dart';
import '../drinks/drink_selection_screen.dart';
import '../providers.dart';
import '../theme.dart';
import 'name_tile.dart';

const double _gap = 8;
const double _columnTitleHeight = 32;

/// How a tier column lays out its name tiles.
class NameGridLayout {
  const NameGridLayout({
    required this.perRow,
    required this.tileHeight,
    required this.scrolls,
  });

  final int perRow;
  final double tileHeight;
  final bool scrolls;

  @override
  bool operator ==(Object other) =>
      other is NameGridLayout &&
      other.perRow == perRow &&
      other.tileHeight == tileHeight &&
      other.scrolls == scrolls;

  @override
  int get hashCode => Object.hash(perRow, tileHeight, scrolls);

  @override
  String toString() =>
      'NameGridLayout($perRow per row, $tileHeight high, scrolls: $scrolls)';
}

double _gridHeight(int names, int perRow, double tileHeight) {
  if (names == 0) return 0;
  final rows = (names + perRow - 1) ~/ perRow;
  return rows * tileHeight + (rows - 1) * _gap;
}

/// 3 per row at 64 high; if the tallest column does not fit
/// [availableHeight], 4 per row at 52 high; if it still does not fit, the
/// columns scroll (keeping the compact size).
NameGridLayout chooseLayout({
  required int maxNamesInColumn,
  required double availableHeight,
}) {
  const roomy = NameGridLayout(perRow: 3, tileHeight: 64, scrolls: false);
  const compact = NameGridLayout(perRow: 4, tileHeight: 52, scrolls: false);
  for (final l in [roomy, compact]) {
    if (_gridHeight(maxNamesInColumn, l.perRow, l.tileHeight) <=
        availableHeight) {
      return l;
    }
  }
  return const NameGridLayout(perRow: 4, tileHeight: 52, scrolls: true);
}

class NameListScreen extends ConsumerWidget {
  const NameListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(catalogProvider).value;
    final collective = catalog?.collectiveAccounts() ?? const <Person>[];
    final tiers = catalog?.personsByTier() ?? const [];
    final isEmpty = collective.isEmpty && tiers.isEmpty;

    void open(Person p) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DrinkSelectionScreen(personId: p.id),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.nameListTitle,
                style: const TextStyle(
                  color: BarTabTheme.paper,
                  fontSize: 30,
                  height: 1.2,
                  fontVariations: [
                    FontVariation('wdth', 118),
                    FontVariation('wght', 850),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.nameListEmpty,
                      style: const TextStyle(
                        color: BarTabTheme.muted,
                        fontSize: 20,
                      ),
                    ),
                  ),
                )
              else ...[
                if (collective.isNotEmpty) ...[
                  _CollectiveRow(accounts: collective, onTap: open),
                  const SizedBox(height: 16),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = chooseLayout(
                        maxNamesInColumn: tiers.fold(
                          0,
                          (m, t) => t.$2.length > m ? t.$2.length : m,
                        ),
                        availableHeight:
                            constraints.maxHeight - _columnTitleHeight,
                      );
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < tiers.length; i++) ...[
                            if (i > 0) const SizedBox(width: 20),
                            Expanded(
                              child: _TierColumn(
                                title: tiers[i].$1.name,
                                accent: BarTabTheme.tierColor(i),
                                persons: tiers[i].$2,
                                layout: layout,
                                onTap: open,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(
                height: 28,
                width: double.infinity,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: SyncIndicator(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColumnTitle extends StatelessWidget {
  const _ColumnTitle(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _columnTitleHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 14,
            letterSpacing: 1.2,
            fontVariations: const [
              FontVariation('wdth', 100),
              FontVariation('wght', 750),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed row of collective accounts; never scrolls.
class _CollectiveRow extends StatelessWidget {
  const _CollectiveRow({required this.accounts, required this.onTap});

  final List<Person> accounts;
  final ValueChanged<Person> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColumnTitle(
          AppLocalizations.of(context).nameListCollective,
          BarTabTheme.collectiveAccent,
        ),
        Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final p in accounts)
              SizedBox(
                width: 200,
                child: NameTile(
                  person: p,
                  accent: BarTabTheme.collectiveAccent,
                  height: 52,
                  onTap: () => onTap(p),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TierColumn extends StatefulWidget {
  const _TierColumn({
    required this.title,
    required this.accent,
    required this.persons,
    required this.layout,
    required this.onTap,
  });

  final String title;
  final Color accent;
  final List<Person> persons;
  final NameGridLayout layout;
  final ValueChanged<Person> onTap;

  @override
  State<_TierColumn> createState() => _TierColumnState();
}

class _TierColumnState extends State<_TierColumn> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _tile(Person p) => NameTile(
    person: p,
    accent: widget.accent,
    height: widget.layout.tileHeight,
    onTap: () => widget.onTap(p),
  );

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final Widget grid;
    if (layout.scrolls) {
      grid = Stack(
        children: [
          GridView.count(
            controller: _controller,
            crossAxisCount: layout.perRow,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            mainAxisExtent: layout.tileHeight,
            padding: const EdgeInsets.only(bottom: 40),
            children: [for (final p in widget.persons) _tile(p)],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 40,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0016302A), BarTabTheme.bottle],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      final rows = <Widget>[];
      for (var i = 0; i < widget.persons.length; i += layout.perRow) {
        final chunk = widget.persons.skip(i).take(layout.perRow).toList();
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _gap),
            child: Row(
              children: [
                for (var j = 0; j < layout.perRow; j++) ...[
                  if (j > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: j < chunk.length
                        ? _tile(chunk[j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      grid = Column(children: rows);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColumnTitle(widget.title, widget.accent),
        if (layout.scrolls) Expanded(child: grid) else grid,
      ],
    );
  }
}

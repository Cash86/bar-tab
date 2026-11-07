import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/catalog.dart';
import '../../../l10n/app_localizations.dart';
import '../chalk_text.dart';
import '../design.dart';
import 'chalk_board.dart';
import 'chalk_extras.dart';

const double _columnGap = 28;
const double _boxGap = 10;
const double _headingHeight = 46;
const double _collectiveHeight = 58;
const double _collectiveWidth = 230;
const double _collectiveLabelWidth = 160;

/// A name whose fitted size is below this share of the column's median
/// size shrinks on its own instead of shrinking the column.
const double _outlierShare = 0.8;

/// How the tier columns lay out their chalk boxes.
@immutable
class ChalkNameLayout {
  const ChalkNameLayout({
    required this.perRow,
    required this.boxHeight,
    required this.scrolls,
  });

  final int perRow;
  final double boxHeight;
  final bool scrolls;

  @override
  bool operator ==(Object other) =>
      other is ChalkNameLayout &&
      other.perRow == perRow &&
      other.boxHeight == boxHeight &&
      other.scrolls == scrolls;

  @override
  int get hashCode => Object.hash(perRow, boxHeight, scrolls);

  @override
  String toString() =>
      'ChalkNameLayout($perRow per row, $boxHeight high, '
      'scrolls: $scrolls)';
}

/// Boxes as high as [availableHeight] allows for the longest column, up to
/// [maxHeight]: three per row down to [minRoomy], then four per row down to
/// [minCompact]; below that the columns scroll at [minCompact].
ChalkNameLayout planChalkNames({
  required int maxNamesInColumn,
  required double availableHeight,
  double maxHeight = 100,
  double minRoomy = 60,
  double minCompact = 50,
}) {
  double fit(int perRow) {
    final rows = math.max(1, (maxNamesInColumn + perRow - 1) ~/ perRow);
    return math.min(maxHeight, (availableHeight - (rows - 1) * _boxGap) / rows);
  }

  final roomy = fit(3);
  if (roomy >= minRoomy) {
    return ChalkNameLayout(perRow: 3, boxHeight: roomy, scrolls: false);
  }
  final compact = fit(4);
  if (compact >= minCompact) {
    return ChalkNameLayout(perRow: 4, boxHeight: compact, scrolls: false);
  }
  return ChalkNameLayout(perRow: 4, boxHeight: minCompact, scrolls: true);
}

/// The Kreidetafel name list: collective accounts in yellow chalk on top,
/// one column per price tier with its name as underlined heading, persons
/// as dashed chalk boxes. Taps are ignored while not [enabled].
class ChalkNameBoard extends StatelessWidget {
  const ChalkNameBoard({
    required this.collective,
    required this.tiers,
    required this.tierColor,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  final List<Person> collective;
  final List<(PriceTier, List<Person>)> tiers;
  final Color Function(PriceTier tier) tierColor;
  final ValueChanged<Person> onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    // The undo banner animates every frame over the board.
    return RepaintBoundary(
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (collective.isNotEmpty) ...[
              SizedBox(
                height: _collectiveHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _collectiveLabelWidth,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ChalkText(
                          AppLocalizations.of(context).nameListCollective,
                          style: chalkStyle(
                            tokens,
                            30,
                            color: tokens.accent,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ),
                    // Never wider than the board: many accounts share it.
                    for (var i = 0; i < collective.length; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _collectiveWidth,
                          ),
                          child: _CollectiveBox(
                            key: ValueKey('person-${collective[i].id}'),
                            name: collective[i].name,
                            onTap: () => onTap(collective[i]),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final layout = planChalkNames(
                    maxNamesInColumn: tiers.fold(
                      0,
                      (m, t) => math.max(m, t.$2.length),
                    ),
                    availableHeight: constraints.maxHeight - _headingHeight,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tiers.length; i++) ...[
                        if (i > 0) const SizedBox(width: _columnGap),
                        Expanded(
                          child: _TierColumn(
                            title: tiers[i].$1.name,
                            color: tierColor(tiers[i].$1),
                            persons: tiers[i].$2,
                            layout: layout,
                            onTap: onTap,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TierColumn extends StatefulWidget {
  const _TierColumn({
    required this.title,
    required this.color,
    required this.persons,
    required this.layout,
    required this.onTap,
  });

  final String title;
  final Color color;
  final List<Person> persons;
  final ChalkNameLayout layout;
  final ValueChanged<Person> onTap;

  @override
  State<_TierColumn> createState() => _TierColumnState();
}

class _TierColumnState extends State<_TierColumn> {
  /// The fitted name size and what it was fitted for: the screen rebuilds
  /// every second while the undo banner counts down.
  (Object, double)? _size;

  /// One name size for the whole column: the largest at which every name
  /// fits its box in up to two lines. A name far longer than the others
  /// does not shrink the whole column: it shrinks alone (see [_NameBox]).
  double _nameSize(BuildContext context, DesignTokens tokens, double width) {
    final layout = widget.layout;
    final names = [for (final p in widget.persons) p.name];
    final key = Object.hash(Object.hashAll(names), width, layout);
    if (_size case (final k, final size) when k == key) return size;
    final boxWidth = (width - (layout.perRow - 1) * _boxGap) / layout.perRow;
    final style = DefaultTextStyle.of(context).style.merge(
      chalkStyle(tokens, math.min(40, 0.44 * layout.boxHeight), height: 1.05),
    );
    final box = Size(
      math.max(0, boxWidth - 2 * _NameBox.padding - 1),
      layout.boxHeight - 4,
    );
    final sizes = [
      for (final name in names)
        fitChalkFontSize(
          name,
          style,
          box,
          minFontSize: _NameBox.minName,
          maxLines: 2,
          textScaler: MediaQuery.textScalerOf(context),
        ),
    ]..sort();
    var size = style.fontSize!;
    if (sizes.isNotEmpty) {
      final median = sizes[sizes.length ~/ 2];
      size = sizes.firstWhere((s) => s >= _outlierShare * median);
    }
    _size = (key, size);
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final layout = widget.layout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headingHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChalkText(
              widget.title,
              style: chalkStyle(tokens, 38, color: widget.color, height: 1.05)
                  .copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: widget.color,
                    decorationThickness: 2,
                  ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final nameSize = _nameSize(context, tokens, constraints.maxWidth);
              final rows = <Widget>[
                for (var i = 0; i < widget.persons.length; i += layout.perRow)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : _boxGap),
                    child: Row(
                      children: [
                        for (var j = 0; j < layout.perRow; j++) ...[
                          if (j > 0) const SizedBox(width: _boxGap),
                          Expanded(
                            child: i + j < widget.persons.length
                                ? _box(widget.persons[i + j], nameSize)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ];
              final rowCount = rows.length;
              final height =
                  rowCount * layout.boxHeight + (rowCount - 1) * _boxGap;
              if (height <= constraints.maxHeight) {
                return Column(children: rows);
              }
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: _boxGap),
                child: Column(children: rows),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _box(Person p, double nameSize) => _NameBox(
    key: ValueKey('person-${p.id}'),
    name: p.name,
    height: widget.layout.boxHeight,
    nameSize: nameSize,
    onTap: () => widget.onTap(p),
  );
}

/// A person's name in a dashed chalk box.
class _NameBox extends StatelessWidget {
  const _NameBox({
    required this.name,
    required this.height,
    required this.nameSize,
    required this.onTap,
    super.key,
  });

  static const padding = 8.0;
  static const minName = 14.0;

  final String name;
  final double height;

  /// The column's name size (see [_TierColumnState._nameSize]).
  final double nameSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: ChalkBorderPainter(
          color: tokens.text.withAlpha(153),
          dashed: true,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const RoundedRectangleBorder(
              borderRadius: kChalkCorners,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: padding),
              child: Center(
                child: ChalkText(
                  name,
                  style: chalkStyle(tokens, nameSize, height: 1.05),
                  // Only a much longer name than the others shrinks here.
                  minFontSize: minName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A collective account in a solid yellow chalk box.
class _CollectiveBox extends StatelessWidget {
  const _CollectiveBox({required this.name, required this.onTap, super.key});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return CustomPaint(
      painter: ChalkBorderPainter(color: tokens.accent, width: 2.5),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const RoundedRectangleBorder(
            borderRadius: kChalkCorners,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: ChalkText(
                name,
                style: chalkStyle(
                  tokens,
                  32,
                  color: kChalkCollectiveText,
                  height: 1.05,
                ),
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

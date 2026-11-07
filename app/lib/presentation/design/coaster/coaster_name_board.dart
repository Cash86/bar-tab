import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/catalog.dart';
import '../../../l10n/app_localizations.dart';
import '../design.dart';
import 'coaster.dart';

const double _columnGap = 28;
const double _headingHeight = 40;
const double _collectiveDiameter = 120;

/// Persons stay smaller than the collective accounts (as 72 to 84 px in
/// the approved mockup).
const double _collectiveShare = 1.15;
const double _collectiveLabelWidth = 170;

/// Between collective coasters: room for a long word crossing the rims.
const double _collectiveGap = 0.5 * _collectiveDiameter;

/// Least space between two coasters in a row and between two rows.
const double _minGap = 12;

/// Fixed turns of some coasters, in degrees, by position in the column.
double _turn(int index) => index % 3 == 2
    ? -7
    : index % 4 == 3
    ? 5
    : 0;

/// How a tier column lays out its coasters.
@immutable
class CoasterNameLayout {
  const CoasterNameLayout({
    required this.perRow,
    required this.diameter,
    required this.scrolls,
  });

  final int perRow;
  final double diameter;
  final bool scrolls;

  @override
  bool operator ==(Object other) =>
      other is CoasterNameLayout &&
      other.perRow == perRow &&
      other.diameter == diameter &&
      other.scrolls == scrolls;

  @override
  int get hashCode => Object.hash(perRow, diameter, scrolls);

  @override
  String toString() =>
      'CoasterNameLayout($perRow per row, $diameter px, '
      'scrolls: $scrolls)';
}

/// The largest coasters (up to [maxDiameter]) at which the longest column
/// fits [area]: five per row, or fewer when that makes them larger (a
/// short list fills the height). Below [minDiameter] the columns scroll at
/// that size, with as many per row as the width takes (three at least).
///
/// [minDiameter] keeps names readable: a single word of 20 characters may
/// cross the rim (up to 1.5 × the diameter) but is not cut.
CoasterNameLayout planCoasterNames({
  required int maxNamesInColumn,
  required Size area,
  double maxDiameter = 150,
  double minDiameter = 88,
}) {
  double widthFit(int perRow) => area.width / perRow - _minGap;
  double fit(int perRow) {
    final rows = math.max(1, (maxNamesInColumn + perRow - 1) ~/ perRow);
    final heightFit = (area.height - (rows - 1) * _minGap) / rows;
    return math.min(maxDiameter, math.min(widthFit(perRow), heightFit));
  }

  var best = CoasterNameLayout(perRow: 5, diameter: fit(5), scrolls: false);
  for (final perRow in [4, 3]) {
    final d = fit(perRow);
    if (d > best.diameter) {
      best = CoasterNameLayout(perRow: perRow, diameter: d, scrolls: false);
    }
  }
  if (best.diameter >= minDiameter) return best;
  final perRow = [
    5,
    4,
  ].firstWhere((n) => widthFit(n) >= minDiameter, orElse: () => 3);
  return CoasterNameLayout(
    perRow: perRow,
    diameter: math.min(minDiameter, widthFit(perRow)),
    scrolls: true,
  );
}

/// The Bierdeckel name list: collective accounts as large gold-rimmed
/// coasters on top, one column per price tier (tier colour as a dot next
/// to the heading and as the persons' ring colour), persons as coasters,
/// some slightly turned. Taps are ignored while not [enabled].
class CoasterNameBoard extends StatelessWidget {
  const CoasterNameBoard({
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
    return IgnorePointer(
      ignoring: !enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (collective.isNotEmpty) ...[
            SizedBox(
              height: _collectiveDiameter,
              child: Row(
                children: [
                  SizedBox(
                    width: _collectiveLabelWidth,
                    child: _Label(
                      AppLocalizations.of(context).nameListCollective,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Never wider than the board: many accounts share it.
                        final d = math.min(
                          _collectiveDiameter,
                          constraints.maxWidth / collective.length -
                              _collectiveGap,
                        );
                        return Row(
                          children: [
                            for (final p in collective)
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: _collectiveGap,
                                ),
                                child: Coaster(
                                  key: ValueKey('person-${p.id}'),
                                  label: p.name,
                                  diameter: d,
                                  ring: tokens.accent,
                                  highlighted: true,
                                  onTap: () => onTap(p),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth = tiers.isEmpty
                    ? 0.0
                    : (constraints.maxWidth - (tiers.length - 1) * _columnGap) /
                          tiers.length;
                final layout = planCoasterNames(
                  maxNamesInColumn: tiers.fold(
                    0,
                    (m, t) => math.max(m, t.$2.length),
                  ),
                  area: Size(
                    columnWidth,
                    constraints.maxHeight - _headingHeight,
                  ),
                  maxDiameter: collective.isEmpty
                      ? 150
                      : _collectiveDiameter / _collectiveShare,
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
    );
  }
}

/// Small caps label in the body font on the counter.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: tokens.bodyFont,
        fontSize: 19,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.9,
        color: kCoasterPaper,
      ),
    );
  }
}

class _TierColumn extends StatelessWidget {
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
  final CoasterNameLayout layout;
  final ValueChanged<Person> onTap;

  @override
  Widget build(BuildContext context) {
    final d = layout.diameter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headingHeight,
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: kCoasterPaper, width: 2),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: _Label(title)),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rows =
                  (persons.length + layout.perRow - 1) ~/ layout.perRow;
              final free = constraints.maxHeight - rows * d;
              // Rows spread over the column, but stay together.
              final double gap = rows < 2
                  ? _minGap
                  : (free / rows).clamp(_minGap, math.max(_minGap, 0.35 * d));
              final content = Column(
                children: [
                  for (var r = 0; r < rows; r++)
                    Padding(
                      padding: EdgeInsets.only(top: r == 0 ? 0 : gap),
                      child: Row(
                        children: [
                          for (var j = 0; j < layout.perRow; j++)
                            Expanded(
                              child: r * layout.perRow + j < persons.length
                                  ? _cell(r * layout.perRow + j)
                                  : SizedBox(height: d),
                            ),
                        ],
                      ),
                    ),
                ],
              );
              final height = rows * d + math.max(0, rows - 1) * gap;
              if (height <= constraints.maxHeight) return content;
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                // The scroll view clips: room for a long word crossing the
                // rim of a coaster at the column's edge.
                padding: EdgeInsets.fromLTRB(0.25 * d, 4, 0.25 * d, _minGap),
                child: content,
              );
            },
          ),
        ),
      ],
    );
  }

  /// The whole cell around a coaster takes the tap, like a Standard tile:
  /// a tap beside the round coaster (or while the page still slides back
  /// after the drink screen) still finds the person.
  Widget _cell(int index) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onTap(persons[index]),
    child: Center(child: _coaster(index)),
  );

  Widget _coaster(int index) {
    final p = persons[index];
    return Transform.rotate(
      angle: _turn(index) * math.pi / 180,
      child: Coaster(
        key: ValueKey('person-${p.id}'),
        label: p.name,
        diameter: layout.diameter,
        ring: color,
        onTap: () => onTap(p),
      ),
    );
  }
}

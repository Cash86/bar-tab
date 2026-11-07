import 'dart:math' as math;
import 'dart:ui';

/// Smallest box height; boxes grow up to [kChalkMaxBoxHeight] to fill.
const kChalkBoxHeight = 46.0;
const kChalkMaxBoxHeight = 72.0;
const kChalkBoxGap = 6.0;
const kChalkHeader = 40.0;
const kChalkMinFieldWidth = 170.0;
const kChalkMinBoxWidth = 150.0;

/// Gap between stacked fields and between neighbouring columns.
const kChalkFieldGap = 8.0;

/// One group's field on the chalkboard.
class ChalkField {
  const ChalkField({
    required this.rect,
    required this.boxColumns,
    required this.scrolls,
    this.boxHeight = kChalkBoxHeight,
  });

  final Rect rect;
  final int boxColumns;

  /// Height of each drink box, [kChalkBoxHeight] to [kChalkMaxBoxHeight].
  final double boxHeight;

  /// The drinks do not fit [rect]; the field scrolls on its own.
  final bool scrolls;
}

class ChalkBoardPlan {
  const ChalkBoardPlan({required this.fields, required this.scrolls});

  /// In group order.
  final List<ChalkField> fields;

  /// The fields extend below the area; the board scrolls vertically.
  final bool scrolls;
}

double _need(int n, int cols) =>
    kChalkHeader + (n / cols).ceil() * (kChalkBoxHeight + kChalkBoxGap);

double _minWidth(int cols) => cols == 1
    ? kChalkMinFieldWidth
    : 2 * math.max(kChalkMinFieldWidth, kChalkMinBoxWidth);

class _Column {
  final List<int> items = [];
  double height = 0;
  int maxCols = 1;

  double get minWidth => _minWidth(maxCols);

  /// Equal width per box column.
  double get weight => maxCols.toDouble();
}

/// Plans one field per group (in order) for an area, never taller than it.
ChalkBoardPlan planChalkBoard(List<int> counts, Size area) {
  final cols = [for (final n in counts) _need(n, 1) > area.height ? 2 : 1];
  final heights = [
    for (var i = 0; i < counts.length; i++)
      math.min(_need(counts[i], cols[i]), area.height),
  ];

  final columns = <_Column>[];
  for (var i = 0; i < counts.length; i++) {
    final col = columns.isEmpty ? null : columns.last;
    if (col != null &&
        col.height + kChalkFieldGap + heights[i] <= area.height) {
      col.height += kChalkFieldGap + heights[i];
      col.items.add(i);
      col.maxCols = math.max(col.maxCols, cols[i]);
    } else {
      columns.add(
        _Column()
          ..items.add(i)
          ..height = heights[i]
          ..maxCols = cols[i],
      );
    }
  }

  double minOf(_Column c) => math.min(c.minWidth, area.width);
  double rowMin(List<_Column> row) =>
      row.fold<double>(0, (s, c) => s + minOf(c)) +
      kChalkFieldGap * (row.isEmpty ? 0 : row.length - 1);

  final rows = <List<_Column>>[];
  for (final c in columns) {
    if (rows.isNotEmpty && rowMin([...rows.last, c]) <= area.width) {
      rows.last.add(c);
    } else {
      rows.add([c]);
    }
  }

  // One row fills the area height; wrapped rows keep their needs and scroll.
  final fill = rows.length == 1;
  final fields = List<ChalkField?>.filled(counts.length, null);
  var y = 0.0;
  for (final row in rows) {
    // Minimums are kChalkMinFieldWidth per box column, so an equal share
    // per box column never falls below them.
    final share =
        (area.width - kChalkFieldGap * (row.length - 1)) /
        row.fold<double>(0, (s, c) => s + c.weight);
    final widths = [for (final c in row) share * c.weight];
    var x = 0.0;
    var rowHeight = 0.0;
    for (var c = 0; c < row.length; c++) {
      final col = row[c];
      final gaps = kChalkFieldGap * (col.items.length - 1);
      final height = fill ? math.max(area.height, col.height) : col.height;
      // Stacked fields share the column height in proportion to their need.
      final scale = (height - gaps) / (col.height - gaps);
      var top = y;
      for (final i in col.items) {
        final h = i == col.items.last ? y + height - top : heights[i] * scale;
        final scrolls = _need(counts[i], cols[i]) > area.height;
        final boxRows = (counts[i] / cols[i]).ceil();
        final boxHeight = scrolls || boxRows == 0
            ? kChalkBoxHeight
            : ((h - kChalkHeader) / boxRows - kChalkBoxGap).clamp(
                kChalkBoxHeight,
                kChalkMaxBoxHeight,
              );
        fields[i] = ChalkField(
          rect: Rect.fromLTWH(x, top, widths[c], h),
          boxColumns: cols[i],
          scrolls: scrolls,
          boxHeight: boxHeight,
        );
        top += h + kChalkFieldGap;
      }
      rowHeight = math.max(rowHeight, height);
      x += widths[c] + kChalkFieldGap;
    }
    y += rowHeight + kChalkFieldGap;
  }
  return ChalkBoardPlan(
    fields: [for (final f in fields) f!],
    scrolls: rows.length > 1,
  );
}

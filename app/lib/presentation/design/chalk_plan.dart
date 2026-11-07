import 'dart:math' as math;
import 'dart:ui';

const kChalkBoxHeight = 46.0;
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
  });

  final Rect rect;
  final int boxColumns;

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
  int maxCount = 0;

  double get minWidth => _minWidth(maxCols);
  double get weight => math.max(1, maxCols * maxCount).toDouble();
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
      col.maxCount = math.max(col.maxCount, counts[i]);
    } else {
      columns.add(
        _Column()
          ..items.add(i)
          ..height = heights[i]
          ..maxCols = cols[i]
          ..maxCount = counts[i],
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

  final fields = List<ChalkField?>.filled(counts.length, null);
  var y = 0.0;
  for (final row in rows) {
    final spare = area.width - rowMin(row);
    final totalWeight = row.fold<double>(0, (s, c) => s + c.weight);
    var x = 0.0;
    var rowHeight = 0.0;
    for (final col in row) {
      final width = minOf(col) + spare * col.weight / totalWeight;
      var top = y;
      for (final i in col.items) {
        fields[i] = ChalkField(
          rect: Rect.fromLTWH(x, top, width, heights[i]),
          boxColumns: cols[i],
          scrolls: _need(counts[i], cols[i]) > area.height,
        );
        top += heights[i] + kChalkFieldGap;
      }
      rowHeight = math.max(rowHeight, col.height);
      x += width + kChalkFieldGap;
    }
    y += rowHeight + kChalkFieldGap;
  }
  return ChalkBoardPlan(
    fields: [for (final f in fields) f!],
    scrolls: rows.length > 1,
  );
}

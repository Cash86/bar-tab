import 'dart:math' as math;
import 'dart:ui';

/// Coaster diameters in design px, largest first.
const kCoasterSteps = [72.0, 60.0, 50.0];

/// Gap between coasters on a ring, and between ring blocks on the board.
const kCoasterGap = 8.0;

/// One ring of coasters around the hub.
class Ring {
  const Ring({required this.radius, required this.count});

  final double radius;
  final int count;
}

/// The rings of one drink group around its hub.
class GroupRings {
  const GroupRings({
    required this.coaster,
    required this.hub,
    required this.rings,
  });

  final double coaster;
  final double hub;
  final List<Ring> rings;

  /// Radius of the outermost coaster centres.
  double get outerRadius =>
      rings.isEmpty ? (hub - coaster) / 2 : rings.last.radius;

  Size get footprint {
    final side = 2 * outerRadius + coaster;
    return Size(side, side);
  }
}

int _capacity(double radius, double coaster, double gap) =>
    (2 * math.pi * radius / (coaster + gap)).floor();

/// Places [count] coasters on rings around a hub, filling inside out.
GroupRings ringsFor(int count, double coaster, {double gap = kCoasterGap}) {
  final hub = 1.35 * coaster;
  final counts = <int>[];
  final radii = <double>[];
  var radius = hub / 2 + gap + coaster / 2;
  var remaining = count;
  while (remaining > 0) {
    final n = math.min(_capacity(radius, coaster, gap), remaining);
    if (n < 1) {
      radius += coaster + gap;
      continue;
    }
    counts.add(n);
    radii.add(radius);
    remaining -= n;
    if (remaining > 0 && remaining < 3) {
      final total = counts.last + remaining;
      counts[counts.length - 1] = total;
      radii[radii.length - 1] = math.max(
        radius,
        total * (coaster + gap) / (2 * math.pi),
      );
      remaining = 0;
    }
    radius += coaster + gap;
  }
  return GroupRings(
    coaster: coaster,
    hub: hub,
    rings: [
      for (var i = 0; i < counts.length; i++)
        Ring(radius: radii[i], count: counts[i]),
    ],
  );
}

/// The chosen coaster size and the block rectangle of every group.
class CoasterBoardPlan {
  const CoasterBoardPlan({
    required this.coaster,
    required this.groups,
    required this.blocks,
    required this.scrolls,
  });

  final double coaster;
  final List<GroupRings> groups;
  final List<Rect> blocks;
  final bool scrolls;
}

class _Column {
  _Column(this.width);

  final double width;
  final List<int> items = [];
  double height = 0;
}

List<_Column> _columns(List<GroupRings> groups, double maxHeight) {
  final columns = <_Column>[];
  for (var i = 0; i < groups.length; i++) {
    final size = groups[i].footprint;
    final col = columns.isEmpty ? null : columns.last;
    if (col != null &&
        size.width <= col.width &&
        col.height + kCoasterGap + size.height <= maxHeight) {
      col.height += kCoasterGap + size.height;
      col.items.add(i);
    } else {
      columns.add(
        _Column(size.width)
          ..items.add(i)
          ..height = size.height,
      );
    }
  }
  return columns;
}

double _rowWidth(List<_Column> cols) =>
    cols.fold<double>(0, (sum, c) => sum + c.width) +
    kCoasterGap * (cols.isEmpty ? 0 : cols.length - 1);

/// Picks the largest coaster step whose blocks fit [area]; if none does, uses
/// the smallest step and wraps columns into rows that scroll vertically.
CoasterBoardPlan planCoasterBoard(
  List<int> counts,
  Size area, {
  List<double> steps = kCoasterSteps,
}) {
  CoasterBoardPlan build(double step, bool wrap) {
    final groups = [for (final n in counts) ringsFor(n, step)];
    final columns = _columns(groups, area.height);
    final rows = <List<_Column>>[];
    if (wrap) {
      for (final c in columns) {
        if (rows.isNotEmpty && _rowWidth([...rows.last, c]) <= area.width) {
          rows.last.add(c);
        } else {
          rows.add([c]);
        }
      }
    } else {
      rows.add(columns);
    }
    final blocks = List<Rect>.filled(groups.length, Rect.zero);
    var y = 0.0;
    for (final row in rows) {
      var x = 0.0;
      var rowHeight = 0.0;
      for (final col in row) {
        var top = y;
        for (final i in col.items) {
          final size = groups[i].footprint;
          blocks[i] = Rect.fromLTWH(
            x + (col.width - size.width) / 2,
            top,
            size.width,
            size.height,
          );
          top += size.height + kCoasterGap;
        }
        rowHeight = math.max(rowHeight, col.height);
        x += col.width + kCoasterGap;
      }
      y += rowHeight + kCoasterGap;
    }
    return CoasterBoardPlan(
      coaster: step,
      groups: groups,
      blocks: blocks,
      scrolls: wrap,
    );
  }

  for (final step in steps) {
    final plan = build(step, false);
    final columns = _columns(plan.groups, area.height);
    final tallest = columns.fold<double>(0, (m, c) => math.max(m, c.height));
    if (_rowWidth(columns) <= area.width && tallest <= area.height) return plan;
  }
  return build(steps.last, true);
}

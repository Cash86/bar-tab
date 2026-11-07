import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bar_tab/presentation/design/coaster_plan.dart';

List<int> counts(GroupRings g) => [for (final r in g.rings) r.count];

bool overlaps(Rect a, Rect b) => a.overlaps(b);

void main() {
  group('ringsFor', () {
    test('five fit into one ring', () {
      expect(counts(ringsFor(5, 72)), [5]);
    });
    test('seven fill the first ring', () {
      expect(counts(ringsFor(7, 72)), [7]);
    });
    test('nine stay in one widened ring', () {
      final seven = ringsFor(7, 72);
      final nine = ringsFor(9, 72);
      expect(counts(nine), [9]);
      expect(nine.rings.first.radius, greaterThan(seven.rings.first.radius));
    });
    test('ten make rings of 7 and 3', () {
      expect(counts(ringsFor(10, 72)), [7, 3]);
    });
    test('twenty make rings of 7 and 13', () {
      expect(counts(ringsFor(20, 72)), [7, 13]);
    });
    test('two leftovers join the previous ring and widen it', () {
      final g = ringsFor(22, 72);
      expect(counts(g), [7, 15]);
      expect(
        g.rings[1].radius,
        closeTo(15 * 80 / (2 * 3.141592653589793), 1e-6),
      );
    });
    test('one drink is one ring of one', () {
      expect(counts(ringsFor(1, 72)), [1]);
    });
    test('footprint is twice the outer radius plus a coaster', () {
      final g = ringsFor(10, 72);
      expect(g.footprint.width, 2 * g.outerRadius + 72);
      expect(g.footprint.height, g.footprint.width);
    });
  });

  group('planCoasterBoard', () {
    test('four groups fit at 60 with Bier and Alkoholfrei in one column', () {
      final plan = planCoasterBoard([5, 3, 11, 1], const Size(1000, 480));
      expect(plan.coaster, 60);
      expect(plan.scrolls, isFalse);
      expect(plan.blocks, hasLength(4));
      expect(plan.blocks[0].center.dx, closeTo(plan.blocks[1].center.dx, 1e-6));
      expect(plan.blocks[1].top, greaterThan(plan.blocks[0].top));
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          expect(overlaps(plan.blocks[i], plan.blocks[j]), isFalse);
        }
      }
    });

    test('blocks are spread over the area, not packed top-left', () {
      const area = Size(1000, 480);
      final plan = planCoasterBoard([5, 3, 11, 1], area);
      final b = plan.blocks;
      // Columns: [Bier over Alkoholfrei], [Limo & Saft], [Wasser]; equal
      // margins at the edges and between the columns (plus the gap).
      final margin = b[0].left;
      expect(margin, greaterThan(20));
      expect(b[2].left - b[0].right, closeTo(margin + kCoasterGap, 1e-6));
      expect(b[3].left - b[2].right, closeTo(margin + kCoasterGap, 1e-6));
      expect(area.width - b[3].right, closeTo(margin, 1e-6));
      // A lone block sits in the middle of its column.
      expect(b[2].center.dy, closeTo(area.height / 2, 1e-6));
      expect(b[3].center.dy, closeTo(area.height / 2, 1e-6));
      // A stacked column spreads its blocks evenly over the height.
      final top = b[0].top;
      expect(top, greaterThan(0));
      expect(area.height - b[1].bottom, closeTo(top, 1e-6));
      expect(b[1].top - b[0].bottom, closeTo(top + kCoasterGap, 1e-6));
    });

    test('wrapped rows are spread over the width', () {
      final plan = planCoasterBoard(List.filled(8, 30), const Size(1000, 480));
      final b = plan.blocks;
      // Two blocks per row.
      expect(b[0].top, closeTo(b[1].top, 1e-6));
      expect(b[2].top, greaterThan(b[0].bottom));
      expect(b[0].left, greaterThan(20));
      expect(1000 - b[1].right, closeTo(b[0].left, 1e-6));
    });

    test('the real assortment next to the tray fits at 66 on 16:9', () {
      // 1280×720 minus header, tray and order-bar room.
      final plan = planCoasterBoard([5, 3, 11, 1], const Size(1024, 510));
      expect(plan.coaster, 66);
      expect(plan.scrolls, isFalse);
    });

    test('two small groups keep the largest step', () {
      final plan = planCoasterBoard([3, 2], const Size(1000, 480));
      expect(plan.coaster, 72);
      expect(plan.scrolls, isFalse);
    });

    test('a huge assortment falls back to 50 and scrolls', () {
      final plan = planCoasterBoard(List.filled(8, 30), const Size(1000, 480));
      expect(plan.coaster, 50);
      expect(plan.scrolls, isTrue);
      expect(plan.blocks, hasLength(8));
      for (final b in plan.blocks) {
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.right, lessThanOrEqualTo(1000));
      }
      for (var i = 0; i < 8; i++) {
        for (var j = i + 1; j < 8; j++) {
          expect(overlaps(plan.blocks[i], plan.blocks[j]), isFalse);
        }
      }
    });

    test('a group taller than the area drops a step instead of clipping', () {
      final plan = planCoasterBoard([30], const Size(1000, 480));
      expect(plan.coaster, lessThan(72));
      expect(plan.scrolls, isFalse);
      expect(plan.blocks.single.bottom, lessThanOrEqualTo(480));
    });

    test('a group too tall even at the smallest step scrolls', () {
      final plan = planCoasterBoard([30], const Size(1000, 300));
      expect(plan.coaster, 50);
      expect(plan.scrolls, isTrue);
      expect(plan.blocks.single.bottom, greaterThan(300));
    });
  });
}

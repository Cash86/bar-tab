import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:bar_tab/presentation/design/chalk_plan.dart';

void main() {
  const area = Size(760, 480);

  bool overlap(Rect a, Rect b) => a.overlaps(b);

  void expectNoOverlap(ChalkBoardPlan plan) {
    for (var i = 0; i < plan.fields.length; i++) {
      for (var j = i + 1; j < plan.fields.length; j++) {
        expect(
          overlap(plan.fields[i].rect, plan.fields[j].rect),
          isFalse,
          reason: 'fields $i and $j overlap',
        );
      }
    }
  }

  test('mixed groups: large field uses two box columns, small ones stack', () {
    final plan = planChalkBoard([5, 3, 11, 1], area);
    expect(plan.fields, hasLength(4));
    expect(plan.fields[2].boxColumns, 2);
    expect(plan.fields[0].boxColumns, 1);
    // The 1-drink field stacks below the 11-drink field.
    expect(plan.fields[3].rect.left, plan.fields[2].rect.left);
    expect(plan.fields[3].rect.top, greaterThan(plan.fields[2].rect.top));
    final lefts = plan.fields.map((f) => f.rect.left).toSet();
    final widthSum = lefts.fold<double>(
      0,
      (s, l) => s + plan.fields.firstWhere((f) => f.rect.left == l).rect.width,
    );
    expect(widthSum, lessThanOrEqualTo(area.width));
    expectNoOverlap(plan);
    expect(plan.scrolls, isFalse);
    for (final f in plan.fields) {
      expect(f.scrolls, isFalse);
      expect((Offset.zero & area).expandToInclude(f.rect), Offset.zero & area);
    }
  });

  test('a one-drink field is at least the minimum width', () {
    final plan = planChalkBoard([1, 20, 20], area);
    expect(
      plan.fields.first.rect.width,
      greaterThanOrEqualTo(kChalkMinFieldWidth),
    );
  });

  test('two-column fields are at least two minimum box widths', () {
    final plan = planChalkBoard([11], area);
    expect(plan.fields.single.boxColumns, 2);
    expect(
      plan.fields.single.rect.width,
      greaterThanOrEqualTo(2 * kChalkMinBoxWidth),
    );
  });

  test('wider share for larger groups', () {
    final plan = planChalkBoard([2, 10], const Size(900, 700));
    expect(plan.fields[1].rect.width, greaterThan(plan.fields[0].rect.width));
  });

  test('one group of 40 drinks uses two columns and scrolls on its own', () {
    final plan = planChalkBoard([40], area);
    final f = plan.fields.single;
    expect(f.boxColumns, 2);
    expect(f.scrolls, isTrue);
    expect(f.rect.height, area.height);
    expect(plan.scrolls, isFalse);
  });

  test('a scrolling field is never taller than the area', () {
    final plan = planChalkBoard([40, 3], area);
    for (final f in plan.fields) {
      expect(f.rect.height, lessThanOrEqualTo(area.height));
    }
    expectNoOverlap(plan);
  });

  test('8 groups of 6 wrap into rows and scroll vertically only', () {
    final plan = planChalkBoard(List.filled(8, 6), area);
    expect(plan.fields, hasLength(8));
    expect(plan.scrolls, isTrue);
    for (final f in plan.fields) {
      expect(f.rect.left, greaterThanOrEqualTo(0));
      expect(f.rect.right, lessThanOrEqualTo(area.width + 0.001));
    }
    expect(
      plan.fields.map((f) => f.rect.bottom).reduce(math.max),
      greaterThan(area.height),
    );
    expectNoOverlap(plan);
  });

  test('a narrow area wraps a two-column field without going sideways', () {
    final plan = planChalkBoard([11, 11], const Size(400, 480));
    expect(plan.scrolls, isTrue);
    for (final f in plan.fields) {
      expect(f.rect.right, lessThanOrEqualTo(400.001));
    }
    expectNoOverlap(plan);
  });

  test('empty input gives an empty plan', () {
    final plan = planChalkBoard([], area);
    expect(plan.fields, isEmpty);
    expect(plan.scrolls, isFalse);
  });
}

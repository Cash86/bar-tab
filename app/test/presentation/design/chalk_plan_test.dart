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

  test('width is shared equally per box column', () {
    // 10 drinks fit one box column: same share as 2 drinks.
    final one = planChalkBoard([2, 10], const Size(900, 700));
    expect(one.fields[0].boxColumns, 1);
    expect(one.fields[1].boxColumns, 1);
    expect(one.fields[1].rect.width, closeTo(one.fields[0].rect.width, 0.01));
    // 20 drinks need two box columns: twice the share.
    final two = planChalkBoard([2, 20], const Size(900, 700));
    expect(two.fields[1].boxColumns, 2);
    expect(
      two.fields[1].rect.width,
      closeTo(2 * two.fields[0].rect.width, 0.01),
    );
  });

  test('columns stretch to the area height; stacks share it by need', () {
    // Needs 300, 196, 352 (2 box columns), 92: only 11 and 1 can stack.
    final plan = planChalkBoard([5, 3, 11, 1], area);
    for (final i in [0, 1]) {
      expect(plan.fields[i].rect.top, 0);
      expect(plan.fields[i].rect.bottom, closeTo(area.height, 0.01));
    }
    final limo = plan.fields[2].rect;
    final wasser = plan.fields[3].rect;
    expect(wasser.bottom, closeTo(area.height, 0.01));
    expect(wasser.top - limo.bottom, closeTo(kChalkFieldGap, 0.01));
    expect(limo.height / wasser.height, closeTo(352 / 92, 0.01));
  });

  test('boxes grow to fill the field, from 46 up to 72', () {
    final plan = planChalkBoard([5, 3, 11, 1], area);
    for (final f in plan.fields) {
      expect(
        f.boxHeight,
        inInclusiveRange(kChalkBoxHeight, kChalkMaxBoxHeight),
      );
    }
    // 5 boxes in 480: (480 - 40) / 5 - 6 = 82 → capped at 72.
    expect(plan.fields[0].boxHeight, kChalkMaxBoxHeight);
    // 11 drinks in 2 columns (6 rows) get (360.8 - 40) / 6 - 6 ≈ 47.5.
    final limo = plan.fields[2];
    expect(
      limo.boxHeight,
      closeTo((limo.rect.height - kChalkHeader) / 6 - kChalkBoxGap, 0.01),
    );
  });

  test('a scrolling field keeps the smallest boxes', () {
    final plan = planChalkBoard([40], area);
    expect(plan.fields.single.scrolls, isTrue);
    expect(plan.fields.single.boxHeight, kChalkBoxHeight);
  });

  test('wrapped rows keep their needs (no stretching)', () {
    final plan = planChalkBoard(List.filled(8, 6), area);
    expect(plan.scrolls, isTrue);
    for (final f in plan.fields) {
      expect(f.rect.height, closeTo(kChalkHeader + 6 * 52, 0.01));
      expect(f.boxHeight, kChalkBoxHeight);
    }
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

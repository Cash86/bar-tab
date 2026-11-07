import 'package:bar_tab/presentation/design/chalk/chalk_name_board.dart';
import 'package:bar_tab/presentation/design/coaster/coaster_name_board.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('planChalkNames', () {
    // Boxes are 10 px apart: rows * h + (rows - 1) * 10.
    final table = <(int, double, ChalkNameLayout)>[
      // 3 names: capped at 100 px.
      (
        3,
        500,
        const ChalkNameLayout(perRow: 3, boxHeight: 100, scrolls: false),
      ),
      // 15 names, 3 per row = 5 rows: (340 - 40) / 5 = 60, the 3-per-row floor.
      (
        15,
        340,
        const ChalkNameLayout(perRow: 3, boxHeight: 60, scrolls: false),
      ),
      // Below it: 4 per row = 4 rows, (300 - 30) / 4 = 67.5.
      (
        15,
        300,
        const ChalkNameLayout(perRow: 4, boxHeight: 67.5, scrolls: false),
      ),
      // (230 - 30) / 4 = 50, the 4-per-row floor.
      (
        15,
        230,
        const ChalkNameLayout(perRow: 4, boxHeight: 50, scrolls: false),
      ),
      // Below it the columns scroll at 50.
      (15, 229, const ChalkNameLayout(perRow: 4, boxHeight: 50, scrolls: true)),
    ];
    for (final (n, h, expected) in table) {
      test('$n names in $h px -> $expected', () {
        expect(
          planChalkNames(maxNamesInColumn: n, availableHeight: h),
          expected,
        );
      });
    }
  });

  group('planCoasterNames', () {
    // Coasters keep 12 px apart; width fit = width / perRow - 12.
    test('picks 4 per row when that makes the coasters larger', () {
      // 5 per row: 600 / 5 - 12 = 108; 4 per row: 4 rows, (500 - 36) / 4.
      expect(
        planCoasterNames(maxNamesInColumn: 15, area: const Size(600, 500)),
        const CoasterNameLayout(perRow: 4, diameter: 116, scrolls: false),
      );
    });

    test('picks 3 per row for a short list, capped at 150 px', () {
      expect(
        planCoasterNames(maxNamesInColumn: 6, area: const Size(600, 600)),
        const CoasterNameLayout(perRow: 3, diameter: 150, scrolls: false),
      );
    });

    test('honours a smaller cap (104 px under collective accounts); '
        'ties keep 5 per row', () {
      expect(
        planCoasterNames(
          maxNamesInColumn: 15,
          area: const Size(600, 500),
          maxDiameter: 104,
        ),
        const CoasterNameLayout(perRow: 5, diameter: 104, scrolls: false),
      );
    });

    test('below 88 px the column scrolls at 88 px', () {
      // Best fit would be 5 per row at (250 - 24) / 3 = 75.3 px.
      expect(
        planCoasterNames(maxNamesInColumn: 15, area: const Size(600, 250)),
        const CoasterNameLayout(perRow: 5, diameter: 88, scrolls: true),
      );
      expect(
        planCoasterNames(maxNamesInColumn: 40, area: const Size(600, 430)),
        const CoasterNameLayout(perRow: 5, diameter: 88, scrolls: true),
      );
    });

    test('a narrow scrolling column takes fewer per row to keep 88 px', () {
      // 5 per row: 64 px, 4 per row: 83 px, 3 per row: 114.7 px wide.
      expect(
        planCoasterNames(maxNamesInColumn: 40, area: const Size(380, 430)),
        const CoasterNameLayout(perRow: 3, diameter: 88, scrolls: true),
      );
      // 4 per row: 440 / 4 - 12 = 98 px.
      expect(
        planCoasterNames(maxNamesInColumn: 40, area: const Size(440, 430)),
        const CoasterNameLayout(perRow: 4, diameter: 88, scrolls: true),
      );
      // Even 3 per row is narrower than 88: as wide as the width allows.
      final narrow = planCoasterNames(
        maxNamesInColumn: 40,
        area: const Size(270, 430),
      );
      expect(narrow.perRow, 3);
      expect(narrow.scrolls, isTrue);
      expect(narrow.diameter, closeTo(270 / 3 - 12, 1e-9));
    });
  });
}

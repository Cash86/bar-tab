import 'package:bar_tab/domain/booking.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/presentation/drinks/order_controller.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fakes.dart';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  late FakeBookingRepository bookings;
  late FakeSyncService sync;
  late FixedClock clock;

  setUp(() {
    bookings = FakeBookingRepository();
    sync = FakeSyncService();
    clock = FixedClock(DateTime.utc(2026, 11, 2, 20));
  });

  /// Runs [body] in fake time with a container whose controller for `p1`
  /// stays alive.
  void run(
    void Function(
      FakeAsync async,
      OrderController controller,
      ProviderContainer c,
    )
    body, {
    bool withSync = true,
  }) {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: [
          bookingRepositoryProvider.overrideWithValue(bookings),
          syncServiceProvider.overrideWithValue(withSync ? sync : null),
          clockProvider.overrideWithValue(clock),
        ],
      );
      container.listen(orderControllerProvider('p1'), (_, _) {});
      body(
        async,
        container.read(orderControllerProvider('p1').notifier),
        container,
      );
      container.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  }

  OrderState stateOf(ProviderContainer c) =>
      c.read(orderControllerProvider('p1'));

  test('commits 8 s after the last tap, not before', () {
    expect(kAutoBookDelay, const Duration(seconds: 8));
    run((async, controller, c) {
      controller.tap('d1', 115);
      async.elapse(const Duration(milliseconds: 7999));
      expect(bookings.bookings, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(bookings.bookings, hasLength(1));
      expect(stateOf(c).draft.isEmpty, isTrue);
      expect(stateOf(c).booked!.lines.single.drinkId, 'd1');
    });
  });

  test('a second tap at 5 s moves the commit to 13 s', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      async.elapse(const Duration(seconds: 5));
      controller.tap('d2', 60);
      async.elapse(const Duration(milliseconds: 7999));
      expect(bookings.bookings, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(bookings.bookings, hasLength(2));
    });
  });

  test('countdown counts down once per second', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      expect(stateOf(c).secondsLeft, 8);
      async.elapse(const Duration(seconds: 1));
      expect(stateOf(c).secondsLeft, 7);
      async.elapse(const Duration(seconds: 5));
      expect(stateOf(c).secondsLeft, 2);
    });
  });

  test('the 3rd tap opens the sheet, which pauses the timer', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.tap('d1', 115);
      expect(stateOf(c).sheetDrinkId, isNull);
      controller.tap('d1', 115);
      expect(stateOf(c).sheetDrinkId, 'd1');
      expect(stateOf(c).sheetQuantity, 3);
      async.elapse(const Duration(seconds: 30));
      expect(bookings.bookings, isEmpty);

      controller.setQuantity(24);
      controller.closeSheet();
      expect(stateOf(c).sheetDrinkId, isNull);
      expect(stateOf(c).draft.lines.single.quantity, 24);
      async.elapse(const Duration(milliseconds: 7999));
      expect(bookings.bookings, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(bookings.bookings.single.quantity, 24);
    });
  });

  test('quantity 0 in the sheet removes the line on close', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.tap('d2', 60);
      controller.openSheet('d1');
      controller.setQuantity(0);
      expect(stateOf(c).effectiveDraft.lines.map((l) => l.drinkId), ['d2']);
      controller.closeSheet();
      expect(stateOf(c).draft.lines.map((l) => l.drinkId), ['d2']);
    });
  });

  test('discard clears without writing', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.discard();
      expect(stateOf(c).draft.isEmpty, isTrue);
      async.elapse(const Duration(seconds: 30));
      expect(bookings.bookings, isEmpty);
      expect(sync.syncNowCalls, 0);
      expect(stateOf(c).booked, isNull);
    });
  });

  test('commit writes one booking per line with fixed prices and UUIDs', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.tap('d1', 999); // later price is ignored: fixed at first tap
      controller.tap('d2', 60);
      clock.advance(const Duration(minutes: 1));
      controller.commit();
      async.flushMicrotasks();

      final written = bookings.bookings;
      expect(written, hasLength(2));
      expect(written.map((b) => (b.drinkId, b.quantity, b.unitPriceCents)), [
        ('d1', 2, 115),
        ('d2', 1, 60),
      ]);
      for (final b in written) {
        expect(b.id, matches(_uuidV4));
        expect(b.personId, 'p1');
        expect(b.bookedAt, DateTime.utc(2026, 11, 2, 20, 1));
        expect(b.status, BookingStatus.queued);
        expect(b.includedInTabs, isFalse);
      }
      expect(written[0].id, isNot(written[1].id));
      expect(sync.syncNowCalls, 1);
      // No second commit from the cancelled timer.
      async.elapse(const Duration(seconds: 30));
      expect(bookings.bookings, hasLength(2));
      expect(sync.syncNowCalls, 1);
    });
  });

  test('commit with the sheet open books the sheet quantity', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.openSheet('d1');
      controller.setQuantity(20);
      controller.commit();
      async.flushMicrotasks();
      expect(bookings.bookings.single.quantity, 20);
      expect(stateOf(c).sheetDrinkId, isNull);
    });
  });

  test('commit on an empty draft writes nothing', () {
    run((async, controller, c) {
      controller.commit();
      async.flushMicrotasks();
      expect(bookings.bookings, isEmpty);
      expect(sync.syncNowCalls, 0);
      expect(stateOf(c).booked, isNull);
    });
  });

  test('commit without a sync service still writes', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.commit();
      async.flushMicrotasks();
      expect(bookings.bookings, hasLength(1));
    }, withSync: false);
  });

  test('a failing sync does not affect the commit', () {
    sync.syncError = StateError('offline');
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.commit();
      async.flushMicrotasks();
      expect(bookings.bookings, hasLength(1));
      expect(stateOf(c).booked, isNotNull);
    });
  });

  test('a failing write keeps the draft', () {
    bookings.addAllError = StateError('disk full');
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.commit();
      async.flushMicrotasks();
      expect(stateOf(c).draft.lines.single.drinkId, 'd1');
      expect(stateOf(c).booked, isNull);
      expect(sync.syncNowCalls, 0);
    });
  });
}

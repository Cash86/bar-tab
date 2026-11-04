import 'dart:async';

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

  test('quickBook books one unit at once with the given price and hold', () {
    run((async, controller, c) {
      unawaited(controller.quickBook('d1', 115));
      async.flushMicrotasks();
      final booking = bookings.bookings.single;
      expect(booking.quantity, 1);
      expect(booking.unitPriceCents, 115);
      expect(booking.holdUntil, clock.now().add(kUndoWindow));
      expect(stateOf(c).booked!.draft.lines.single.drinkId, 'd1');
      expect(stateOf(c).secondsLeft, 0);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('quickBook is ignored while the quantity sheet is open', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.tap('d1', 115);
      controller.tap('d1', 115); // opens the sheet
      unawaited(controller.quickBook('d2', 60));
      async.flushMicrotasks();
      expect(stateOf(c).sheetDrinkId, 'd1');
      expect(stateOf(c).draft.lines.map((l) => l.drinkId), ['d1']);
      expect(bookings.bookings, isEmpty);
    });
  });

  test('quickBook is ignored while a grid order is pending', () {
    run((async, controller, c) {
      controller.tap('d2', 60);
      unawaited(controller.quickBook('d1', 115));
      async.flushMicrotasks();
      expect(stateOf(c).draft.lines.single.drinkId, 'd2');
      async.elapse(kAutoBookDelay);
      expect(bookings.bookings.single.drinkId, 'd2');
    });
  });

  test('a second quickBook while the first commits books once', () {
    run((async, controller, c) {
      unawaited(controller.quickBook('d1', 115));
      unawaited(controller.quickBook('d1', 115));
      async.flushMicrotasks();
      expect(bookings.bookings, hasLength(1));
      expect(bookings.bookings.single.quantity, 1);
      expect(stateOf(c).draft.isEmpty, isTrue);
    });
  });

  test('quickBook is ignored once an order was booked', () {
    run((async, controller, c) {
      unawaited(controller.quickBook('d1', 115));
      async.flushMicrotasks();
      expect(stateOf(c).booked!.quick, isTrue);
      unawaited(controller.quickBook('d2', 60));
      async.flushMicrotasks();
      expect(bookings.bookings, hasLength(1));
      expect(stateOf(c).draft.isEmpty, isTrue);
    });
  });

  test('quickBook is ignored after the idle timeout left the screen', () {
    run((async, controller, c) {
      async.elapse(kDrinkScreenIdleTimeout);
      expect(stateOf(c).idleLeft, isTrue);
      unawaited(controller.quickBook('d1', 115));
      async.flushMicrotasks();
      expect(bookings.bookings, isEmpty);
    });
  });

  test('commits 5 s after the last tap, not at 4.9 s', () {
    expect(kAutoBookDelay, const Duration(seconds: 5));
    run((async, controller, c) {
      controller.tap('d1', 115);
      async.elapse(const Duration(milliseconds: 4900));
      expect(bookings.bookings, isEmpty);
      async.elapse(const Duration(milliseconds: 99));
      expect(bookings.bookings, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(bookings.bookings, hasLength(1));
      expect(stateOf(c).draft.isEmpty, isTrue);
      expect(stateOf(c).booked!.draft.lines.single.drinkId, 'd1');
      expect(stateOf(c).booked!.bookingIds, {bookings.bookings.single.id});
    });
  });

  test('a second tap before the commit restarts the delay', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      async.elapse(kAutoBookDelay - const Duration(seconds: 1));
      controller.tap('d2', 60);
      async.elapse(kAutoBookDelay - const Duration(milliseconds: 1));
      expect(bookings.bookings, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(bookings.bookings, hasLength(2));
    });
  });

  test('countdown counts down once per second', () {
    run((async, controller, c) {
      final delay = kAutoBookDelay.inSeconds;
      controller.tap('d1', 115);
      expect(stateOf(c).secondsLeft, delay);
      async.elapse(const Duration(seconds: 1));
      expect(stateOf(c).secondsLeft, delay - 1);
      async.elapse(Duration(seconds: delay - 3));
      expect(stateOf(c).secondsLeft, 2);
    });
  });

  test('every countdown restart gets a new run, ticks keep it', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      final first = stateOf(c).countdownRun;
      async.elapse(const Duration(seconds: 1));
      expect(stateOf(c).countdownRun, first);
      controller.tap('d2', 60);
      final second = stateOf(c).countdownRun;
      expect(second, isNot(first));
      controller.tap('d1', 115);
      controller.tap('d1', 115); // opens the sheet
      controller.closeSheet();
      expect(stateOf(c).countdownRun, isNot(second));
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
      async.elapse(const Duration(seconds: 29));
      expect(bookings.bookings, isEmpty);

      controller.setQuantity(24);
      controller.closeSheet();
      expect(stateOf(c).sheetDrinkId, isNull);
      expect(stateOf(c).draft.lines.single.quantity, 24);
      async.elapse(kAutoBookDelay - const Duration(milliseconds: 1));
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
        expect(b.holdUntil, DateTime.utc(2026, 11, 2, 20, 1, 15));
      }
      expect(kUndoWindow, const Duration(seconds: 15));
      expect(stateOf(c).booked!.bookingIds, {for (final b in written) b.id});
      expect(
        stateOf(c).booked!.holdUntil,
        DateTime.utc(2026, 11, 2, 20, 1, 15),
      );
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

  test('a failed write is retried kAutoBookDelay later', () {
    bookings.addAllError = StateError('disk full');
    run((async, controller, c) {
      controller.tap('d1', 115);
      controller.commit();
      async.flushMicrotasks();
      expect(stateOf(c).saveFailed, isTrue);
      expect(stateOf(c).secondsLeft, kAutoBookDelay.inSeconds);

      bookings.addAllError = null;
      async.elapse(kAutoBookDelay - const Duration(milliseconds: 1));
      expect(bookings.bookings, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(bookings.bookings.single.drinkId, 'd1');
      expect(stateOf(c).saveFailed, isFalse);
      expect(stateOf(c).booked, isNotNull);
    });
  });

  test('taps while a commit is being written are ignored', () {
    run((async, controller, c) {
      // Created in the fake zone so its completion runs in fake time.
      final gate = Completer<void>();
      bookings.addAllGate = gate;
      controller.tap('d1', 115);
      controller.commit();
      async.flushMicrotasks();
      controller.tap('d2', 60);
      controller.commit();
      expect(stateOf(c).draft.isEmpty, isTrue);

      gate.complete();
      async.flushMicrotasks();
      expect(bookings.bookings.map((b) => b.drinkId), ['d1']);
      expect(stateOf(c).booked!.draft.lines.single.drinkId, 'd1');
      expect(sync.syncNowCalls, 1);
    });
  });

  test('nothing fires while a commit is in flight', () {
    run((async, controller, c) {
      final gate = Completer<void>();
      bookings.addAllGate = gate;
      controller.tap('d1', 115);
      controller.commit();
      async.flushMicrotasks();
      expect(stateOf(c).committing, isTrue);

      async.elapse(const Duration(seconds: 31));
      expect(stateOf(c).idleLeft, isFalse);
      expect(stateOf(c).committing, isTrue);
      expect(bookings.bookings, isEmpty);

      gate.complete();
      async.flushMicrotasks();
      expect(bookings.bookings, hasLength(1));
      expect(stateOf(c).booked, isNotNull);
      expect(stateOf(c).idleLeft, isFalse);
    });
  });

  test('start() resets a reused controller and re-arms the idle timer', () {
    run((async, controller, c) {
      controller.tap('d1', 115);
      async.elapse(kAutoBookDelay);
      expect(stateOf(c).booked, isNotNull);
      // Same person re-opened before the old instance was disposed.
      controller.start();
      expect(stateOf(c).booked, isNull);
      expect(stateOf(c).idleLeft, isFalse);
      async.elapse(const Duration(seconds: 29));
      expect(stateOf(c).idleLeft, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(stateOf(c).idleLeft, isTrue);
    });
  });

  test('start() does not interrupt a running commit', () {
    run((async, controller, c) {
      final gate = Completer<void>();
      bookings.addAllGate = gate;
      controller.tap('d1', 115);
      controller.commit();
      async.flushMicrotasks();
      controller.start();
      expect(stateOf(c).committing, isTrue);
      gate.complete();
      async.flushMicrotasks();
      expect(stateOf(c).booked, isNotNull);
    });
  });
}

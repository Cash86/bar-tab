import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../domain/booking.dart';
import '../../domain/order.dart';
import '../providers.dart';

/// Time after the last change before a pending order is booked.
const kAutoBookDelay = Duration(seconds: 5);

/// Idle time on the drink screen with an empty draft before it is left.
const kDrinkScreenIdleTimeout = Duration(seconds: 30);

/// Idle time in the open quantity sheet before it closes.
const kQuantitySheetIdleTimeout = Duration(seconds: 30);

/// Overridable in tests.
final drinkScreenIdleTimeoutProvider = Provider<Duration>(
  (ref) => kDrinkScreenIdleTimeout,
);

/// Overridable in tests.
final quantitySheetIdleTimeoutProvider = Provider<Duration>(
  (ref) => kQuantitySheetIdleTimeout,
);

final _log = Logger('order');
const _uuid = Uuid();

/// A committed order: what was booked and the ids of its bookings, held
/// until [holdUntil] so it can be undone from the name list.
@immutable
class BookedOrder {
  const BookedOrder(this.draft, this.bookingIds, this.holdUntil);

  final OrderDraft draft;
  final Set<String> bookingIds;
  final DateTime holdUntil;
}

/// The order being built on the drink selection screen.
@immutable
class OrderState {
  const OrderState({
    required this.draft,
    this.sheetDrinkId,
    this.sheetQuantity = 0,
    this.secondsLeft = 0,
    this.countdownRun = 0,
    this.booked,
    this.saveFailed = false,
    this.committing = false,
    this.idleLeft = false,
  });

  final OrderDraft draft;

  /// Drink whose quantity sheet is open, or `null`.
  final String? sheetDrinkId;

  /// Quantity being edited in the open sheet; applied when it closes.
  final int sheetQuantity;

  /// Whole seconds until the auto-booking; only meaningful while counting.
  final int secondsLeft;

  /// Changes on every (re)start of the countdown, not on its ticks: the
  /// countdown bar refills and drains over [kAutoBookDelay] for each run.
  final int countdownRun;

  /// The order written by the last successful commit: the screen leaves.
  final BookedOrder? booked;

  /// The last attempt to write this order failed; it is retried after
  /// [kAutoBookDelay].
  final bool saveFailed;

  /// A commit is being written; edits are ignored and the screen must not
  /// be left until it is done.
  final bool committing;

  /// The empty drink screen was idle too long: the screen leaves without
  /// booking.
  final bool idleLeft;

  /// [draft] with the open sheet's quantity applied (a 0 removes the line).
  OrderDraft get effectiveDraft {
    final id = sheetDrinkId;
    return id == null ? draft : draft.setQuantity(id, sheetQuantity);
  }

  OrderState _copy({
    OrderDraft? draft,
    String? Function()? sheetDrinkId,
    int? sheetQuantity,
    int? secondsLeft,
    int? countdownRun,
    BookedOrder? Function()? booked,
    bool? saveFailed,
    bool? committing,
    bool? idleLeft,
  }) => OrderState(
    draft: draft ?? this.draft,
    sheetDrinkId: sheetDrinkId != null ? sheetDrinkId() : this.sheetDrinkId,
    sheetQuantity: sheetQuantity ?? this.sheetQuantity,
    secondsLeft: secondsLeft ?? this.secondsLeft,
    countdownRun: countdownRun ?? this.countdownRun,
    booked: booked != null ? booked() : this.booked,
    saveFailed: saveFailed ?? this.saveFailed,
    committing: committing ?? this.committing,
    idleLeft: idleLeft ?? this.idleLeft,
  );
}

/// Builds one person's order, auto-books it [kAutoBookDelay] after the last
/// change (paused while the quantity sheet is open) and commits it.
class OrderController extends Notifier<OrderState> {
  OrderController(this.personId);

  final String personId;
  Timer? _timer;
  Timer? _idleTimer;
  int _runs = 0;

  @override
  OrderState build() {
    ref.onDispose(_cancelTimer);
    _startEmptyIdle();
    return OrderState(draft: OrderDraft.empty(personId));
  }

  /// Called when the drink screen opens: a controller reused from a screen
  /// that is still popping (same person re-opened) starts clean, with the
  /// idle timer armed. A running commit is left alone.
  void start() {
    if (state.committing) return;
    _cancelTimer();
    state = OrderState(draft: OrderDraft.empty(personId));
    _startEmptyIdle();
  }

  /// Any pointer activity on the screen: restarts the idle timer that
  /// applies (empty draft: leave; open sheet: close).
  void activity() {
    if (state.committing || state.idleLeft) return;
    if (state.sheetDrinkId != null || state.draft.isEmpty) _restartTimer();
  }

  /// Adds one of [drinkId]; [unitPriceCents] is kept from the first tap.
  /// The 3rd tap opens the quantity sheet.
  void tap(String drinkId, int unitPriceCents) {
    if (state.committing || state.sheetDrinkId != null) return;
    final result = state.draft.tap(drinkId, unitPriceCents);
    state = state._copy(draft: result.draft);
    if (result.openQuantitySheet) {
      openSheet(drinkId);
    } else {
      _restartTimer();
    }
  }

  void openSheet(String drinkId) {
    if (state.committing) return;
    final line = state.draft.lines.firstWhere((l) => l.drinkId == drinkId);
    _cancelTimer();
    state = state._copy(
      sheetDrinkId: () => drinkId,
      sheetQuantity: line.quantity,
    );
    _restartTimer();
  }

  /// Sets the quantity in the open sheet (0..999).
  void setQuantity(int quantity) {
    if (state.committing || state.sheetDrinkId == null) return;
    if (quantity < 0 || quantity > maxLineQuantity) {
      throw ArgumentError.value(quantity, 'quantity', 'must be 0..999');
    }
    state = state._copy(sheetQuantity: quantity);
    _restartTimer();
  }

  /// Applies the sheet quantity, closes the sheet and restarts the timer.
  void closeSheet() {
    if (state.committing || state.sheetDrinkId == null) return;
    state = OrderState(
      draft: state.effectiveDraft,
      saveFailed: state.saveFailed,
    );
    _restartTimer();
  }

  void discard() {
    if (state.committing) return;
    _cancelTimer();
    state = OrderState(draft: OrderDraft.empty(personId));
    _restartTimer();
  }

  /// Books every line (open sheet included), held back from upload for
  /// [kUndoWindow], and triggers a sync. Does nothing for an empty order or
  /// while a commit is running. If the write fails the order is kept and
  /// retried after [kAutoBookDelay].
  Future<void> commit() async {
    if (state.committing) return;
    _cancelTimer();
    final draft = state.effectiveDraft;
    state = OrderState(draft: OrderDraft.empty(personId));
    if (draft.isEmpty) {
      _restartTimer();
      return;
    }

    final now = ref.read(clockProvider).now();
    final holdUntil = now.add(kUndoWindow);
    final bookings = [
      for (final line in draft.lines)
        Booking(
          id: _uuid.v4(),
          personId: personId,
          drinkId: line.drinkId,
          quantity: line.quantity,
          unitPriceCents: line.unitPriceCents,
          bookedAt: now,
          status: BookingStatus.queued,
          includedInTabs: false,
          holdUntil: holdUntil,
        ),
    ];
    final repository = ref.read(bookingRepositoryProvider);
    final sync = ref.read(syncServiceProvider);
    state = state._copy(committing: true);
    try {
      await repository.addAll(bookings);
    } on Object catch (e, st) {
      _log.severe('Writing the order failed', e, st);
      if (ref.mounted) {
        state = OrderState(draft: draft, saveFailed: true);
        _restartTimer();
      }
      return;
    }
    if (sync != null) {
      unawaited(
        sync.syncNow().catchError((Object e, StackTrace st) {
          _log.severe('Sync after booking failed', e, st);
        }),
      );
    }
    if (ref.mounted) {
      final booked = BookedOrder(draft, {
        for (final b in bookings) b.id,
      }, holdUntil);
      state = state._copy(committing: false, booked: () => booked);
    }
  }

  void _restartTimer() {
    _cancelTimer();
    if (state.committing) return;
    if (state.sheetDrinkId != null) {
      _idleTimer = Timer(
        ref.read(quantitySheetIdleTimeoutProvider),
        closeSheet,
      );
      return;
    }
    if (state.draft.isEmpty) {
      _startEmptyIdle();
      return;
    }
    state = state._copy(
      secondsLeft: kAutoBookDelay.inSeconds,
      countdownRun: ++_runs,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = state.secondsLeft - 1;
      if (left <= 0) {
        unawaited(commit());
      } else {
        state = state._copy(secondsLeft: left);
      }
    });
  }

  void _startEmptyIdle() {
    _idleTimer = Timer(ref.read(drinkScreenIdleTimeoutProvider), () {
      if (!state.committing) state = state._copy(idleLeft: true);
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
  }
}

final orderControllerProvider = NotifierProvider.autoDispose
    .family<OrderController, OrderState, String>(OrderController.new);

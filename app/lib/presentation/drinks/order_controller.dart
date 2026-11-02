import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../domain/booking.dart';
import '../../domain/order.dart';
import '../providers.dart';

/// Time after the last change before a pending order is booked.
const kAutoBookDelay = Duration(seconds: 8);

final _log = Logger('order');
const _uuid = Uuid();

/// The order being built on the drink selection screen.
@immutable
class OrderState {
  const OrderState({
    required this.draft,
    this.sheetDrinkId,
    this.sheetQuantity = 0,
    this.secondsLeft = 0,
    this.booked,
    this.saveFailed = false,
  });

  final OrderDraft draft;

  /// Drink whose quantity sheet is open, or `null`.
  final String? sheetDrinkId;

  /// Quantity being edited in the open sheet; applied when it closes.
  final int sheetQuantity;

  /// Whole seconds until the auto-booking; only meaningful while counting.
  final int secondsLeft;

  /// The draft written by the last successful commit: the screen leaves.
  final OrderDraft? booked;

  /// The last attempt to write this order failed; it is retried after
  /// [kAutoBookDelay].
  final bool saveFailed;

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
    OrderDraft? Function()? booked,
    bool? saveFailed,
  }) => OrderState(
    draft: draft ?? this.draft,
    sheetDrinkId: sheetDrinkId != null ? sheetDrinkId() : this.sheetDrinkId,
    sheetQuantity: sheetQuantity ?? this.sheetQuantity,
    secondsLeft: secondsLeft ?? this.secondsLeft,
    booked: booked != null ? booked() : this.booked,
    saveFailed: saveFailed ?? this.saveFailed,
  );
}

/// Builds one person's order, auto-books it [kAutoBookDelay] after the last
/// change (paused while the quantity sheet is open) and commits it.
class OrderController extends Notifier<OrderState> {
  OrderController(this.personId);

  final String personId;
  Timer? _timer;

  /// A commit is being written; edits are ignored until it is done.
  bool _committing = false;

  @override
  OrderState build() {
    ref.onDispose(_cancelTimer);
    return OrderState(draft: OrderDraft.empty(personId));
  }

  /// Adds one of [drinkId]; [unitPriceCents] is kept from the first tap.
  /// The 3rd tap opens the quantity sheet.
  void tap(String drinkId, int unitPriceCents) {
    if (_committing || state.sheetDrinkId != null) return;
    final result = state.draft.tap(drinkId, unitPriceCents);
    state = state._copy(draft: result.draft);
    if (result.openQuantitySheet) {
      openSheet(drinkId);
    } else {
      _restartTimer();
    }
  }

  void openSheet(String drinkId) {
    if (_committing) return;
    final line = state.draft.lines.firstWhere((l) => l.drinkId == drinkId);
    _cancelTimer();
    state = state._copy(
      sheetDrinkId: () => drinkId,
      sheetQuantity: line.quantity,
    );
  }

  /// Sets the quantity in the open sheet (0..999).
  void setQuantity(int quantity) {
    if (_committing || state.sheetDrinkId == null) return;
    if (quantity < 0 || quantity > maxLineQuantity) {
      throw ArgumentError.value(quantity, 'quantity', 'must be 0..999');
    }
    state = state._copy(sheetQuantity: quantity);
  }

  /// Applies the sheet quantity, closes the sheet and restarts the timer.
  void closeSheet() {
    if (_committing || state.sheetDrinkId == null) return;
    state = OrderState(
      draft: state.effectiveDraft,
      saveFailed: state.saveFailed,
    );
    _restartTimer();
  }

  void discard() {
    if (_committing) return;
    _cancelTimer();
    state = OrderState(draft: OrderDraft.empty(personId));
  }

  /// Books every line (open sheet included) and triggers a sync. Does
  /// nothing for an empty order or while a commit is running. If the write
  /// fails the order is kept and retried after [kAutoBookDelay].
  Future<void> commit() async {
    if (_committing) return;
    _cancelTimer();
    final draft = state.effectiveDraft;
    state = OrderState(draft: OrderDraft.empty(personId));
    if (draft.isEmpty) return;

    final now = ref.read(clockProvider).now();
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
        ),
    ];
    final repository = ref.read(bookingRepositoryProvider);
    final sync = ref.read(syncServiceProvider);
    _committing = true;
    try {
      await repository.addAll(bookings);
    } on Object catch (e, st) {
      _log.severe('Writing the order failed', e, st);
      if (ref.mounted) {
        state = OrderState(draft: draft, saveFailed: true);
        _restartTimer();
      }
      return;
    } finally {
      _committing = false;
    }
    if (sync != null) {
      unawaited(
        sync.syncNow().catchError((Object e, StackTrace st) {
          _log.severe('Sync after booking failed', e, st);
        }),
      );
    }
    if (ref.mounted) state = state._copy(booked: () => draft);
  }

  void _restartTimer() {
    _cancelTimer();
    if (state.draft.isEmpty || state.sheetDrinkId != null) return;
    state = state._copy(secondsLeft: kAutoBookDelay.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = state.secondsLeft - 1;
      if (left <= 0) {
        unawaited(commit());
      } else {
        state = state._copy(secondsLeft: left);
      }
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

final orderControllerProvider = NotifierProvider.autoDispose
    .family<OrderController, OrderState, String>(OrderController.new);

import 'package:freezed_annotation/freezed_annotation.dart';

part 'order.freezed.dart';

@freezed
abstract class OrderLine with _$OrderLine {
  const factory OrderLine({
    required String drinkId,
    required int quantity,
    required int unitPriceCents,
  }) = _OrderLine;
}

/// Result of a tap: the new draft and whether the quantity sheet should open.
typedef TapResult = ({OrderDraft draft, bool openQuantitySheet});

const int maxLineQuantity = 999;

/// Immutable order being built for one person. Lines keep first-tap order and
/// a line's unit price is fixed at its first tap.
@immutable
class OrderDraft {
  const OrderDraft.empty(this.personId) : lines = const [];

  OrderDraft._(this.personId, List<OrderLine> lines)
    : lines = List.unmodifiable(lines);

  final String personId;
  final List<OrderLine> lines;

  bool get isEmpty => lines.isEmpty;

  int get totalCents =>
      lines.fold(0, (sum, l) => sum + l.quantity * l.unitPriceCents);

  /// Adds one of [drinkId]. [unitPriceCents] only applies if the drink is not
  /// yet in the draft. The quantity sheet opens when the quantity reaches 3.
  /// A line at [maxLineQuantity] stays there.
  TapResult tap(String drinkId, int unitPriceCents) {
    final index = lines.indexWhere((l) => l.drinkId == drinkId);
    if (index < 0) {
      final line = OrderLine(
        drinkId: drinkId,
        quantity: 1,
        unitPriceCents: unitPriceCents,
      );
      return (
        draft: OrderDraft._(personId, [...lines, line]),
        openQuantitySheet: false,
      );
    }
    final old = lines[index];
    if (old.quantity >= maxLineQuantity) {
      return (draft: this, openQuantitySheet: false);
    }
    final quantity = old.quantity + 1;
    final updated = [...lines]..[index] = old.copyWith(quantity: quantity);
    return (
      draft: OrderDraft._(personId, updated),
      openQuantitySheet: quantity == 3,
    );
  }

  /// Sets a line's quantity; 0 removes it. Throws [ArgumentError] outside
  /// 0..999 or for a drink not in the draft.
  OrderDraft setQuantity(String drinkId, int quantity) {
    if (quantity < 0 || quantity > maxLineQuantity) {
      throw ArgumentError.value(quantity, 'quantity', 'must be 0..999');
    }
    final index = lines.indexWhere((l) => l.drinkId == drinkId);
    if (index < 0) {
      throw ArgumentError.value(drinkId, 'drinkId', 'not in draft');
    }
    final updated = [...lines];
    if (quantity == 0) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].copyWith(quantity: quantity);
    }
    return OrderDraft._(personId, updated);
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/catalog.dart';
import '../../domain/quick_bar.dart';
import '../../l10n/app_localizations.dart';
import '../format.dart';
import '../providers.dart';
import '../theme.dart';
import 'drink_tile.dart';
import 'order_bar.dart';
import 'order_controller.dart';
import 'quick_bar.dart';
import 'quantity_sheet.dart';

const int _tilesPerRow = 7;
const double _gap = 10;

/// Drink selection for one person. Pops with the [BookedOrder] after a
/// commit, or with `null` when left without booking.
class DrinkSelectionScreen extends ConsumerStatefulWidget {
  const DrinkSelectionScreen({required this.personId, super.key});

  final String personId;

  @override
  ConsumerState<DrinkSelectionScreen> createState() =>
      _DrinkSelectionScreenState();
}

class _DrinkSelectionScreenState extends ConsumerState<DrinkSelectionScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _left = false;

  OrderController get _controller =>
      ref.read(orderControllerProvider(widget.personId).notifier);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: _bookPending,
      onPause: _bookPending,
    );
    // Providers must not change while the widget tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.start();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  bool get _hasPending => !ref
      .read(orderControllerProvider(widget.personId))
      .effectiveDraft
      .isEmpty;

  /// The tablet is put away: never leave an order unbooked.
  void _bookPending() {
    if (_hasPending) unawaited(_controller.commit());
  }

  void _otherPerson() {
    // A running commit pops by itself once written, or stays on failure.
    if (ref.read(orderControllerProvider(widget.personId)).committing) return;
    if (_hasPending) {
      unawaited(_controller.commit()); // pops once booked
    } else {
      _leave(null);
    }
  }

  void _leave(BookedOrder? booked) {
    if (_left) return;
    _left = true;
    Navigator.of(context).pop(booked);
  }

  @override
  Widget build(BuildContext context) {
    final provider = orderControllerProvider(widget.personId);
    ref.listen(provider, (previous, next) {
      final booked = next.booked;
      if (booked != null && !identical(booked, previous?.booked)) {
        _leave(booked);
      } else if (next.idleLeft && !(previous?.idleLeft ?? false)) {
        _leave(null);
      }
    });
    final order = ref.watch(provider);
    final catalog = ref.watch(catalogProvider).value;
    final person = catalog?.persons
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    final quickDrinks = catalog != null && person != null
        ? quickBarDrinks(catalog, person, ref.watch(rankingsProvider).value)
        : const <Drink>[];
    final draft = order.effectiveDraft;
    final sheetId = order.sheetDrinkId;

    // System back leaves like "Andere Person": a pending order is booked.
    return PopScope<BookedOrder>(
      canPop: draft.isEmpty && !order.committing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _otherPerson();
      },
      child: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _controller.activity(),
          onPointerMove: (_) => _controller.activity(),
          child: SafeArea(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(33, 22, 33, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        person: person,
                        tierName: catalog?.tiers
                            .where((t) => t.id == person?.priceTierId)
                            .firstOrNull
                            ?.name,
                        onOtherPerson: _otherPerson,
                      ),
                      if (catalog != null &&
                          person != null &&
                          quickDrinks.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: QuickBar(
                            drinks: quickDrinks,
                            priceOf: (d) => catalog.priceFor(d, person)!,
                            colorOf: (d) => Color(
                              catalog.groups
                                  .firstWhere((g) => g.id == d.groupId)
                                  .color,
                            ),
                            enabled:
                                order.draft.isEmpty &&
                                !order.committing &&
                                sheetId == null,
                            dimmed: !order.draft.isEmpty || sheetId != null,
                            onTap: (drink, price) => unawaited(
                              _controller.quickBook(drink.id, price),
                            ),
                          ),
                        ),
                      if (catalog != null && person != null)
                        Expanded(
                          child: _Groups(
                            catalog: catalog,
                            person: person,
                            quantities: {
                              for (final l in draft.lines)
                                l.drinkId: l.quantity,
                            },
                            onTap: (drink, price) =>
                                _controller.tap(drink.id, price),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!order.draft.isEmpty && sheetId == null)
                  Positioned(
                    left: 33,
                    right: 33,
                    bottom: 24,
                    child: OrderBar(
                      summary: orderSummary(
                        AppLocalizations.of(context),
                        order.draft,
                        catalog,
                      ),
                      totalCents: order.draft.totalCents,
                      secondsLeft: order.secondsLeft,
                      countdownRun: order.countdownRun,
                      saveFailed: order.saveFailed,
                      onDiscard: _controller.discard,
                      onDone: () => unawaited(_controller.commit()),
                    ),
                  ),
                if (sheetId != null) ...[
                  const Positioned.fill(
                    child: AbsorbPointer(
                      child: ColoredBox(color: Color(0x9916302A)),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: _sheet(catalog, order, sheetId),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheet(Catalog? catalog, OrderState order, String drinkId) {
    final drink = catalog?.drinks.where((d) => d.id == drinkId).firstOrNull;
    final group = catalog?.groups
        .where((g) => g.id == drink?.groupId)
        .firstOrNull;
    final line = order.draft.lines.firstWhere((l) => l.drinkId == drinkId);
    return QuantitySheet(
      key: ValueKey(drinkId),
      drinkName: drink?.name ?? '',
      unitPriceCents: line.unitPriceCents,
      crateSize: drink?.crateSize,
      quantity: order.sheetQuantity,
      orderTotalCents: order.effectiveDraft.totalCents,
      accent: group != null ? Color(group.color) : BarTabTheme.bottle3,
      onChanged: _controller.setQuantity,
      onMore: _controller.closeSheet,
      onBook: () => unawaited(_controller.commit()),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.person,
    required this.tierName,
    required this.onOtherPerson,
  });

  final Person? person;
  final String? tierName;
  final VoidCallback onOtherPerson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final person = this.person;
    final total = person == null
        ? null
        : ref.watch(runningTotalProvider(person.id)).value;
    return Container(
      padding: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BarTabTheme.bottle3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.center,
            child: Material(
              color: BarTabTheme.bottle3,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOtherPerson,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  child: Text(
                    l10n.drinkSelectionOtherPerson,
                    style: const TextStyle(
                      color: BarTabTheme.paper,
                      fontSize: 17,
                      fontVariations: [FontVariation('wght', 600)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 26),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  person?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BarTabTheme.paper,
                    fontSize: 56,
                    height: 0.95,
                    fontVariations: [
                      FontVariation('wdth', 118),
                      FontVariation('wght', 850),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tierName ?? '',
                  style: const TextStyle(
                    color: BarTabTheme.muted,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 26),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                total == null
                    ? l10n.drinkSelectionTotalLoading
                    : formatCents(total),
                style: const TextStyle(
                  color: BarTabTheme.paper,
                  fontSize: 38,
                  fontVariations: [
                    FontVariation('wdth', 90),
                    FontVariation('wght', 700),
                  ],
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                l10n.drinkSelectionTotalLabel,
                style: const TextStyle(color: BarTabTheme.muted, fontSize: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row per drink group: a rail with the group colour and name, then the
/// tiles, [_tilesPerRow] equal-width tiles per row.
class _Groups extends StatelessWidget {
  const _Groups({
    required this.catalog,
    required this.person,
    required this.quantities,
    required this.onTap,
  });

  final Catalog catalog;
  final Person person;
  final Map<String, int> quantities;
  final void Function(Drink drink, int priceCents) onTap;

  @override
  Widget build(BuildContext context) {
    final groups = catalog.drinksFor(person);
    return SingleChildScrollView(
      // Room for the order bar below the last group.
      padding: const EdgeInsets.only(top: 20, bottom: 120),
      child: Column(
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 19),
            _GroupRow(
              group: groups[i].$1,
              drinks: groups[i].$2,
              tile: (d) {
                // drinksFor only returns drinks priced for this person.
                final price = catalog.priceFor(d, person)!;
                return DrinkTile(
                  key: ValueKey('drink-${d.id}'),
                  name: d.name,
                  priceCents: price,
                  color: Color(groups[i].$1.color),
                  quantity: quantities[d.id] ?? 0,
                  onTap: () => onTap(d, price),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.drinks,
    required this.tile,
  });

  final DrinkGroup group;
  final List<Drink> drinks;
  final Widget Function(Drink) tile;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < drinks.length; i += _tilesPerRow) {
      final chunk = drinks.skip(i).take(_tilesPerRow).toList();
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : _gap),
          child: Row(
            children: [
              for (var j = 0; j < _tilesPerRow; j++) ...[
                if (j > 0) const SizedBox(width: _gap),
                Expanded(
                  child: j < chunk.length
                      ? tile(chunk[j])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 166,
            padding: const EdgeInsets.only(left: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(group.color), width: 7),
              ),
            ),
            child: Text(
              group.name,
              style: const TextStyle(
                color: BarTabTheme.paper,
                fontSize: 24,
                height: 1.05,
                fontVariations: [FontVariation('wght', 750)],
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(child: Column(children: rows)),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../domain/app_design.dart';
import '../../domain/booking.dart';
import '../../domain/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_gate.dart';
import '../common/sync_indicator.dart';
import '../design/chalk/chalk_board.dart';
import '../design/chalk/chalk_name_board.dart';
import '../design/coaster/coaster.dart';
import '../design/coaster/coaster_name_board.dart';
import '../design/coaster/counter_background.dart';
import '../design/design.dart';
import '../drinks/drink_selection_screen.dart';
import '../drinks/order_bar.dart';
import '../drinks/order_controller.dart';
import '../providers.dart';
import '../theme.dart';
import 'name_tile.dart';
import 'screensaver.dart';
import 'undo_banner.dart';

const double _gap = 8;
const double _columnTitleHeight = 32;

/// How a tier column lays out its name tiles.
class NameGridLayout {
  const NameGridLayout({
    required this.perRow,
    required this.tileHeight,
    required this.scrolls,
  });

  final int perRow;
  final double tileHeight;
  final bool scrolls;

  @override
  bool operator ==(Object other) =>
      other is NameGridLayout &&
      other.perRow == perRow &&
      other.tileHeight == tileHeight &&
      other.scrolls == scrolls;

  @override
  int get hashCode => Object.hash(perRow, tileHeight, scrolls);

  @override
  String toString() =>
      'NameGridLayout($perRow per row, $tileHeight high, scrolls: $scrolls)';
}

double _gridHeight(int names, int perRow, double tileHeight) {
  if (names == 0) return 0;
  final rows = (names + perRow - 1) ~/ perRow;
  return rows * tileHeight + (rows - 1) * _gap;
}

/// 3 per row at 64 high; if the tallest column does not fit
/// [availableHeight], 4 per row at 52 high; if it still does not fit, the
/// columns scroll (keeping the compact size).
NameGridLayout chooseLayout({
  required int maxNamesInColumn,
  required double availableHeight,
}) {
  const roomy = NameGridLayout(perRow: 3, tileHeight: 64, scrolls: false);
  const compact = NameGridLayout(perRow: 4, tileHeight: 52, scrolls: false);
  for (final l in [roomy, compact]) {
    if (_gridHeight(maxNamesInColumn, l.perRow, l.tileHeight) <=
        availableHeight) {
      return l;
    }
  }
  return const NameGridLayout(perRow: 4, tileHeight: 52, scrolls: true);
}

/// How long the note after a successful undo stays visible.
const kUndoDoneInfoDuration = Duration(seconds: 3);

/// How long the note after a failed (too late) undo stays visible.
const kUndoTooLateInfoDuration = Duration(seconds: 4);

/// After a quick booking the name list ignores taps for this long, so a
/// second tap on the quick tile cannot land on a name tile during the pop.
const kReturnTapGuard = Duration(milliseconds: 500);

final _log = Logger('names');

/// The latest order, undoable while its bookings are held.
class _UndoOffer {
  const _UndoOffer(this.text, this.bookingIds, this.holdUntil);

  final String text;
  final Set<String> bookingIds;

  /// The offer ends with the hold: "Rückgängig" is never shown after it.
  final DateTime holdUntil;
}

class NameListScreen extends ConsumerStatefulWidget {
  const NameListScreen({super.key});

  @override
  ConsumerState<NameListScreen> createState() => _NameListScreenState();
}

class _NameListScreenState extends ConsumerState<NameListScreen> {
  _UndoOffer? _offer;
  int _offerSecondsLeft = 0;
  bool _undoing = false;
  String? _info;

  /// Ends the offer at its hold's expiry, or ends the info note.
  Timer? _bannerTimer;

  /// Updates the offer's draining bar once per second.
  Timer? _tickTimer;

  /// Uploads the held bookings once the undo window is over.
  Timer? _syncTimer;

  /// Ends the tap guard after a quick booking.
  Timer? _guardTimer;
  bool _guarded = false;

  @override
  void dispose() {
    _guardTimer?.cancel();
    _bannerTimer?.cancel();
    _tickTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _open(Person p) async {
    final booked = await Navigator.of(context).push(
      MaterialPageRoute<BookedOrder>(
        builder: (_) => DrinkSelectionScreen(personId: p.id),
      ),
    );
    if (booked == null || !mounted) return;
    if (booked.quick) {
      // The screen is popping now: a second tap on the quick tile must not
      // land on a name tile below it.
      _guardTimer?.cancel();
      setState(() => _guarded = true);
      _guardTimer = Timer(kReturnTapGuard, () {
        setState(() => _guarded = false);
      });
    }
    final l10n = AppLocalizations.of(context);
    final catalog = ref.read(catalogProvider).value;
    _scheduleSync(_holdLeft(booked.holdUntil));
    _showOffer(
      _UndoOffer(
        l10n.nameListUndoBanner(
          p.name,
          orderSummary(l10n, booked.draft, catalog),
        ),
        booked.bookingIds,
        booked.holdUntil,
      ),
    );
  }

  void _openAdmin() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AdminGate()));
  }

  /// Time until [holdUntil], within 0..[kUndoWindow] (the clock may step).
  Duration _holdLeft(DateTime holdUntil) {
    final left = holdUntil.difference(ref.read(clockProvider).now());
    if (left.isNegative) return Duration.zero;
    return left > kUndoWindow ? kUndoWindow : left;
  }

  /// One second after the hold expires; a newer order's timer also covers
  /// the older one's bookings. This sync may join a run already in flight
  /// (which may have read the queue before the hold ended); the regular
  /// 30 s sync loop is the backstop.
  void _scheduleSync(Duration holdLeft) {
    _syncTimer?.cancel();
    _syncTimer = Timer(holdLeft + const Duration(seconds: 1), () {
      ref.read(syncServiceProvider)?.syncNow().catchError((
        Object e,
        StackTrace st,
      ) {
        _log.severe('Sync after the undo window failed', e, st);
      });
    });
  }

  /// Replaces whatever the banner shows: only the latest order is undoable.
  void _showOffer(_UndoOffer offer) {
    _bannerTimer?.cancel();
    _tickTimer?.cancel();
    final left = _holdLeft(offer.holdUntil);
    if (left == Duration.zero) {
      // Already expired (very slow write): nothing to offer.
      setState(() {
        _offer = null;
        _info = null;
      });
      return;
    }
    int secondsLeft() =>
        (_holdLeft(offer.holdUntil).inMilliseconds / 1000).ceil();
    setState(() {
      _offer = offer;
      _offerSecondsLeft = secondsLeft();
      _undoing = false;
      _info = null;
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _offerSecondsLeft = secondsLeft());
    });
    _bannerTimer = Timer(left, () {
      _tickTimer?.cancel();
      setState(() => _offer = null);
    });
  }

  void _showInfo(String text, Duration duration) {
    _bannerTimer?.cancel();
    _tickTimer?.cancel();
    setState(() {
      _offer = null;
      _info = text;
    });
    _bannerTimer = Timer(duration, () => setState(() => _info = null));
  }

  Future<void> _undo() async {
    final offer = _offer;
    if (offer == null || _undoing) return;
    // Stop the countdown: the answer must not be lost to the banner ending.
    _bannerTimer?.cancel();
    _tickTimer?.cancel();
    setState(() => _undoing = true);
    bool undone;
    try {
      undone = await ref
          .read(bookingRepositoryProvider)
          .undoHeld(offer.bookingIds);
    } on Object catch (e, st) {
      _log.severe('Undoing the order failed', e, st);
      undone = false;
    }
    // A newer order took over the banner meanwhile.
    if (!mounted || !identical(_offer, offer)) return;
    final l10n = AppLocalizations.of(context);
    if (undone) {
      _showInfo(l10n.nameListUndoDone, kUndoDoneInfoDuration);
    } else {
      _showInfo(l10n.nameListUndoTooLate, kUndoTooLateInfoDuration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogValue = ref.watch(catalogProvider);
    final design = ref.watch(appDesignProvider);
    final tokens = DesignTokens.of(context);
    // Keeps the rankings stream subscribed, so the quick bar is complete the
    // moment the drink screen opens (no layout shift).
    ref.listen(rankingsProvider, (_, _) {});
    final catalog = catalogValue.value;
    final collective = catalog?.collectiveAccounts() ?? const <Person>[];
    final tiers = catalog?.personsByTier() ?? const [];
    // Colour by position among all tiers, so hidden empty tiers keep theirs.
    final tierOrder = [...?catalog?.tiers]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    int tierIndex(PriceTier t) => tierOrder.indexWhere((o) => o.id == t.id);
    Color tierColor(PriceTier t) => BarTabTheme.tierColor(tierIndex(t));
    Color designTierColor(PriceTier t) => tokens.tierColor(tierIndex(t));
    final isEmpty = collective.isEmpty && tiers.isEmpty;
    final offer = _offer;
    final info = _info;

    // System back must never exit the kiosk app.
    return PopScope(
      canPop: false,
      child: IdleScreensaver(
        stayAwake: offer != null,
        child: Scaffold(
          body: AbsorbPointer(
            absorbing: _guarded,
            child: _Backdrop(
              design: design,
              child: SafeArea(
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.nameListTitle,
                                  style: _titleStyle(design, tokens),
                                ),
                              ),
                              IconButton(
                                key: const Key('admin-gear'),
                                icon: const Icon(Icons.settings),
                                iconSize: design == AppDesign.standard
                                    ? 24
                                    : 30,
                                color: switch (design) {
                                  AppDesign.standard => BarTabTheme.muted,
                                  AppDesign.kreidetafel => tokens.text,
                                  AppDesign.bierdeckel => kCoasterPaper,
                                },
                                onPressed: _openAdmin,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (catalogValue.isLoading && catalog == null)
                            const Spacer()
                          else if (isEmpty)
                            Expanded(
                              child: Center(
                                child: Text(
                                  l10n.nameListEmpty,
                                  style: TextStyle(
                                    color: tokens.muted,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            )
                          else if (design == AppDesign.kreidetafel)
                            Expanded(
                              child: ChalkNameBoard(
                                collective: collective,
                                tiers: tiers,
                                tierColor: designTierColor,
                                onTap: _open,
                                enabled: !_guarded,
                              ),
                            )
                          else if (design == AppDesign.bierdeckel)
                            Expanded(
                              child: CoasterNameBoard(
                                collective: collective,
                                tiers: tiers,
                                tierColor: designTierColor,
                                onTap: _open,
                                enabled: !_guarded,
                              ),
                            )
                          else ...[
                            if (collective.isNotEmpty) ...[
                              _CollectiveRow(
                                accounts: collective,
                                onTap: _open,
                              ),
                              const SizedBox(height: 16),
                            ],
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final layout = chooseLayout(
                                    maxNamesInColumn: tiers.fold(
                                      0,
                                      (m, t) =>
                                          t.$2.length > m ? t.$2.length : m,
                                    ),
                                    availableHeight:
                                        constraints.maxHeight -
                                        _columnTitleHeight,
                                  );
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (
                                        var i = 0;
                                        i < tiers.length;
                                        i++
                                      ) ...[
                                        if (i > 0) const SizedBox(width: 20),
                                        Expanded(
                                          child: _TierColumn(
                                            title: tiers[i].$1.name,
                                            accent: tierColor(tiers[i].$1),
                                            persons: tiers[i].$2,
                                            layout: layout,
                                            onTap: _open,
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                          const SizedBox(
                            height: 28,
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: SyncIndicator(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Over the title row, so the names never move when it shows.
                    if (offer != null || info != null)
                      Positioned(
                        top: 8,
                        right: 28,
                        child: offer != null
                            ? UndoBanner(
                                text: offer.text,
                                secondsLeft: _offerSecondsLeft,
                                onUndo: _undoing ? null : _undo,
                              )
                            : UndoInfo(info!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _titleStyle(AppDesign design, DesignTokens tokens) =>
    switch (design) {
      AppDesign.standard => const TextStyle(
        color: BarTabTheme.paper,
        fontSize: 30,
        height: 1.2,
        fontVariations: [
          FontVariation('wdth', 118),
          FontVariation('wght', 850),
        ],
      ),
      AppDesign.kreidetafel => TextStyle(
        fontFamily: tokens.displayFont,
        color: tokens.text,
        fontSize: 52,
        height: 1,
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700)],
      ),
      // Alfa Slab One has a single face: no weight.
      AppDesign.bierdeckel => TextStyle(
        fontFamily: tokens.displayFont,
        color: kCoasterPaper,
        fontSize: 38,
        height: 1.1,
        shadows: const [
          Shadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 3),
        ],
      ),
    };

/// The design's background behind the screen, as on the drink screen.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.design, required this.child});

  final AppDesign design;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (design) {
    AppDesign.standard => child,
    AppDesign.kreidetafel => ChalkBoard(child: child),
    AppDesign.bierdeckel => CounterBackground(child: child),
  };
}

class _ColumnTitle extends StatelessWidget {
  const _ColumnTitle(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _columnTitleHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 14,
            letterSpacing: 1.2,
            fontVariations: const [
              FontVariation('wdth', 100),
              FontVariation('wght', 750),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed row of collective accounts; never scrolls.
class _CollectiveRow extends StatelessWidget {
  const _CollectiveRow({required this.accounts, required this.onTap});

  final List<Person> accounts;
  final ValueChanged<Person> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColumnTitle(
          AppLocalizations.of(context).nameListCollective,
          BarTabTheme.collectiveAccent,
        ),
        Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final p in accounts)
              SizedBox(
                width: 200,
                child: NameTile(
                  person: p,
                  accent: BarTabTheme.collectiveAccent,
                  height: 52,
                  onTap: () => onTap(p),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TierColumn extends StatefulWidget {
  const _TierColumn({
    required this.title,
    required this.accent,
    required this.persons,
    required this.layout,
    required this.onTap,
  });

  final String title;
  final Color accent;
  final List<Person> persons;
  final NameGridLayout layout;
  final ValueChanged<Person> onTap;

  @override
  State<_TierColumn> createState() => _TierColumnState();
}

class _TierColumnState extends State<_TierColumn> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _tile(Person p) => NameTile(
    person: p,
    accent: widget.accent,
    height: widget.layout.tileHeight,
    onTap: () => widget.onTap(p),
  );

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final Widget grid;
    if (layout.scrolls) {
      grid = Stack(
        children: [
          GridView.count(
            controller: _controller,
            crossAxisCount: layout.perRow,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            mainAxisExtent: layout.tileHeight,
            padding: const EdgeInsets.only(bottom: 40),
            children: [for (final p in widget.persons) _tile(p)],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 40,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0016302A), BarTabTheme.bottle],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      final rows = <Widget>[];
      for (var i = 0; i < widget.persons.length; i += layout.perRow) {
        final chunk = widget.persons.skip(i).take(layout.perRow).toList();
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _gap),
            child: Row(
              children: [
                for (var j = 0; j < layout.perRow; j++) ...[
                  if (j > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: j < chunk.length
                        ? _tile(chunk[j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      grid = Column(children: rows);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColumnTitle(widget.title, widget.accent),
        if (layout.scrolls) Expanded(child: grid) else grid,
      ],
    );
  }
}

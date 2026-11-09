import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../data/api/dto.dart';
import '../../domain/catalog.dart';
import '../../domain/master_data.dart' as md;
import '../../domain/sync_state.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_route.dart';
import 'admin_session.dart';
import 'count_draft.dart';
import 'quantity_list.dart';
import 'settlement_review_screen.dart';

final _log = Logger('admin');

/// Server limit for one count (`MAX_COUNT`).
const int _maxCount = 99999;

typedef _Text = String Function(AppLocalizations l10n);

/// Counting the stock: step 2 of the settlement (then the review) or the
/// opening count before the first settlement (then saved). The counts are
/// kept as a local draft per [mode] until confirmed or discarded.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, required this.mode});

  final CountMode mode;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late final QuantityLines _lines = QuantityLines(
    maxLineUnits: _maxCount,
    crateSizeOf: (id) => _crateSizes[id] ?? 1,
  );

  StockDto? _stock;
  Map<String, int> _crateSizes = const {};

  /// Why the flow cannot go on; the list is not shown.
  _Text? _blocked;

  /// Shown above the list (failed bookings).
  _Text? _warning;

  /// A draft was restored on entry.
  bool _restored = false;
  bool _busy = false;

  /// Draft writes, in order.
  Future<void> _saving = Future.value();

  CountMode get _mode => widget.mode;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _lines.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_mode == CountMode.settlement) {
      final flush = await _flush();
      if (!mounted) return;
      if (flush == null || !flush.reachable) {
        return _block((l) => l.adminUnreachable);
      }
      if (flush.pending > 0) {
        return _block((l) => l.settlementPending(flush.pending));
      }
      if (flush.failed > 0) {
        _warning = (l) => l.settlementFailedBookings(flush.failed);
      }
    }
    final StockDto stock;
    try {
      stock = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.getStock(token));
    } on AdminSessionEndedException {
      return; // The session listener returns to the PIN prompt.
    } on ApiException catch (e) {
      _log.info('Stock not loaded: ${e.message}');
      if (mounted) _block((l) => l.adminUnreachable);
      return;
    }
    if (!mounted) return;
    if (_mode == CountMode.opening && !stock.openingCountAllowed) {
      return _block((l) => l.openingNotAllowed);
    }
    final draft = await _loadDraft();
    if (!mounted) return;
    if (draft != null) _lines.restore(draft);
    _lines.addListener(_saveDraft);
    setState(() {
      _stock = stock;
      _crateSizes = {for (final d in stock.drinks) d.drinkId: d.crateSize};
      _restored = stock.drinks.any((d) => _lines.hasEntry(d.drinkId));
    });
  }

  /// Pushes all queued bookings; null when that failed outright.
  Future<FlushResult?> _flush() async {
    try {
      return await ref.read(syncServiceProvider)?.flushForSettlement();
    } on Object catch (e, st) {
      _log.warning('Flush before settlement failed', e, st);
      return null;
    }
  }

  void _block(_Text reason) => setState(() => _blocked = reason);

  Future<Map<String, dynamic>?> _loadDraft() async {
    try {
      return await ref.read(countDraftStoreProvider).load(_mode);
    } on Object catch (e) {
      _log.warning('Count draft not readable: $e');
      return null;
    }
  }

  void _saveDraft() {
    final store = ref.read(countDraftStoreProvider);
    final json = _lines.isEmpty ? null : _lines.toJson();
    _saving = _saving
        .then(
          (_) => json == null ? store.clear(_mode) : store.save(_mode, json),
        )
        .catchError((Object e) => _log.warning('Count draft not saved: $e'));
  }

  /// The session ended: back to the gate, which shows the PIN prompt.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  /// Units per listed drink; null while a drink has no count.
  Map<String, int>? _counts(StockDto stock) {
    final counts = <String, int>{};
    for (final d in stock.drinks) {
      if (!_lines.hasEntry(d.drinkId)) return null;
      counts[d.drinkId] = md.unitsOf(
        crates: _lines.cratesOf(d.drinkId),
        units: _lines.unitsOf(d.drinkId),
        crateSize: d.crateSize,
      );
    }
    return counts;
  }

  Future<void> _discard() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AdminIdleGuard(
        child: AlertDialog(
          title: Text(l10n.countDiscardConfirm),
          actions: [
            TextButton(
              key: const Key('count-discard-cancel'),
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(l10n.adminCancel),
            ),
            FilledButton(
              key: const Key('count-discard-confirm'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(l10n.countDiscard),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    _lines.restore(const {});
    setState(() => _restored = false);
  }

  Future<void> _review(Map<String, int> counts) async {
    final closed = await Navigator.of(
      context,
    ).push<bool>(adminRoute((_) => SettlementReviewScreen(counts: counts)));
    if (closed != true || !mounted) return;
    _lines.removeListener(_saveDraft);
    Navigator.of(context).pop();
  }

  Future<void> _saveOpening(Map<String, int> counts) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Read before the request: the answer may come after this screen is gone.
    final drafts = ref.read(countDraftStoreProvider);
    setState(() => _busy = true);
    String? failure;
    try {
      await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.recordOpeningCount(token, counts));
    } on AdminSessionEndedException {
      if (mounted) setState(() => _busy = false);
      return;
    } on AlreadySettledException {
      failure = l10n.openingNotAllowed;
    } on NetworkException catch (e) {
      _log.info('Opening count unreachable: ${e.message}');
      failure = l10n.adminUnreachable;
    } on ApiException catch (e) {
      _log.info('Opening count failed: ${e.message}');
      failure = l10n.saveFailed;
    }
    if (failure != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure)));
      if (mounted) setState(() => _busy = false);
      return;
    }
    _lines.removeListener(_saveDraft);
    try {
      await (_saving = _saving.then((_) => drafts.clear(_mode)));
    } on Object catch (e) {
      _log.warning('Count draft not cleared: $e');
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.openingSaved)));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final stock = _stock;
    return AdminIdleGuard(
      // Not left while the opening count is saved: its answer clears the draft.
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _mode == CountMode.settlement
                  ? l10n.settlementTitle
                  : l10n.openingTitle,
            ),
            actions: [if (stock != null) ..._actions(l10n, stock)],
          ),
          body: _body(l10n, stock),
        ),
      ),
    );
  }

  List<Widget> _actions(AppLocalizations l10n, StockDto stock) => [
    TextButton(
      key: const Key('count-discard'),
      onPressed: _busy ? null : _discard,
      child: Text(l10n.countDiscard),
    ),
    const SizedBox(width: 8),
    ListenableBuilder(
      listenable: _lines,
      builder: (context, _) {
        final counts = _counts(stock);
        final opening = _mode == CountMode.opening;
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: FilledButton(
            key: Key(opening ? 'count-save' : 'count-review'),
            onPressed: counts == null || _busy
                ? null
                : () => opening ? _saveOpening(counts) : _review(counts),
            child: Text(opening ? l10n.dialogSave : l10n.countReview),
          ),
        );
      },
    ),
  ];

  Widget _body(AppLocalizations l10n, StockDto? stock) {
    final blocked = _blocked;
    if (blocked != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            blocked(l10n),
            key: const Key('count-blocked'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22),
          ),
        ),
      );
    }
    if (stock == null) return const Center(child: CircularProgressIndicator());
    final tokens = DesignTokens.of(context);
    final warning = _warning;
    final notes = [
      if (warning != null) warning(l10n),
      if (_restored) l10n.countDraftRestored,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              note,
              style: TextStyle(color: tokens.accent, fontSize: 18),
            ),
          ),
        Expanded(child: _list(stock)),
      ],
    );
  }

  /// The stock drinks in server order, as list entries of their groups.
  Widget _list(StockDto stock) {
    final groups = <String, DrinkGroup>{};
    final drinks = <Drink>[];
    for (final (i, d) in stock.drinks.indexed) {
      groups.putIfAbsent(
        d.groupId,
        () => DrinkGroup(
          id: d.groupId,
          name: d.groupName,
          sortOrder: groups.length,
          color: 0,
        ),
      );
      drinks.add(
        Drink(
          id: d.drinkId,
          name: d.name,
          groupId: d.groupId,
          crateSize: d.crateSize,
          sortOrder: i,
          isHidden: false,
          // Every listed drink is counted, inactive ones with stock too.
          isActive: true,
          prices: const {},
        ),
      );
    }
    return QuantityList(
      drinks: drinks,
      groups: groups.values.toList(),
      lines: _lines,
    );
  }
}

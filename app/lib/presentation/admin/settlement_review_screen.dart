import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../data/api/dto.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../format.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'count_draft.dart';

final _log = Logger('admin');

/// Step 3 of the settlement: the server's figures for [counts]; nothing is
/// stored until "Abrechnung abschließen". Pops with `true` once closed.
class SettlementReviewScreen extends ConsumerStatefulWidget {
  const SettlementReviewScreen({super.key, required this.counts});

  /// Units per drink id.
  final Map<String, int> counts;

  @override
  ConsumerState<SettlementReviewScreen> createState() =>
      _SettlementReviewScreenState();
}

class _SettlementReviewScreenState
    extends ConsumerState<SettlementReviewScreen> {
  SettlementReviewDto? _review;
  String Function(AppLocalizations)? _loadFailure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final review = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.reviewSettlement(token, widget.counts));
      if (mounted) setState(() => _review = review);
    } on AdminSessionEndedException {
      // The session listener returns to the PIN prompt.
    } on NetworkException catch (e) {
      _log.info('Review unreachable: ${e.message}');
      if (mounted) setState(() => _loadFailure = (l) => l.adminUnreachable);
    } on ApiException catch (e) {
      _log.info('Review failed: ${e.message}');
      if (mounted) setState(() => _loadFailure = (l) => l.settlementFailed);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The session ended: back to the gate, which shows the PIN prompt.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  Future<void> _close(SettlementReviewDto review) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AdminIdleGuard(
        child: AlertDialog(
          title: Text(l10n.settlementCloseConfirm),
          actions: [
            TextButton(
              key: const Key('settlement-close-cancel'),
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(l10n.adminCancel),
            ),
            FilledButton(
              key: const Key('settlement-close-confirm'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(l10n.settlementClose),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    // Read before the request: the answer may come after this screen is gone.
    final drafts = ref.read(countDraftStoreProvider);
    setState(() => _busy = true);
    try {
      final closed = await ref
          .read(adminSessionProvider.notifier)
          .run(
            (api, token) =>
                api.closeSettlement(token, review.token, widget.counts),
          );
      await _clearDraft(drafts);
      if (!mounted) return;
      _toast(switch (closed.mailStatus) {
        MailStatus.sent => l10n.settlementDoneSent,
        MailStatus.failed => l10n.settlementDoneMailFailed,
        MailStatus.skipped => l10n.settlementDoneNoMail,
        MailStatus.pending => l10n.settlementDone,
      });
      Navigator.of(context).pop(true);
      return;
    } on AdminSessionEndedException {
      // The session listener returns to the PIN prompt.
    } on StaleReviewException {
      if (!mounted) return;
      _toast(l10n.settlementStale);
      setState(() => _review = null);
      await _load();
    } on NetworkException catch (e) {
      // The close may have happened; the same token replays it safely.
      _log.info('Close without answer: ${e.message}');
      if (mounted) _toast(l10n.settlementCloseUnclear);
    } on ApiException catch (e) {
      _log.info('Close failed: ${e.message}');
      if (mounted) _toast(l10n.settlementFailed);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The period is closed: the counts are done with.
  Future<void> _clearDraft(CountDraftStore drafts) async {
    try {
      await drafts.clear(CountMode.settlement);
    } on Object catch (e) {
      _log.warning('Count draft not cleared: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final review = _review;
    final failure = _loadFailure;
    return AdminIdleGuard(
      // Not left while the close runs: its answer clears the draft.
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.reviewTitle),
            actions: [
              TextButton(
                key: const Key('review-back'),
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(l10n.reviewBack),
              ),
              const SizedBox(width: 8),
              if (review != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: FilledButton(
                    key: const Key('settlement-close'),
                    onPressed: _busy ? null : () => _close(review),
                    child: Text(l10n.settlementClose),
                  ),
                ),
            ],
          ),
          body: failure != null
              ? Center(child: Text(failure(l10n)))
              : review == null
              ? const Center(child: CircularProgressIndicator())
              : _ReviewTable(review: review),
        ),
      ),
    );
  }
}

class _ReviewTable extends StatelessWidget {
  const _ReviewTable({required this.review});

  final SettlementReviewDto review;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final muted = TextStyle(color: tokens.muted, fontSize: 16);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        _Row(
          name: '',
          cells: [
            l10n.reviewExpected,
            l10n.reviewCounted,
            l10n.reviewShrinkage,
            l10n.reviewValue,
          ],
          style: muted,
        ),
        for (final g in review.groups) ...[
          for (final d in review.drinks)
            if (d.groupId == g.groupId)
              _Row(
                key: Key('review-drink-${d.drinkId}'),
                name: d.name,
                noPrice: !d.hasPrice,
                cells: [
                  '${d.expected}',
                  '${d.counted}',
                  '${d.shrinkage}',
                  formatCents(d.valueCents),
                ],
                style: TextStyle(color: tokens.text, fontSize: 18),
              ),
          _Row(
            key: Key('review-group-${g.groupId}'),
            name: g.name,
            noPrice: !g.hasPrice,
            cells: [
              '${g.expected}',
              '${g.counted}',
              '${g.shrinkage}',
              formatCents(g.valueCents),
            ],
            style: TextStyle(
              color: tokens.text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(),
        ],
        const SizedBox(height: 8),
        _Total(
          key: const Key('review-total-persons'),
          label: l10n.reviewPersonsTotal,
          cents: review.personsTotalCents,
        ),
        _Total(
          key: const Key('review-total-hidden'),
          label: l10n.reviewHiddenTotal,
          cents: review.hiddenTotalCents,
        ),
        _Total(
          key: const Key('review-total-grand'),
          label: l10n.reviewGrandTotal,
          cents: review.grandTotalCents,
          bold: true,
        ),
        _Total(
          key: const Key('review-total-shrinkage'),
          label: l10n.reviewShrinkageTotal,
          note: l10n.reviewValuedWith(review.valuationTierName),
          cents: review.shrinkageTotalCents,
          bold: true,
        ),
      ],
    );
  }
}

/// A name and four right-aligned figures; [noPrice] adds the marker.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.name,
    required this.cells,
    required this.style,
    this.noPrice = false,
  });

  final String name;
  final List<String> cells;
  final TextStyle style;
  final bool noPrice;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(name, style: style)),
          if (noPrice)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                AppLocalizations.of(context).reviewNoPrice,
                style: TextStyle(color: tokens.accent, fontSize: 16),
              ),
            ),
          for (final cell in cells)
            SizedBox(
              width: 130,
              child: Text(cell, textAlign: TextAlign.end, style: style),
            ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    super.key,
    required this.label,
    required this.cents,
    this.note,
    this.bold = false,
  });

  final String label;
  final int cents;
  final String? note;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final style = TextStyle(
      color: tokens.text,
      fontSize: 20,
      fontWeight: bold ? FontWeight.bold : null,
    );
    final note = this.note;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                note,
                style: TextStyle(color: tokens.muted, fontSize: 16),
              ),
            ),
          SizedBox(
            width: 160,
            child: Text(
              formatCents(cents),
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

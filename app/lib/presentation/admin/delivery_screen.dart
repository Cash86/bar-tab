import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../data/api/api_client.dart';
import '../../data/api/dto.dart';
import '../../domain/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'quantity_list.dart';

final _log = Logger('admin');
const _uuid = Uuid();

/// Record a delivery: crates and units per drink, booked in one batch.
class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key});

  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  final QuantityLines _lines = QuantityLines();

  /// Request ids of the last attempt by drink id, kept so a retry after a
  /// lost answer is recognised by the server instead of booked twice.
  Map<String, DeliveryInDto> _attempt = {};
  bool _busy = false;

  @override
  void dispose() {
    _lines.dispose();
    super.dispose();
  }

  /// The session ended: back to the gate, which shows the PIN prompt.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
  }

  Map<String, int> _totals(Catalog catalog) =>
      _lines.totals({for (final d in catalog.drinks) d.id: d.crateSize});

  Future<void> _book(Catalog catalog) async {
    final totals = _totals(catalog);
    if (totals.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AdminIdleGuard(
        child: AlertDialog(
          content: Text(
            l10n.deliveryConfirm(
              totals.length,
              totals.values.fold(0, (a, b) => a + b),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('delivery-confirm-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.adminCancel),
            ),
            FilledButton(
              key: const Key('delivery-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.deliveryConfirmAction),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    // One id per line, reused while the line is unchanged since a failed try.
    final previous = _attempt;
    _attempt = {
      for (final e in totals.entries)
        e.key: previous[e.key]?.quantity == e.value
            ? previous[e.key]!
            : DeliveryInDto(id: _uuid.v4(), drinkId: e.key, quantity: e.value),
    };
    final items = _attempt.values.toList();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    String? failure;
    try {
      await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.createDeliveries(token, items));
    } on AdminSessionEndedException {
      if (mounted) setState(() => _busy = false);
      return;
    } on NetworkException catch (e) {
      _log.info('Delivery unreachable: ${e.message}');
      failure = l10n.adminUnreachable;
    } on ApiException catch (e) {
      _log.info('Delivery failed: ${e.message}');
      failure = l10n.deliveryFailed;
    }
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
      if (mounted) setState(() => _busy = false);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.deliveryDone)));
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(catalogProvider).value;
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.deliveryTitle),
          actions: [
            if (catalog != null)
              ListenableBuilder(
                listenable: _lines,
                builder: (context, _) {
                  final count = _totals(catalog).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: FilledButton(
                      key: const Key('delivery-submit'),
                      onPressed: count == 0 || _busy
                          ? null
                          : () => _book(catalog),
                      child: Text(l10n.deliveryBook(count)),
                    ),
                  );
                },
              ),
          ],
        ),
        body: catalog == null
            ? const Center(child: CircularProgressIndicator())
            : QuantityList(
                drinks: catalog.drinks,
                groups: catalog.groups,
                lines: _lines,
              ),
      ),
    );
  }
}

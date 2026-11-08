import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../data/api/mappers.dart';
import '../../domain/catalog.dart';
import '../../domain/delivery.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../format.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'storno_confirm.dart';

final _log = Logger('admin');

/// Deliveries of the open period, newest first, with storno.
class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  List<Delivery>? _deliveries;
  bool _loadFailed = false;

  /// Bumped per load: only the latest answer is shown.
  int _loadGeneration = 0;

  /// Deliveries with a storno in progress (dialog open or request running).
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  void _reload() {
    setState(() {
      _deliveries = null;
      _loadFailed = false;
    });
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    final generation = ++_loadGeneration;
    try {
      final dtos = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.listDeliveries(token));
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _deliveries = [for (final d in dtos) deliveryFromDto(d)]);
    } on AdminSessionEndedException {
      // The session listener returns to the PIN prompt.
    } on ApiException catch (e) {
      _log.info('Deliveries not loaded: ${e.message}');
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadFailed = true);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _storno(Delivery delivery, String summary) async {
    if (_busy.contains(delivery.id)) return;
    setState(() => _busy.add(delivery.id));
    try {
      final confirmed = await confirmStorno(
        context,
        title: AppLocalizations.of(context).deliveriesStornoConfirm,
        summary: summary,
      );
      if (!confirmed || !mounted) return;
      final dto = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.cancelDelivery(token, delivery.id));
      if (!mounted) return;
      final updated = deliveryFromDto(dto);
      setState(() {
        _deliveries = [
          for (final d in _deliveries ?? const <Delivery>[])
            d.id == updated.id ? updated : d,
        ];
      });
      _toast(AppLocalizations.of(context).deliveriesStornoDone);
    } on AdminSessionEndedException {
      // The session listener returns to the PIN prompt.
    } on RejectedException catch (e) {
      _log.info('Delivery storno refused: ${e.detail}');
      if (!mounted) return;
      _toast(AppLocalizations.of(context).adminStornoFailed);
      _reload();
    } on NetworkException catch (e) {
      _log.info('Delivery storno unreachable: ${e.message}');
      if (!mounted) return;
      _toast(AppLocalizations.of(context).adminUnreachable);
    } on ApiException catch (e) {
      _log.warning('Delivery storno failed: ${e.message}');
      if (!mounted) return;
      _toast(AppLocalizations.of(context).adminStornoFailed);
    } finally {
      if (mounted) setState(() => _busy.remove(delivery.id));
    }
  }

  /// The session ended (server restart, expiry): back to the gate, which
  /// shows the PIN prompt. Already gone when the idle logout left the area.
  void _leave() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r == route);
    navigator.pop();
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
        appBar: AppBar(title: Text(l10n.deliveriesTitle)),
        body: _body(l10n, catalog),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, Catalog? catalog) {
    if (_loadFailed) return Center(child: Text(l10n.adminUnreachable));
    final deliveries = _deliveries;
    if (deliveries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (deliveries.isEmpty) {
      return Center(child: Text(l10n.deliveriesEmpty));
    }
    final drinks = {
      for (final d in catalog?.drinks ?? const <Drink>[]) d.id: d,
    };
    return ListView.builder(
      itemCount: deliveries.length,
      itemBuilder: (context, i) {
        final d = deliveries[i];
        final drink = drinks[d.drinkId];
        return _DeliveryRow(
          delivery: d,
          drinkName: drink?.name ?? d.drinkId,
          units: _units(l10n, d.quantity, drink?.crateSize ?? 1),
          busy: _busy.contains(d.id),
          onStorno: _storno,
        );
      },
    );
  }
}

/// Units with the split into crates and singles, recomputed from the drink's
/// current crate size. No split below one crate.
String _units(AppLocalizations l10n, int units, int crateSize) {
  if (crateSize <= 1 || units < crateSize) return '$units';
  final crates = l10n.quantityCratesField(units ~/ crateSize);
  final rest = units % crateSize;
  return rest == 0
      ? l10n.deliveryUnits(units, crates)
      : l10n.deliveryUnitsWithRest(units, crates, rest);
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({
    required this.delivery,
    required this.drinkName,
    required this.units,
    required this.busy,
    required this.onStorno,
  });

  final Delivery delivery;
  final String drinkName;
  final String units;
  final bool busy;
  final void Function(Delivery delivery, String summary) onStorno;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final d = delivery;
    final cancelled = d.cancelledAt != null;
    final time = formatBookingTime(d.createdAt);
    final summary = l10n.deliveriesStornoSummary(time, drinkName, units);
    return Padding(
      key: Key('delivery-${d.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 18,
          color: cancelled ? DesignTokens.of(context).muted : null,
        ),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(time)),
            Expanded(flex: 3, child: Text(drinkName)),
            SizedBox(width: 200, child: Text(units, textAlign: TextAlign.end)),
            SizedBox(
              width: 140,
              child: cancelled
                  ? Text(l10n.adminCancelled, textAlign: TextAlign.center)
                  : TextButton(
                      key: Key('storno-${d.id}'),
                      onPressed: busy ? null : () => onStorno(d, summary),
                      child: Text(l10n.adminStorno),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

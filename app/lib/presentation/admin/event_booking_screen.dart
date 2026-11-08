import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../data/api/api_client.dart';
import '../../data/api/dto.dart';
import '../../domain/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../design/design.dart';
import '../format.dart';
import '../providers.dart';
import 'admin_idle.dart';
import 'admin_session.dart';
import 'quantity_list.dart';

final _log = Logger('admin');
const _uuid = Uuid();

/// Server limit for the quantity of one booking line.
const int _maxLineUnits = 999;

/// One line of the last attempt: its request id and what it was sent with.
/// The server compares `booked_at` too, so a retry must reuse it.
typedef _Sent = ({String id, int quantity, int price, DateTime bookedAt});

/// Book quantities of many drinks on one person: pick the person, then enter
/// crates and units per drink. Goes online at once, without the undo hold and
/// without the offline queue.
class EventBookingScreen extends ConsumerStatefulWidget {
  const EventBookingScreen({super.key});

  @override
  ConsumerState<EventBookingScreen> createState() => _EventBookingScreenState();
}

class _EventBookingScreenState extends ConsumerState<EventBookingScreen> {
  QuantityLines? _lines;
  Person? _person;

  /// Request ids of the last attempt by drink id, kept so a retry after a
  /// lost answer is recognised by the server instead of booked twice.
  Map<String, _Sent> _attempt = {};
  bool _busy = false;

  @override
  void dispose() {
    _lines?.dispose();
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

  void _choose(Person person, Catalog catalog) {
    final sizes = {for (final d in catalog.drinks) d.id: d.crateSize};
    setState(() {
      _lines?.dispose();
      _lines = QuantityLines(
        maxLineUnits: _maxLineUnits,
        crateSizeOf: (id) => sizes[id] ?? 1,
      );
      _attempt = {};
      _person = person;
    });
  }

  /// Back to step 1; nothing entered is kept.
  void _changePerson() {
    setState(() {
      _lines?.dispose();
      _lines = null;
      _attempt = {};
      _person = null;
    });
  }

  /// Single units and unit price per drink id with a quantity and a price.
  Map<String, ({int units, int price})> _lineData(
    Catalog catalog,
    Person person,
  ) {
    final totals = _lines!.totals({
      for (final d in catalog.drinks) d.id: d.crateSize,
    });
    final prices = {for (final d in catalog.drinks) d.id: d.prices};
    return {
      for (final e in totals.entries)
        if (prices[e.key]?[person.priceTierId] case final price?)
          e.key: (units: e.value, price: price),
    };
  }

  /// Names of entered drinks without a price for the person's tier; while
  /// there are any, nothing can be booked.
  List<String> _unpriced(Catalog catalog, Person person) {
    final totals = _lines!.totals({
      for (final d in catalog.drinks) d.id: d.crateSize,
    });
    return [
      for (final d in catalog.drinks)
        if (totals.containsKey(d.id) && d.prices[person.priceTierId] == null)
          d.name,
    ];
  }

  int _sum(Map<String, ({int units, int price})> lines) =>
      lines.values.fold(0, (a, l) => a + l.units * l.price);

  Future<void> _book(Catalog catalog, Person person) async {
    final data = _lineData(catalog, person);
    if (data.isEmpty || _busy || _unpriced(catalog, person).isNotEmpty) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AdminIdleGuard(
        child: AlertDialog(
          content: Text(
            l10n.eventConfirm(
              person.name,
              data.length,
              formatCents(_sum(data)),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('event-confirm-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.adminCancel),
            ),
            FilledButton(
              key: const Key('event-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.deliveryConfirmAction),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    // One id and time per line, reused while the line is unchanged since a
    // failed try; a changed line is a new booking, booked now.
    final previous = _attempt;
    final now = ref.read(clockProvider).now();
    _attempt = {
      for (final e in data.entries)
        e.key:
            previous[e.key]?.quantity == e.value.units &&
                previous[e.key]?.price == e.value.price
            ? previous[e.key]!
            : (
                id: _uuid.v4(),
                quantity: e.value.units,
                price: e.value.price,
                bookedAt: now,
              ),
    };
    final bookings = [
      for (final e in _attempt.entries)
        BookingInDto(
          id: e.value.id,
          personId: person.id,
          drinkId: e.key,
          quantity: e.value.quantity,
          unitPriceCents: e.value.price,
          bookedAt: e.value.bookedAt,
        ),
    ];
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final api = ref.read(apiProvider);
    setState(() => _busy = true);
    String? failure;
    try {
      if (api == null) throw const NetworkException('Not paired');
      final results = await api.postBookings(bookings);
      final ok =
          results.length == bookings.length &&
          results.every(
            (r) =>
                r.status == BookingResultStatus.accepted ||
                r.status == BookingResultStatus.duplicate,
          );
      if (!ok) {
        _log.info(
          'Event booking refused: ${[for (final r in results) r.status]}',
        );
        failure = l10n.eventFailed;
      }
    } on NetworkException catch (e) {
      _log.info('Event booking unreachable: ${e.message}');
      failure = l10n.adminUnreachable;
    } on ApiException catch (e) {
      _log.info('Event booking failed: ${e.message}');
      failure = l10n.eventFailed;
    }
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
      if (mounted) setState(() => _busy = false);
      return;
    }
    final sync = ref.read(syncServiceProvider);
    if (sync != null) {
      unawaited(
        sync.syncNow().catchError((Object e, StackTrace st) {
          _log.warning('Sync after event booking failed', e, st);
        }),
      );
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.eventDone)));
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(adminSessionProvider, (_, token) {
      if (token == null) _leave();
    });
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(catalogProvider).value;
    final person = _person;
    final lines = _lines;
    if (catalog == null) {
      return AdminIdleGuard(
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.eventTitle)),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (person == null || lines == null) {
      return AdminIdleGuard(
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.eventPickPerson)),
          body: _Picker(catalog: catalog, onPick: (p) => _choose(p, catalog)),
        ),
      );
    }
    final tier = catalog.tiers
        .where((t) => t.id == person.priceTierId)
        .map((t) => t.name)
        .firstOrNull;
    final prices = {for (final d in catalog.drinks) d.id: d.prices};
    return AdminIdleGuard(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.eventPerson(person.name, tier ?? '')),
          actions: [
            TextButton(
              key: const Key('event-change-person'),
              onPressed: _busy ? null : _changePerson,
              child: Text(l10n.eventChangePerson),
            ),
            ListenableBuilder(
              listenable: lines,
              builder: (context, _) {
                final data = _lineData(catalog, person);
                final blocked = _unpriced(catalog, person).isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.only(left: 8, right: 16),
                  child: FilledButton(
                    key: const Key('event-submit'),
                    onPressed: data.isEmpty || _busy || blocked
                        ? null
                        : () => _book(catalog, person),
                    child: Text(l10n.eventBook(formatCents(_sum(data)))),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: lines,
              builder: (context, _) {
                final unpriced = _unpriced(catalog, person);
                if (unpriced.isEmpty) return const SizedBox.shrink();
                return Padding(
                  key: const Key('event-unpriced'),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    l10n.eventUnpriced(tier ?? '', unpriced.join(', ')),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 18,
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: QuantityList(
                drinks: catalog.drinks,
                groups: catalog.groups,
                lines: lines,
                trailing: (drink, units) => formatCents(
                  units * (prices[drink.id]?[person.priceTierId] ?? 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.catalog, required this.onPick});

  final Catalog catalog;
  final void Function(Person) onPick;

  /// Hidden first, then collective, then the rest; each alphabetical.
  List<Person> _ordered() {
    int rank(Person p) => p.isHidden ? 0 : (p.isCollective ? 1 : 2);
    final byName = catalog.allPersonsByName().where((p) => p.isActive);
    return [
      for (final r in [0, 1, 2])
        for (final p in byName)
          if (rank(p) == r) p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final tiers = {for (final t in catalog.tiers) t.id: t.name};
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        for (final p in _ordered())
          ListTile(
            key: Key('event-person-${p.id}'),
            title: Text(
              p.name,
              style: TextStyle(color: tokens.text, fontSize: 22),
            ),
            trailing: Text(
              tiers[p.priceTierId] ?? '',
              style: TextStyle(color: tokens.muted, fontSize: 18),
            ),
            onTap: () => onPick(p),
          ),
      ],
    );
  }
}

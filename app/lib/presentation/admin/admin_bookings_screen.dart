import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../data/api/api_client.dart';
import '../../data/api/mappers.dart';
import '../../domain/admin_booking.dart';
import '../../domain/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../format.dart';
import '../providers.dart';
import '../theme.dart';
import 'admin_idle.dart';
import 'admin_session.dart';

final _log = Logger('admin');

/// Filter value for "all persons".
const _all = '';

/// Bookings of the open period, newest first, with storno.
class AdminBookingsScreen extends ConsumerStatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  ConsumerState<AdminBookingsScreen> createState() =>
      _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends ConsumerState<AdminBookingsScreen> {
  String _personId = _all;
  List<AdminBooking>? _bookings;
  bool _loadFailed = false;

  /// Bumped per load: only the latest answer is shown.
  int _loadGeneration = 0;

  /// Bookings with a storno in progress (dialog open or request running).
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  void _reload() {
    setState(() {
      _bookings = null;
      _loadFailed = false;
    });
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    final generation = ++_loadGeneration;
    final personId = _personId == _all ? null : _personId;
    try {
      final dtos = await ref
          .read(adminSessionProvider.notifier)
          .run(
            (api, token) => api.listAdminBookings(token, personId: personId),
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => _bookings = [for (final d in dtos) adminBookingFromDto(d)],
      );
    } on AdminSessionEndedException {
      // The session listener returns to the PIN prompt.
    } on ApiException catch (e) {
      _log.info('Admin bookings not loaded: ${e.message}');
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadFailed = true);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _storno(AdminBooking booking, String summary) async {
    if (_busy.contains(booking.id)) return;
    setState(() => _busy.add(booking.id));
    try {
      if (!await _confirm(summary) || !mounted) return;
      final dto = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.cancelBooking(token, booking.id));
      if (!mounted) return;
      final updated = adminBookingFromDto(dto);
      setState(() {
        _bookings = [
          for (final b in _bookings ?? const <AdminBooking>[])
            b.id == updated.id ? updated : b,
        ];
      });
      _toast(AppLocalizations.of(context).adminStornoDone);
      // Tabs on the name list drop the cancelled amount right away.
      final sync = ref.read(syncServiceProvider);
      if (sync != null) {
        unawaited(
          sync.syncNow().onError<Object>((e, st) {
            _log.warning('Sync after storno failed', e, st);
          }),
        );
      }
    } on AdminSessionEndedException {
      // The session listener returns to the PIN prompt.
    } on BookingNotCancellableException catch (e) {
      _log.info('Storno refused: ${e.reason}');
      if (!mounted) return;
      _toast(AppLocalizations.of(context).adminStornoFailed);
      _reload();
    } on NetworkException catch (e) {
      _log.info('Storno unreachable: ${e.message}');
      if (!mounted) return;
      _toast(AppLocalizations.of(context).adminUnreachable);
    } on ApiException catch (e) {
      _log.warning('Storno failed: ${e.message}');
      if (!mounted) return;
      _toast(AppLocalizations.of(context).adminStornoFailed);
    } finally {
      if (mounted) setState(() => _busy.remove(booking.id));
    }
  }

  Future<bool> _confirm(String summary) async {
    final l10n = AppLocalizations.of(context);
    // A second tap during the closing animation must not pop this screen.
    var answered = false;
    void answer(BuildContext dialogContext, bool value) {
      if (answered) return;
      answered = true;
      Navigator.of(dialogContext).pop(value);
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminIdleGuard(
        child: AlertDialog(
          title: Text(l10n.adminStornoConfirm),
          content: Text(summary),
          actions: [
            TextButton(
              key: const Key('storno-dialog-cancel'),
              onPressed: () => answer(dialogContext, false),
              child: Text(l10n.adminCancel),
            ),
            FilledButton(
              key: const Key('storno-dialog-confirm'),
              onPressed: () => answer(dialogContext, true),
              child: Text(l10n.adminStorno),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
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
        appBar: AppBar(title: Text(l10n.adminBookings)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DropdownButton<String>(
                  key: const Key('admin-person-filter'),
                  value: _personId,
                  items: [
                    DropdownMenuItem(
                      value: _all,
                      child: Text(l10n.adminFilterAll),
                    ),
                    for (final p
                        in catalog?.allPersonsByName() ?? const <Person>[])
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _personId = value;
                    _reload();
                  },
                ),
              ),
            ),
            Expanded(child: _body(l10n, catalog)),
          ],
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, Catalog? catalog) {
    if (_loadFailed) return Center(child: Text(l10n.adminUnreachable));
    final bookings = _bookings;
    if (bookings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (bookings.isEmpty) return Center(child: Text(l10n.adminBookingsEmpty));
    final persons = {
      for (final p in catalog?.persons ?? const <Person>[]) p.id: p.name,
    };
    final drinks = {
      for (final d in catalog?.drinks ?? const <Drink>[]) d.id: d.name,
    };
    return ListView.builder(
      itemCount: bookings.length,
      itemBuilder: (context, i) {
        final b = bookings[i];
        return _BookingRow(
          booking: b,
          person: persons[b.personId] ?? b.personId,
          drink: drinks[b.drinkId] ?? b.drinkId,
          busy: _busy.contains(b.id),
          onStorno: _storno,
        );
      },
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({
    required this.booking,
    required this.person,
    required this.drink,
    required this.busy,
    required this.onStorno,
  });

  final AdminBooking booking;
  final String person;
  final String drink;
  final bool busy;
  final void Function(AdminBooking booking, String summary) onStorno;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final b = booking;
    final time = formatBookingTime(b.bookedAt);
    final amount = formatCents(b.amountCents);
    final summary = l10n.adminStornoSummary(
      time,
      person,
      l10n.orderLine(b.quantity, drink),
      amount,
    );
    return Padding(
      key: Key('booking-${b.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 18,
          color: b.isCancelled ? BarTabTheme.muted : null,
        ),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(time)),
            Expanded(flex: 3, child: Text(person)),
            Expanded(flex: 3, child: Text(drink)),
            SizedBox(
              width: 60,
              child: Text(
                l10n.adminQuantity(b.quantity),
                textAlign: TextAlign.end,
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                formatCents(b.unitPriceCents),
                textAlign: TextAlign.end,
              ),
            ),
            SizedBox(width: 110, child: Text(amount, textAlign: TextAlign.end)),
            SizedBox(
              width: 110,
              child: b.isLate
                  ? Text(
                      l10n.adminLate,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    )
                  : null,
            ),
            SizedBox(
              width: 140,
              child: b.isCancelled
                  ? Text(l10n.adminCancelled, textAlign: TextAlign.center)
                  : TextButton(
                      key: Key('storno-${b.id}'),
                      onPressed: busy ? null : () => onStorno(b, summary),
                      child: Text(l10n.adminStorno),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

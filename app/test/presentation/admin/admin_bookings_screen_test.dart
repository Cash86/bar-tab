import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/data/sync/sync_service.dart';
import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/domain/repositories.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/admin_bookings_screen.dart';
import 'package:bar_tab/presentation/admin/admin_session.dart';
import 'package:bar_tab/presentation/format.dart';
import 'package:bar_tab/presentation/kiosk.dart';
import 'package:bar_tab/presentation/names/name_list_screen.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:bar_tab/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../fixtures/fakes.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _idle = Duration(seconds: 10);

Person _person(
  String id,
  String name, {
  bool hidden = false,
  bool active = true,
}) => Person(
  id: id,
  name: name,
  priceTierId: 't1',
  isHidden: hidden,
  isCollective: false,
  isActive: active,
);

Drink _drink(String id, String name) => Drink(
  id: id,
  name: name,
  groupId: 'g1',
  crateSize: 20,
  sortOrder: 1,
  isHidden: false,
  isActive: true,
  prices: const {'t1': 150},
);

final _catalog = Catalog(
  tiers: const [PriceTier(id: 't1', name: 'Members', sortOrder: 1)],
  persons: [
    _person('p1', 'Kim Example'),
    _person('p2', 'Bo Sample', hidden: true),
    _person('p3', 'Ann Old', active: false),
  ],
  groups: const [
    DrinkGroup(id: 'g1', name: 'Beer', sortOrder: 1, color: 0xFF445566),
  ],
  drinks: [_drink('d1', 'Lager'), _drink('d2', 'Cola')],
  etag: 'e',
);

const _cancelledAt = '2026-11-05T18:05:00Z';

/// Newest first, as the server delivers them.
Map<String, Object?> _booking(String id) => switch (id) {
  'b1' => {
    'id': 'b1',
    'person_id': 'p2',
    'drink_id': 'd2',
    'quantity': 2,
    'unit_price_cents': 180,
    'booked_at': '2026-11-05T20:30:00Z',
    'is_late': false,
    'cancelled_at': null,
  },
  'b2' => {
    'id': 'b2',
    'person_id': 'p1',
    'drink_id': 'd1',
    'quantity': 1,
    'unit_price_cents': 150,
    'booked_at': '2026-11-05T19:00:00Z',
    'is_late': true,
    'cancelled_at': null,
  },
  _ => {
    'id': 'b3',
    'person_id': 'p1',
    'drink_id': 'd1',
    'quantity': 3,
    'unit_price_cents': 150,
    'booked_at': '2026-11-05T18:00:00Z',
    'is_late': false,
    'cancelled_at': _cancelledAt,
  },
};

class _NoCatalog implements CatalogRepository {
  @override
  Future<Catalog?> cached() async => null;

  @override
  Future<void> save(Catalog catalog) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  late FakeApiServer server;
  late FixedClock clock;

  /// Booking ids the fake server lists, and those it has cancelled.
  late List<String> listed;
  late Set<String> cancelled;

  /// Answers a cancel request; default: cancels and returns the booking.
  late Future<http.Response> Function(String id) onCancel;

  Map<String, Object?> current(String id) => {
    ..._booking(id),
    if (cancelled.contains(id)) 'cancelled_at': _cancelledAt,
  };

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    listed = ['b1', 'b2', 'b3'];
    cancelled = {};
    onCancel = (id) async {
      cancelled.add(id);
      return _json(current(id));
    };
    server.respond = (r) async {
      final path = r.url.path;
      if (r.method == 'POST' && path.endsWith('admin/session')) {
        return _json({'token': 't1', 'expires_in': 300});
      }
      if (r.method == 'GET' && path.endsWith('admin/bookings')) {
        final personId = r.url.queryParameters['person_id'];
        return _json({
          'bookings': [
            for (final id in listed)
              if (personId == null || _booking(id)['person_id'] == personId)
                current(id),
          ],
        });
      }
      final cancel = RegExp(r'admin/bookings/(\w+)/cancel$').firstMatch(path);
      if (r.method == 'POST' && cancel != null) {
        return onCancel(cancel.group(1)!);
      }
      return _json({});
    };
  });

  List<String> calls() => [
    for (final r in server.requests) '${r.method} ${r.url.path}',
  ];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configStoreProvider.overrideWithValue(pairedStore()),
          httpClientProvider.overrideWithValue(server.client),
          clockProvider.overrideWithValue(clock),
          idleTimeoutProvider.overrideWithValue(_idle),
          catalogProvider.overrideWith((ref) async => _catalog),
          rankingsProvider.overrideWith((ref) => Stream.value(null)),
          syncStateProvider.overrideWith((ref) => const Stream.empty()),
          syncServiceProvider.overrideWith(
            (ref) => SyncService(
              api: ref.watch(apiProvider)!,
              bookings: FakeBookingRepository(clock: clock),
              tabs: FakeTabsRepository(),
              catalog: _NoCatalog(),
              rankings: FakeRankingsRepository(),
              clock: clock,
              transaction: (action) => action(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: BarTabTheme.data,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const NameListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Logs in, opens the bookings list and forgets the requests so far.
  Future<void> openBookings(WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('admin-gear')));
    await tester.pumpAndSettle();
    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-bookings')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminBookingsScreen), findsOneWidget);
  }

  Finder inRow(String id, Finder finder) =>
      find.descendant(of: find.byKey(Key('booking-$id')), matching: finder);

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  bool stornoEnabled(WidgetTester tester, String id) =>
      tester.widget<TextButton>(find.byKey(Key('storno-$id'))).enabled;

  Future<void> confirmStorno(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('storno-$id')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Stornieren')));
  }

  testWidgets('lists the bookings with names and amounts, newest first', (
    tester,
  ) async {
    await openBookings(tester);
    expect(calls().last, 'GET /api/v1/admin/bookings');
    expect(server.requests.last.url.queryParameters, isEmpty);
    expect(server.requests.last.headers['X-Admin-Token'], 't1');

    expect(inRow('b1', find.text('Bo Sample')), findsOneWidget);
    expect(inRow('b1', find.text('Cola')), findsOneWidget);
    expect(inRow('b1', find.text('2×')), findsOneWidget);
    expect(inRow('b1', find.text('1,80\u00a0€')), findsOneWidget);
    expect(inRow('b1', find.text('3,60\u00a0€')), findsOneWidget);
    expect(
      inRow(
        'b1',
        find.text(formatBookingTime(DateTime.utc(2026, 11, 5, 20, 30))),
      ),
      findsOneWidget,
    );
    expect(inRow('b2', find.text('Kim Example')), findsOneWidget);
    expect(inRow('b2', find.text('Lager')), findsOneWidget);
    expect(inRow('b2', find.text('1,50\u00a0€')), findsNWidgets(2));
    expect(inRow('b2', find.text('verspätet')), findsOneWidget);
    expect(inRow('b1', find.text('verspätet')), findsNothing);
    expect(inRow('b3', find.text('4,50\u00a0€')), findsOneWidget);

    final y1 = tester.getTopLeft(find.byKey(const Key('booking-b1'))).dy;
    final y2 = tester.getTopLeft(find.byKey(const Key('booking-b2'))).dy;
    final y3 = tester.getTopLeft(find.byKey(const Key('booking-b3'))).dy;
    expect(y1 < y2 && y2 < y3, isTrue);
  });

  testWidgets('says so when the period has no bookings', (tester) async {
    listed = [];
    await openBookings(tester);
    expect(find.text('Keine Buchungen in dieser Periode'), findsOneWidget);
  });

  testWidgets('offline loading says the server is unreachable', (tester) async {
    await pump(tester);
    final respond = server.respond;
    server.respond = (r) async {
      if (r.url.path.endsWith('admin/bookings')) {
        throw http.ClientException('down');
      }
      return respond(r);
    };
    await tester.tap(find.byKey(const Key('admin-gear')));
    await tester.pumpAndSettle();
    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-bookings')));
    await tester.pumpAndSettle();
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
  });

  testWidgets('the filter lists every person by name and reloads', (
    tester,
  ) async {
    await openBookings(tester);
    server.requests.clear();
    await tester.tap(find.byKey(const Key('admin-person-filter')));
    await tester.pumpAndSettle();
    final names = ['Alle Personen', 'Ann Old', 'Bo Sample', 'Kim Example'];
    final ys = [for (final n in names) tester.getTopLeft(find.text(n).last).dy];
    expect(ys, [...ys]..sort());

    await tester.tap(find.text('Kim Example').last);
    await tester.pumpAndSettle();
    expect(calls(), ['GET /api/v1/admin/bookings']);
    expect(server.requests.single.url.queryParameters, {'person_id': 'p1'});
    expect(find.byKey(const Key('booking-b1')), findsNothing);
    expect(find.byKey(const Key('booking-b2')), findsOneWidget);

    server.requests.clear();
    await tester.tap(find.byKey(const Key('admin-person-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle Personen').last);
    await tester.pumpAndSettle();
    expect(server.requests.single.url.queryParameters, isEmpty);
    expect(find.byKey(const Key('booking-b1')), findsOneWidget);
  });

  testWidgets('a cancelled booking is greyed out without a storno button', (
    tester,
  ) async {
    await openBookings(tester);
    expect(inRow('b3', find.text('storniert')), findsOneWidget);
    expect(find.byKey(const Key('storno-b3')), findsNothing);
    expect(
      DefaultTextStyle.of(
        tester.element(inRow('b3', find.text('Lager'))),
      ).style.color,
      BarTabTheme.muted,
    );
    expect(
      DefaultTextStyle.of(
        tester.element(inRow('b2', find.text('Lager'))),
      ).style.color,
      isNot(BarTabTheme.muted),
    );
    expect(find.byKey(const Key('storno-b2')), findsOneWidget);
  });

  testWidgets('storno asks, cancels on the server, marks the row and syncs', (
    tester,
  ) async {
    await openBookings(tester);
    server.requests.clear();
    await tester.tap(find.byKey(const Key('storno-b2')));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Buchung stornieren?')), findsOneWidget);
    expect(inDialog(find.textContaining('Kim Example')), findsOneWidget);
    expect(inDialog(find.textContaining('1× Lager')), findsOneWidget);
    expect(inDialog(find.text('Abbrechen')), findsOneWidget);

    await tester.tap(inDialog(find.text('Stornieren')));
    await tester.pumpAndSettle();
    expect(calls().first, 'POST /api/v1/admin/bookings/b2/cancel');
    expect(server.requests.first.headers['X-Admin-Token'], 't1');
    expect(calls(), contains('GET /api/v1/tabs'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(inRow('b2', find.text('storniert')), findsOneWidget);
    expect(find.byKey(const Key('storno-b2')), findsNothing);
    expect(find.text('Storniert'), findsOneWidget);
  });

  testWidgets('"Abbrechen" closes the dialog and sends nothing', (
    tester,
  ) async {
    await openBookings(tester);
    server.requests.clear();
    await tester.tap(find.byKey(const Key('storno-b2')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Abbrechen')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls(), isEmpty);
    expect(stornoEnabled(tester, 'b2'), isTrue);
    expect(find.byType(AdminBookingsScreen), findsOneWidget);
  });

  testWidgets('a double tap on "Stornieren" sends one storno', (tester) async {
    final answer = Completer<http.Response>();
    onCancel = (id) {
      cancelled.add(id);
      return answer.future;
    };
    await openBookings(tester);
    server.requests.clear();
    await tester.tap(find.byKey(const Key('storno-b2')));
    await tester.pumpAndSettle();
    final confirm = inDialog(find.text('Stornieren'));
    final button = tester.widget<FilledButton>(
      find.ancestor(of: confirm, matching: find.byType(FilledButton)),
    );
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    // Two presses can also arrive before the dialog starts closing.
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(AdminBookingsScreen), findsOneWidget);
    expect(stornoEnabled(tester, 'b2'), isFalse);
    await tester.tap(find.byKey(const Key('storno-b2')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    answer.complete(_json(current('b2')));
    await tester.pumpAndSettle();
    expect(calls().where((c) => c.endsWith('/cancel')), [
      'POST /api/v1/admin/bookings/b2/cancel',
    ]);
    expect(inRow('b2', find.text('storniert')), findsOneWidget);
  });

  testWidgets('already cancelled elsewhere reloads and says so', (
    tester,
  ) async {
    onCancel = (id) async {
      cancelled.add(id);
      return _json({'detail': 'already_cancelled'}, 409);
    };
    await openBookings(tester);
    server.requests.clear();
    await confirmStorno(tester, 'b2');
    await tester.pumpAndSettle();
    expect(calls(), [
      'POST /api/v1/admin/bookings/b2/cancel',
      'GET /api/v1/admin/bookings',
    ]);
    expect(find.text('Storno nicht möglich'), findsOneWidget);
    expect(inRow('b2', find.text('storniert')), findsOneWidget);
  });

  testWidgets('a closed period says the storno is not possible', (
    tester,
  ) async {
    onCancel = (id) async => _json({'detail': 'period_closed'}, 409);
    await openBookings(tester);
    await confirmStorno(tester, 'b2');
    await tester.pumpAndSettle();
    expect(find.text('Storno nicht möglich'), findsOneWidget);
    expect(stornoEnabled(tester, 'b2'), isTrue);
  });

  testWidgets('offline storno says so and leaves the row unchanged', (
    tester,
  ) async {
    onCancel = (id) async => throw http.ClientException('down');
    await openBookings(tester);
    server.requests.clear();
    await confirmStorno(tester, 'b2');
    await tester.pumpAndSettle();
    expect(calls(), ['POST /api/v1/admin/bookings/b2/cancel']);
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(inRow('b2', find.text('storniert')), findsNothing);
    expect(stornoEnabled(tester, 'b2'), isTrue);
  });

  testWidgets('a session ended on the server returns to the PIN prompt', (
    tester,
  ) async {
    onCancel = (id) async => _json({'detail': 'admin_session_required'}, 401);
    await openBookings(tester);
    await confirmStorno(tester, 'b2');
    await tester.pumpAndSettle();
    expect(find.byType(AdminBookingsScreen), findsNothing);
    expect(find.text('Admin-PIN'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Admin-PIN')),
    );
    expect(container.read(adminSessionProvider), isNull);
  });

  testWidgets('back returns to the admin home', (tester) async {
    await openBookings(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AdminBookingsScreen), findsNothing);
    expect(find.byKey(const Key('admin-bookings')), findsOneWidget);
  });

  testWidgets('idle on the bookings list logs out to the name list', (
    tester,
  ) async {
    await openBookings(tester);
    server.requests.clear();
    await tester.pump(_idle);
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.byType(AdminBookingsScreen), findsNothing);
    expect(calls(), ['DELETE /api/v1/admin/session']);
  });

  testWidgets('idle with the storno dialog open logs out too', (tester) async {
    await openBookings(tester);
    server.requests.clear();
    await tester.tap(find.byKey(const Key('storno-b2')));
    await tester.pumpAndSettle();
    await tester.pump(_idle);
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls(), ['DELETE /api/v1/admin/session']);
  });

  testWidgets('touches on the bookings list keep it open', (tester) async {
    await openBookings(tester);
    for (var i = 0; i < 3; i++) {
      await tester.pump(_idle * 0.6);
      await tester.tapAt(const Offset(640, 780));
    }
    await tester.pump(_idle * 0.6);
    expect(find.byType(AdminBookingsScreen), findsOneWidget);
  });
}

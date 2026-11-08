import 'dart:async';
import 'dart:convert';

import 'package:bar_tab/domain/catalog.dart';
import 'package:bar_tab/domain/clock.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/admin/admin_session.dart';
import 'package:bar_tab/presentation/admin/deliveries_screen.dart';
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

Drink _drink(String id, String name, int crateSize) => Drink(
  id: id,
  name: name,
  groupId: 'g1',
  crateSize: crateSize,
  sortOrder: 1,
  isHidden: false,
  isActive: true,
  prices: const {'t1': 150},
);

final _catalog = Catalog(
  tiers: const [PriceTier(id: 't1', name: 'Members', sortOrder: 1)],
  persons: const [],
  groups: const [
    DrinkGroup(id: 'g1', name: 'Beer', sortOrder: 1, color: 0xFF445566),
  ],
  drinks: [
    _drink('d1', 'Lager', 20),
    _drink('d2', 'Cola', 24),
    _drink('d3', 'Water', 1),
  ],
  etag: 'e',
);

const _cancelledAt = '2026-11-05T18:05:00Z';

/// Newest first, as the server delivers them.
Map<String, Object?> _delivery(String id) => switch (id) {
  's1' => {
    'id': 's1',
    'drink_id': 'd1',
    'quantity': 45,
    'created_at': '2026-11-05T20:30:00Z',
    'cancelled_at': null,
  },
  's2' => {
    'id': 's2',
    'drink_id': 'd2',
    'quantity': 48,
    'created_at': '2026-11-05T19:00:00Z',
    'cancelled_at': null,
  },
  's3' => {
    'id': 's3',
    'drink_id': 'd3',
    'quantity': 7,
    'created_at': '2026-11-05T18:00:00Z',
    'cancelled_at': _cancelledAt,
  },
  's4' => {
    'id': 's4',
    'drink_id': 'gone',
    'quantity': 5,
    'created_at': '2026-11-05T17:00:00Z',
    'cancelled_at': null,
  },
  _ => {
    'id': 's5',
    'drink_id': 'd1',
    'quantity': 10,
    'created_at': '2026-11-05T16:00:00Z',
    'cancelled_at': null,
  },
};

void main() {
  late FakeApiServer server;
  late FixedClock clock;
  late List<String> listed;
  late Set<String> cancelled;
  late Future<http.Response> Function(String id) onCancel;

  Map<String, Object?> current(String id) => {
    ..._delivery(id),
    if (cancelled.contains(id)) 'cancelled_at': _cancelledAt,
  };

  setUp(() {
    server = FakeApiServer();
    clock = FixedClock(DateTime.utc(2026, 11, 5, 21));
    listed = ['s1', 's2', 's3', 's4', 's5'];
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
      if (r.method == 'GET' && path.endsWith('admin/deliveries')) {
        return _json({
          'deliveries': [for (final id in listed) current(id)],
        });
      }
      final cancel = RegExp(r'admin/deliveries/(\w+)/cancel$').firstMatch(path);
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

  Future<void> login(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('admin-gear')));
    await tester.pumpAndSettle();
    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('keypad-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('admin-pin-login')));
    await tester.pumpAndSettle();
  }

  Future<void> openDeliveries(WidgetTester tester) async {
    await pump(tester);
    await login(tester);
    await tester.tap(find.byKey(const Key('admin-tile-deliveries')));
    await tester.pumpAndSettle();
    expect(find.byType(DeliveriesScreen), findsOneWidget);
  }

  Finder inRow(String id, Finder finder) =>
      find.descendant(of: find.byKey(Key('delivery-$id')), matching: finder);

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  bool stornoEnabled(WidgetTester tester, String id) =>
      tester.widget<TextButton>(find.byKey(Key('storno-$id'))).enabled;

  Future<void> confirmStorno(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('storno-$id')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Stornieren')));
  }

  testWidgets('the home has a deliveries tile', (tester) async {
    await pump(tester);
    await login(tester);
    expect(find.text('Lieferungen'), findsOneWidget);
  });

  testWidgets('lists deliveries newest first with the crate split', (
    tester,
  ) async {
    await openDeliveries(tester);
    expect(calls().last, 'GET /api/v1/admin/deliveries');
    expect(server.requests.last.headers['X-Admin-Token'], 't1');

    expect(
      inRow(
        's1',
        find.text(formatBookingTime(DateTime.utc(2026, 11, 5, 20, 30))),
      ),
      findsOneWidget,
    );
    expect(inRow('s1', find.text('Lager')), findsOneWidget);
    expect(inRow('s1', find.text('45 (2 K + 5)')), findsOneWidget);
    expect(inRow('s2', find.text('Cola')), findsOneWidget);
    expect(inRow('s2', find.text('48 (2 K)')), findsOneWidget);
    // Crate size 1: no split. Unknown drink: its id, as in the bookings list.
    expect(inRow('s3', find.text('7')), findsOneWidget);
    expect(inRow('s4', find.text('gone')), findsOneWidget);
    // Less than one crate: no split either.
    expect(inRow('s5', find.text('10')), findsOneWidget);

    final ys = [
      for (final id in ['s1', 's2', 's3', 's4', 's5'])
        tester.getTopLeft(find.byKey(Key('delivery-$id'))).dy,
    ];
    expect(ys, [...ys]..sort());
  });

  testWidgets('says so when the period has no deliveries', (tester) async {
    listed = [];
    await openDeliveries(tester);
    expect(find.text('Keine Lieferungen in dieser Periode'), findsOneWidget);
  });

  testWidgets('offline loading says the server is unreachable', (tester) async {
    await pump(tester);
    final respond = server.respond;
    server.respond = (r) async {
      if (r.url.path.endsWith('admin/deliveries')) {
        throw http.ClientException('down');
      }
      return respond(r);
    };
    await login(tester);
    await tester.tap(find.byKey(const Key('admin-tile-deliveries')));
    await tester.pumpAndSettle();
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
  });

  testWidgets('a cancelled delivery is greyed out without a storno button', (
    tester,
  ) async {
    await openDeliveries(tester);
    expect(inRow('s3', find.text('storniert')), findsOneWidget);
    expect(find.byKey(const Key('storno-s3')), findsNothing);
    expect(
      DefaultTextStyle.of(
        tester.element(inRow('s3', find.text('Water'))),
      ).style.color,
      BarTabTheme.muted,
    );
    expect(
      DefaultTextStyle.of(
        tester.element(inRow('s1', find.text('Lager'))),
      ).style.color,
      isNot(BarTabTheme.muted),
    );
    expect(find.byKey(const Key('storno-s1')), findsOneWidget);
  });

  testWidgets('storno asks, cancels on the server and greys the row', (
    tester,
  ) async {
    await openDeliveries(tester);
    server.requests.clear();
    await tester.tap(find.byKey(const Key('storno-s1')));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Lieferung stornieren?')), findsOneWidget);
    expect(inDialog(find.textContaining('Lager')), findsOneWidget);
    expect(inDialog(find.textContaining('45 (2 K + 5)')), findsOneWidget);
    expect(inDialog(find.text('Abbrechen')), findsOneWidget);

    await tester.tap(inDialog(find.text('Stornieren')));
    await tester.pumpAndSettle();
    expect(calls(), ['POST /api/v1/admin/deliveries/s1/cancel']);
    expect(server.requests.first.headers['X-Admin-Token'], 't1');
    expect(find.byType(AlertDialog), findsNothing);
    expect(inRow('s1', find.text('storniert')), findsOneWidget);
    expect(find.byKey(const Key('storno-s1')), findsNothing);
    expect(find.text('Lieferung storniert'), findsOneWidget);
  });

  testWidgets('"Abbrechen" closes the dialog and sends nothing', (
    tester,
  ) async {
    await openDeliveries(tester);
    server.requests.clear();
    await tester.tap(find.byKey(const Key('storno-s1')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text('Abbrechen')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls(), isEmpty);
    expect(stornoEnabled(tester, 's1'), isTrue);
    expect(find.byType(DeliveriesScreen), findsOneWidget);
  });

  testWidgets('a double tap on "Stornieren" sends one storno', (tester) async {
    final answer = Completer<http.Response>();
    onCancel = (id) {
      cancelled.add(id);
      return answer.future;
    };
    await openDeliveries(tester);
    server.requests.clear();
    await tester.tap(find.byKey(const Key('storno-s1')));
    await tester.pumpAndSettle();
    final confirm = inDialog(find.text('Stornieren'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(DeliveriesScreen), findsOneWidget);
    expect(stornoEnabled(tester, 's1'), isFalse);

    answer.complete(_json(current('s1')));
    await tester.pumpAndSettle();
    expect(calls().where((c) => c.endsWith('/cancel')), [
      'POST /api/v1/admin/deliveries/s1/cancel',
    ]);
    expect(inRow('s1', find.text('storniert')), findsOneWidget);
  });

  testWidgets('already cancelled elsewhere reloads and says so', (
    tester,
  ) async {
    onCancel = (id) async {
      cancelled.add(id);
      return _json({'detail': 'already_cancelled'}, 409);
    };
    await openDeliveries(tester);
    server.requests.clear();
    await confirmStorno(tester, 's1');
    await tester.pumpAndSettle();
    expect(calls(), [
      'POST /api/v1/admin/deliveries/s1/cancel',
      'GET /api/v1/admin/deliveries',
    ]);
    expect(find.text('Storno nicht möglich'), findsOneWidget);
    expect(inRow('s1', find.text('storniert')), findsOneWidget);
  });

  testWidgets('a closed period reloads and says the storno is not possible', (
    tester,
  ) async {
    onCancel = (id) async => _json({'detail': 'period_closed'}, 409);
    await openDeliveries(tester);
    server.requests.clear();
    await confirmStorno(tester, 's1');
    await tester.pumpAndSettle();
    expect(calls(), [
      'POST /api/v1/admin/deliveries/s1/cancel',
      'GET /api/v1/admin/deliveries',
    ]);
    expect(find.text('Storno nicht möglich'), findsOneWidget);
  });

  testWidgets('offline storno says so and leaves the row unchanged', (
    tester,
  ) async {
    onCancel = (id) async => throw http.ClientException('down');
    await openDeliveries(tester);
    server.requests.clear();
    await confirmStorno(tester, 's1');
    await tester.pumpAndSettle();
    expect(calls(), ['POST /api/v1/admin/deliveries/s1/cancel']);
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    expect(inRow('s1', find.text('storniert')), findsNothing);
    expect(stornoEnabled(tester, 's1'), isTrue);
  });

  testWidgets('a session ended on the server returns to the PIN prompt', (
    tester,
  ) async {
    onCancel = (id) async => _json({'detail': 'admin_session_required'}, 401);
    await openDeliveries(tester);
    await confirmStorno(tester, 's1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DeliveriesScreen), findsNothing);
    expect(find.text('Admin-PIN'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Admin-PIN')),
    );
    expect(container.read(adminSessionProvider), isNull);
  });

  testWidgets('idle on the list logs out to the name list', (tester) async {
    await openDeliveries(tester);
    await tester.pump(_idle);
    await tester.pumpAndSettle();
    expect(find.text('Wer trinkt?'), findsOneWidget);
    expect(find.byType(DeliveriesScreen), findsNothing);
  });
}

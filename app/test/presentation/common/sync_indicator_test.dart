import 'package:bar_tab/domain/sync_state.dart';
import 'package:bar_tab/l10n/app_localizations.dart';
import 'package:bar_tab/presentation/common/sync_indicator.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SyncState state({
  int queued = 0,
  int failed = 0,
  bool unauthorised = false,
  bool offline = false,
}) => SyncState(
  queued: queued,
  failed: failed,
  isUnauthorised: unauthorised,
  isOffline: offline,
);

void main() {
  final cases = <(String, SyncState, String?)>[
    ('all synced', state(), null),
    ('offline alone', state(offline: true), null),
    ('one queued', state(queued: 1), '1 Buchung wartet'),
    ('three queued', state(queued: 3), '3 Buchungen warten'),
    ('one failed', state(failed: 1), '1 Buchung abgelehnt'),
    ('two failed', state(failed: 2), '2 Buchungen abgelehnt'),
    (
      'failed beats queued',
      state(queued: 4, failed: 2),
      '2 Buchungen abgelehnt',
    ),
    ('unauthorised', state(unauthorised: true), 'Gerät nicht autorisiert'),
    (
      'unauthorised beats failed and queued',
      state(unauthorised: true, queued: 1, failed: 1),
      'Gerät nicht autorisiert',
    ),
  ];

  for (final (name, s, expected) in cases) {
    testWidgets('$name -> ${expected ?? 'nothing'}', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncStateProvider.overrideWith((ref) => Stream.value(s))],
          child: const MaterialApp(
            locale: Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: SyncIndicator()),
          ),
        ),
      );
      await tester.pump();
      if (expected == null) {
        expect(find.byType(Text), findsNothing);
      } else {
        expect(find.text(expected), findsOneWidget);
      }
    });
  }
}

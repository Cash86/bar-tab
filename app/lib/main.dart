import 'package:bar_tab/app.dart';
import 'package:bar_tab/presentation/app_logging.dart';
import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/drift_config_store.dart';
import 'package:bar_tab/presentation/design/design.dart';
import 'package:bar_tab/presentation/kiosk.dart';
import 'package:bar_tab/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  initLogging();
  WidgetsFlutterBinding.ensureInitialized();
  await configureKiosk(const SystemKioskPlatform());
  registerFontLicenses();
  final db = await openAppDatabase();
  final design = await loadDesign(DriftConfigStore(db));
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        initialDesignProvider.overrideWithValue(design),
      ],
      child: const BarTabApp(),
    ),
  );
}

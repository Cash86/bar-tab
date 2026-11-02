import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final _log = Logger('kiosk');

/// The platform operations that make the tablet behave like a kiosk.
abstract interface class KioskPlatform {
  Future<void> setLandscape();
  Future<void> setImmersive();
  Future<void> keepScreenOn();

  /// Lowers the screen brightness to a minimum (screensaver).
  Future<void> dim();
  Future<void> undim();
}

/// Idle time on the name list before the screensaver shows.
const kIdleTimeout = Duration(minutes: 2);

final kioskPlatformProvider = Provider<KioskPlatform>(
  (ref) => const SystemKioskPlatform(),
);

/// Lets the name list notice when it becomes the current route again.
final routeObserverProvider = Provider<RouteObserver<ModalRoute<void>>>(
  (ref) => RouteObserver<ModalRoute<void>>(),
);

final idleTimeoutProvider = Provider<Duration>((ref) => kIdleTimeout);

class SystemKioskPlatform implements KioskPlatform {
  const SystemKioskPlatform();

  @override
  Future<void> setLandscape() => SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  @override
  Future<void> setImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  @override
  Future<void> keepScreenOn() => WakelockPlus.enable();

  // Brightness is cosmetic: a platform failure must not break the app.
  @override
  Future<void> dim() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(0.05);
    } catch (_) {}
  }

  @override
  Future<void> undim() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
  }
}

/// Each step is guarded: a failing platform call must not stop the app.
Future<void> configureKiosk(KioskPlatform p) async {
  for (final step in [p.setLandscape, p.setImmersive, p.keepScreenOn]) {
    try {
      await step();
    } catch (e, st) {
      _log.warning('Kiosk setup step failed', e, st);
    }
  }
}

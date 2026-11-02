import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

Future<void> configureKiosk(KioskPlatform p) async {
  await p.setLandscape();
  await p.setImmersive();
  await p.keepScreenOn();
}

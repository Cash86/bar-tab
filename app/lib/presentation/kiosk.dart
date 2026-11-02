import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The platform operations that make the tablet behave like a kiosk.
abstract interface class KioskPlatform {
  Future<void> setLandscape();
  Future<void> setImmersive();
  Future<void> keepScreenOn();
}

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
}

Future<void> configureKiosk(KioskPlatform p) async {
  await p.setLandscape();
  await p.setImmersive();
  await p.keepScreenOn();
}

import 'package:bar_tab/presentation/kiosk.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeKioskPlatform implements KioskPlatform {
  final calls = <String>[];

  @override
  Future<void> setLandscape() async => calls.add('landscape');

  @override
  Future<void> setImmersive() async => calls.add('immersive');

  @override
  Future<void> keepScreenOn() async => calls.add('screenOn');

  @override
  Future<void> dim() async => calls.add('dim');

  @override
  Future<void> undim() async => calls.add('undim');
}

void main() {
  test(
    'configureKiosk locks landscape, goes immersive and keeps screen on',
    () async {
      final fake = _FakeKioskPlatform();
      await configureKiosk(fake);
      expect(fake.calls, ['landscape', 'immersive', 'screenOn']);
    },
  );
}

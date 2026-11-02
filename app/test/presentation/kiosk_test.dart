import 'package:bar_tab/presentation/kiosk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeKioskPlatform implements KioskPlatform {
  _FakeKioskPlatform({this.throwing = false});

  final bool throwing;
  final calls = <String>[];

  @override
  Future<void> setLandscape() async {
    calls.add('landscape');
    if (throwing) throw PlatformException(code: 'x');
  }

  @override
  Future<void> setImmersive() async {
    calls.add('immersive');
    if (throwing) throw PlatformException(code: 'x');
  }

  @override
  Future<void> keepScreenOn() async {
    calls.add('screenOn');
    if (throwing) throw PlatformException(code: 'x');
  }

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

  test('configureKiosk carries on when a platform call throws', () async {
    final fake = _FakeKioskPlatform(throwing: true);
    await configureKiosk(fake);
    expect(fake.calls, ['landscape', 'immersive', 'screenOn']);
  });
}

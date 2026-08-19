// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:test/test.dart';

void main() {
  group('DesktopPlatformApi', () {
    test('can be instantiated', () {
      expect(DesktopPlatformApi(), isNotNull);
    });
  });
}

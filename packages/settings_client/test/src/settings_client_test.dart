// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:settings_client/settings_client.dart';
import 'package:test/test.dart';

void main() {
  group('SettingsClient', () {
    test('can be instantiated', () {
      expect(SettingsClient(), isNotNull);
    });
  });
}

// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:test/test.dart';

void main() {
  group('DesktopNotificationsRepository', () {
    test('can be instantiated', () {
      expect(DesktopNotificationsRepository(), isNotNull);
    });
  });
}

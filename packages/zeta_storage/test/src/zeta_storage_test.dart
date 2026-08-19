// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  group('ZetaStorage', () {
    test('can be instantiated', () {
      expect(ZetaStorage(), isNotNull);
    });
  });
}

// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:test/test.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';

void main() {
  group('UsageStatisticsRepository', () {
    test('can be instantiated', () {
      expect(UsageStatisticsRepository(), isNotNull);
    });
  });
}

// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:test/test.dart';
import 'package:usage_statistics_storage_client/usage_statistics_storage_client.dart';

void main() {
  group('UsageStatisticsStorageClient', () {
    test('can be instantiated', () {
      expect(UsageStatisticsStorageClient(), isNotNull);
    });
  });
}

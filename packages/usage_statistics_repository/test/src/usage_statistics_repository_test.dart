import 'package:test/test.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';

void main() {
  test('usage token totals fall back to available components', () {
    expect(
      const UsageTokenBreakdown(inputTokens: 2, outputTokens: 3).effectiveTotal,
      5,
    );
  });
}

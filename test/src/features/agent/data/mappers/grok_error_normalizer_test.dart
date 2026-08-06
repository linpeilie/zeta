import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/data/mappers/grok_error_normalizer.dart';

void main() {
  group('grokTerminalErrorMessage', () {
    test('prefers a real agent_result over a placeholder stop_reason', () {
      expect(
        grokTerminalErrorMessage(
          'error',
          agentResult:
              'API error (status 402 Payment Required): '
              'Grok Build usage balance exhausted',
        ),
        'API error (status 402 Payment Required): '
        'Grok Build usage balance exhausted',
      );
    });

    test('normalizes rate-limit agent_result to the stable summary', () {
      expect(
        grokTerminalErrorMessage(
          'error',
          agentResult: 'rate_limit reached usage-exhausted',
        ),
        grokRateLimitErrorMessage,
      );
      expect(
        grokTerminalErrorMessage(
          'error',
          agentResult: 'status 429 Too many requests',
        ),
        grokRateLimitErrorMessage,
      );
    });

    test('falls back to the generic message for a placeholder stop_reason', () {
      expect(grokTerminalErrorMessage('error'), grokRequestFailedErrorMessage);
      expect(
        grokTerminalErrorMessage('unknown'),
        grokRequestFailedErrorMessage,
      );
      expect(
        grokTerminalErrorMessage('exception'),
        grokRequestFailedErrorMessage,
      );
    });

    test('keeps a meaningful stop_reason when no agent_result is present', () {
      expect(grokTerminalErrorMessage('cancelled'), 'cancelled');
      expect(grokTerminalErrorMessage('max_turn'), 'max_turn');
    });
  });
}

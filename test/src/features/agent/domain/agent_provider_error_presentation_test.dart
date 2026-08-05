import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_error_presentation.dart';

void main() {
  group('AgentProviderErrorPresentation', () {
    test('formats serverOverloaded with actionable guidance', () {
      final text = AgentProviderErrorPresentation.formatUserVisibleText(
        message: 'Selected model is at capacity. Please try a different model.',
        code: 'serverOverloaded',
        willRetry: false,
      );

      expect(text, contains('Selected model is at capacity'));
      expect(text, contains('当前模型容量已满'));
      expect(text, contains('切换其他模型'));
      expect(text, isNot(contains('服务端将自动重试')));
    });

    test('keeps contextWindowExceeded compact guidance', () {
      final text = AgentProviderErrorPresentation.formatUserVisibleText(
        message: 'Context window exceeded',
        code: 'contextWindowExceeded',
      );

      expect(text, contains('Context window exceeded'));
      expect(text, contains('压缩上下文'));
    });

    test('infers serverOverloaded from capacity message without code', () {
      expect(
        AgentProviderErrorPresentation.resolveCode(
          message:
              'Selected model is at capacity. Please try a different model.',
        ),
        'serverOverloaded',
      );
    });

    test('prefixes turn failure messages', () {
      final text = AgentProviderErrorPresentation.formatUserVisibleText(
        message: 'Selected model is at capacity. Please try a different model.',
        code: 'serverOverloaded',
        prefixTurnFailed: true,
      );

      expect(text.startsWith('Turn failed: '), isTrue);
      expect(text, contains('当前模型容量已满'));
    });

    test('localizes automatic retry hint', () {
      final text = AgentProviderErrorPresentation.formatUserVisibleText(
        message: 'Temporary upstream failure',
        willRetry: true,
      );

      expect(text, contains('服务端将自动重试'));
    });
  });
}

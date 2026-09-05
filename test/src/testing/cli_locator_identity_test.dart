import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'agent_provider_implementations.dart';

void main() {
  group('CLI path identity guards', () {
    test('looksLikeGrokCliPath accepts grok binaries only', () {
      expect(looksLikeGrokCliPath(r'C:\Users\me\.grok\bin\grok.exe'), isTrue);
      expect(looksLikeGrokCliPath('/usr/local/bin/grok'), isTrue);
      expect(looksLikeGrokCliPath(r'C:\tools\codex.exe'), isFalse);
      expect(looksLikeGrokCliPath('codex'), isFalse);
    });

    test('looksLikeCodexCliPath accepts codex binaries only', () {
      expect(looksLikeCodexCliPath(r'C:\tools\codex.exe'), isTrue);
      expect(looksLikeCodexCliPath('/usr/local/bin/codex'), isTrue);
      expect(looksLikeCodexCliPath(r'C:\Users\me\.grok\bin\grok.exe'), isFalse);
      expect(looksLikeCodexCliPath('grok'), isFalse);
    });

    test('Grok locator skips contaminated codex cliPath', () async {
      final locator = GrokCliLocator(
        environment: <String, String>{
          'PATH': '',
          'USERPROFILE': r'C:\Users\none',
          'HOME': '/none',
        },
      );
      final resolved = await locator.locate(
        defaultGrokAgentProviderConfig.copyWith(
          extra: <String, Object?>{'cliPath': r'C:\tools\codex.exe'},
          command: r'C:\tools\codex.exe',
        ),
      );
      // 无 PATH/常见目录命中时，错误 cliPath 被跳过，结果为未找到。
      expect(resolved, isNull);
    });
  });
}

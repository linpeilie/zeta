import 'package:test/test.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart';

void main() {
  group('ClaudeCodeCliLocator', () {
    test('selects npm cmd instead of the extensionless POSIX shim', () async {
      // Arrange
      const shim = r'D:\Development\Environment\nodejs\claude';
      const cmd = r'D:\Development\Environment\nodejs\claude.cmd';
      const winGet =
          r'C:\Users\me\AppData\Local\Microsoft\WinGet\Links\claude.exe';
      final locator = ClaudeCodeCliLocator(
        environment: const <String, String>{
          'PATH':
              r'D:\Development\Environment\nodejs;C:\Users\me\AppData\Local\Microsoft\WinGet\Links',
          'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
          'USERPROFILE': r'C:\Users\me',
          'SystemRoot': r'C:\Windows',
        },
        isWindows: true,
        fileExists: (path) async =>
            path == shim || path == cmd || path == winGet,
      );

      // Act
      final resolved = await locator.locate(
        defaultClaudeCodeAgentProviderConfig,
      );

      // Assert
      expect(resolved?.displayPath, cmd);
      expect(resolved?.executable, r'C:\Windows\System32\cmd.exe');
      expect(resolved?.prefixArguments, <String>[
        '/d',
        '/s',
        '/c',
        'call',
        cmd,
      ]);
    });

    test('rejects another Provider CLI path', () async {
      // Arrange
      final locator = ClaudeCodeCliLocator(
        environment: const <String, String>{},
        isWindows: true,
        fileExists: (_) async => true,
      );

      // Act
      final resolved = await locator.resolvePath(r'C:\Tools\codex.exe');

      // Assert
      expect(resolved, isNull);
    });
  });
}

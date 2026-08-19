import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/grok_acp_client.dart';
import 'package:test/test.dart';

void main() {
  group('GrokCliLocator', () {
    test('selects a Windows cmd wrapper from PATH', () async {
      const shim = r'D:\Tools\grok';
      const cmd = r'D:\Tools\grok.cmd';
      final locator = GrokCliLocator(
        environment: const <String, String>{
          'PATH': r'D:\Tools',
          'SystemRoot': r'C:\Windows',
        },
        isWindows: true,
        fileExists: (path) async => path == shim || path == cmd,
      );

      final resolved = await locator.locate(AgentProviderConfig.defaultGrok);

      expect(resolved?.displayPath, cmd);
      expect(resolved?.executable, r'C:\Windows\System32\cmd.exe');
      expect(
        resolved?.arguments,
        const <String>['/d', '/s', '/c', 'call', cmd],
      );
    });

    test(
      'continues after a stale saved path and finds a common path',
      () async {
        const common = r'C:\Users\me\.grok\bin\grok.exe';
        final locator = GrokCliLocator(
          environment: const <String, String>{
            'PATH': '',
            'USERPROFILE': r'C:\Users\me',
          },
          isWindows: true,
          fileExists: (path) async => path == common,
        );

        final resolved = await locator.locate(
          AgentProviderConfig.defaultGrok.copyWith(
            extra: const <String, Object?>{
              'cliPath': r'C:\removed\grok.exe',
            },
          ),
        );

        expect(resolved?.displayPath, common);
        expect(resolved?.executable, common);
        expect(resolved?.arguments, isEmpty);
      },
    );

    test('wraps a selected PowerShell script without a profile', () async {
      const script = r'\\server\tools\grok.ps1';
      final locator = GrokCliLocator(
        environment: const <String, String>{'SystemRoot': r'D:\Windows'},
        isWindows: true,
        fileExists: (path) async => path == script,
      );

      final resolved = await locator.resolvePath('  $script  ');

      expect(
        resolved?.executable,
        r'D:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      );
      expect(
        resolved?.arguments,
        const <String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-File',
          script,
        ],
      );
    });

    test('finds a Windows npm wrapper from APPDATA', () async {
      const wrapper = r'C:\Users\me\AppData\Roaming\npm\grok.cmd';
      final locator = GrokCliLocator(
        environment: const <String, String>{
          'PATH': '',
          'APPDATA': r'C:\Users\me\AppData\Roaming',
          'SystemRoot': r'C:\Windows',
        },
        isWindows: true,
        fileExists: (path) async => path == wrapper,
      );

      final resolved = await locator.locate(AgentProviderConfig.defaultGrok);

      expect(resolved?.displayPath, wrapper);
      expect(resolved?.executable, r'C:\Windows\System32\cmd.exe');
    });

    test('finds POSIX PATH and standard install candidates', () async {
      const pathCli = '/workspace/bin/grok';
      final fromPath = GrokCliLocator(
        environment: const <String, String>{
          'PATH': '"/workspace/bin":/other/bin',
          'HOME': '/home/me',
        },
        isWindows: false,
        fileExists: (path) async => path == pathCli,
      );
      final fromCommon = GrokCliLocator(
        environment: const <String, String>{'PATH': '', 'HOME': '/home/me'},
        isWindows: false,
        fileExists: (path) async => path == '/home/me/.local/bin/grok',
      );

      expect(
        (await fromPath.locate(AgentProviderConfig.defaultGrok))?.executable,
        pathCli,
      );
      expect(
        (await fromCommon.locate(AgentProviderConfig.defaultGrok))?.executable,
        '/home/me/.local/bin/grok',
      );
    });

    test('rejects directories and other provider executables', () async {
      final locator = GrokCliLocator(
        environment: const <String, String>{},
        isWindows: true,
        fileExists: (_) async => true,
      );

      expect(await locator.resolvePath(''), isNull);
      expect(await locator.resolvePath(r'C:\Tools\codex.exe'), isNull);
      expect(await locator.resolvePath(r'C:\Tools\grok'), isNull);
    });

    test('uses the host filesystem when no file seam is injected', () async {
      const locator = GrokCliLocator(
        environment: <String, String>{},
        isWindows: false,
      );

      expect(await locator.resolvePath('/definitely/missing/grok'), isNull);
    });
  });
}

import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/claude_code_cli_locator.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_process_starter.dart';
import 'package:test/test.dart';

void main() {
  group('buildClaudeCodeProcessArguments', () {
    test('default enables the stdio permission callback', () {
      expect(buildClaudeCodeProcessArguments(), <String>[
        '--print',
        '--input-format',
        'stream-json',
        '--output-format',
        'stream-json',
        '--verbose',
        '--permission-prompt-tool',
        'stdio',
      ]);
    });

    test('session-id model effort permission-mode in fixed order', () {
      expect(
        buildClaudeCodeProcessArguments(
          sessionId: 'sid-1',
          model: 'haiku',
          reasoningEffort: 'high',
          permissionMode: 'default',
        ),
        <String>[
          '--print',
          '--input-format',
          'stream-json',
          '--output-format',
          'stream-json',
          '--verbose',
          '--session-id',
          'sid-1',
          '--model',
          'haiku',
          '--effort',
          'high',
          '--permission-prompt-tool',
          'stdio',
          '--permission-mode',
          'default',
        ],
      );
    });

    test('resume wins over session-id', () {
      expect(
        buildClaudeCodeProcessArguments(
          sessionId: 'sid-new',
          resumeSessionId: 'sid-old',
          model: 'sonnet',
          permissionMode: 'plan',
        ),
        <String>[
          '--print',
          '--input-format',
          'stream-json',
          '--output-format',
          'stream-json',
          '--verbose',
          '--resume',
          'sid-old',
          '--model',
          'sonnet',
          '--permission-prompt-tool',
          'stdio',
          '--permission-mode',
          'plan',
        ],
      );
    });

    test('acceptEdits permission mode and optional toggles', () {
      expect(
        buildClaudeCodeProcessArguments(
          sessionId: 's',
          permissionMode: 'acceptEdits',
          includePartialMessages: true,
          noSessionPersistence: true,
        ),
        <String>[
          '--print',
          '--input-format',
          'stream-json',
          '--output-format',
          'stream-json',
          '--verbose',
          '--session-id',
          's',
          '--permission-prompt-tool',
          'stdio',
          '--permission-mode',
          'acceptEdits',
          '--include-partial-messages',
          '--no-session-persistence',
        ],
      );
    });

    test('permission prompt tool can be explicitly disabled', () {
      expect(
        buildClaudeCodeProcessArguments(permissionPromptTool: null),
        <String>[
          '--print',
          '--input-format',
          'stream-json',
          '--output-format',
          'stream-json',
          '--verbose',
        ],
      );
    });
  });

  group('buildClaudeCodeMetadataProbeArguments', () {
    test('uses the fixed no-session user-settings argument list', () {
      expect(buildClaudeCodeMetadataProbeArguments(), <String>[
        '--print',
        '--input-format',
        'stream-json',
        '--output-format',
        'stream-json',
        '--verbose',
        '--no-session-persistence',
        '--setting-sources',
        'user',
      ]);
      expect(
        buildClaudeCodeMetadataProbeArguments(),
        isNot(contains('--permission-prompt-tool')),
      );
      expect(
        buildClaudeCodeMetadataProbeArguments(),
        isNot(contains('--session-id')),
      );
      expect(
        buildClaudeCodeMetadataProbeArguments(),
        isNot(contains('--model')),
      );
    });
  });

  group('resolveClaudeCodeProcessCommand', () {
    test('uses locator result and config model', () async {
      final resolved = await resolveClaudeCodeProcessCommand(
        AgentProviderConfig.defaultClaudeCode.copyWith(
          defaultModel: 'opus',
          selectedReasoningEffort: 'xhigh',
        ),
        sessionId: 'abc',
        permissionMode: 'bypassPermissions',
        locator: _StaticClaudeCodeCliLocator(
          ResolvedCliProcessCommand(
            displayPath: r'C:\Tools\claude.exe',
            executable: r'C:\Tools\claude.exe',
            arguments: const <String>[],
          ),
        ),
      );

      expect(resolved.executable, r'C:\Tools\claude.exe');
      expect(resolved.displayPath, r'C:\Tools\claude.exe');
      expect(
        resolved.arguments,
        buildClaudeCodeProcessArguments(
          sessionId: 'abc',
          model: 'opus',
          reasoningEffort: 'xhigh',
          permissionMode: 'bypassPermissions',
        ),
      );
    });

    test('fails closed when locator cannot find an executable', () async {
      await expectLater(
        resolveClaudeCodeProcessCommand(
          AgentProviderConfig.defaultClaudeCode,
          locator: const _StaticClaudeCodeCliLocator(null),
        ),
        throwsA(isA<ProcessException>()),
      );
    });

    test(
      'prepends the locator shell arguments before protocol flags',
      () async {
        final resolved = await resolveClaudeCodeProcessCommand(
          AgentProviderConfig.defaultClaudeCode,
          locator: _StaticClaudeCodeCliLocator(
            ResolvedCliProcessCommand(
              displayPath: r'D:\bin\claude.cmd',
              executable: r'C:\Windows\System32\cmd.exe',
              arguments: const <String>[
                '/d',
                '/s',
                '/c',
                'call',
                r'D:\bin\claude.cmd',
              ],
            ),
          ),
        );
        expect(resolved.executable, r'C:\Windows\System32\cmd.exe');
        expect(resolved.displayPath, r'D:\bin\claude.cmd');
        expect(resolved.arguments.take(5), <String>[
          '/d',
          '/s',
          '/c',
          'call',
          r'D:\bin\claude.cmd',
        ]);
        expect(resolved.arguments.skip(5), buildClaudeCodeProcessArguments());
      },
    );
  });

  group('resolveClaudeCodeMetadataProbeCommand', () {
    test(
      'keeps wrapper prefix but excludes conversation config args',
      () async {
        final resolved = await resolveClaudeCodeMetadataProbeCommand(
          AgentProviderConfig.defaultClaudeCode.copyWith(
            arguments: const <String>[
              '--model',
              'must-not-leak',
              '--session-id',
              'must-not-leak',
            ],
            defaultModel: 'must-not-leak',
          ),
          locator: _StaticClaudeCodeCliLocator(
            ResolvedCliProcessCommand(
              displayPath: r'D:\bin\claude.cmd',
              executable: r'C:\Windows\System32\cmd.exe',
              arguments: const <String>[
                '/d',
                '/s',
                '/c',
                'call',
                r'D:\bin\claude.cmd',
              ],
            ),
          ),
        );

        expect(resolved.executable, r'C:\Windows\System32\cmd.exe');
        expect(resolved.arguments.take(5), <String>[
          '/d',
          '/s',
          '/c',
          'call',
          r'D:\bin\claude.cmd',
        ]);
        expect(
          resolved.arguments.skip(5),
          buildClaudeCodeMetadataProbeArguments(),
        );
        expect(resolved.arguments, isNot(contains('must-not-leak')));
      },
    );

    test('fails closed when metadata CLI cannot be located', () async {
      await expectLater(
        resolveClaudeCodeMetadataProbeCommand(
          AgentProviderConfig.defaultClaudeCode,
          locator: const _StaticClaudeCodeCliLocator(null),
        ),
        throwsA(isA<ProcessException>()),
      );
    });
  });
}

class _StaticClaudeCodeCliLocator extends ClaudeCodeCliLocator {
  const _StaticClaudeCodeCliLocator(this.result);

  final ResolvedCliProcessCommand? result;

  @override
  Future<ResolvedCliProcessCommand?> locate(AgentProviderConfig config) async =>
      result;

  @override
  Future<ResolvedCliProcessCommand?> resolvePath(String path) async => result;
}

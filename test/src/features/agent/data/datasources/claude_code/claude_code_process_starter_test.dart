import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_process_starter.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

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

    test('session-id model permission-mode in fixed order', () {
      expect(
        buildClaudeCodeProcessArguments(
          sessionId: 'sid-1',
          model: 'haiku',
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

  group('resolveClaudeCodeProcessCommand', () {
    test('uses which lookup result and config model', () async {
      final resolved = await resolveClaudeCodeProcessCommand(
        AgentProviderConfig.defaultClaudeCode.copyWith(defaultModel: 'opus'),
        sessionId: 'abc',
        permissionMode: 'bypassPermissions',
        whichLookup: (command) async {
          expect(command, 'claude');
          return r'C:\Tools\claude.exe';
        },
      );

      expect(resolved.executable, r'C:\Tools\claude.exe');
      expect(resolved.displayPath, 'claude');
      expect(
        resolved.arguments,
        buildClaudeCodeProcessArguments(
          sessionId: 'abc',
          model: 'opus',
          permissionMode: 'bypassPermissions',
        ),
      );
    });

    test('keeps configured command when lookup returns null', () async {
      final resolved = await resolveClaudeCodeProcessCommand(
        AgentProviderConfig.defaultClaudeCode,
        whichLookup: (_) async => null,
      );
      expect(resolved.executable, 'claude');
    });

    test('prefers extra.cliPath for display and lookup key', () async {
      final resolved = await resolveClaudeCodeProcessCommand(
        AgentProviderConfig.defaultClaudeCode.copyWith(
          extra: <String, Object?>{'cliPath': r'D:\bin\claude.cmd'},
        ),
        whichLookup: (command) async {
          expect(command, r'D:\bin\claude.cmd');
          return command;
        },
      );
      expect(resolved.executable, r'D:\bin\claude.cmd');
      expect(resolved.displayPath, r'D:\bin\claude.cmd');
    });
  });
}

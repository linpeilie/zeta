import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/claude_code_cli_locator.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_control_request_handler.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_hidden_thread_store.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_macos_keychain_source.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_oauth_credentials_reader.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_permission_policy_adapter.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_plan_approval_adapter.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_process_starter.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_question_adapter.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_usage_quota_adapter.dart';
import 'package:claude_code_client/src/mappers/claude_code_initialize_metadata_mapper.dart';
import 'package:claude_code_client/src/mappers/claude_code_usage_quota_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('CLI locator compatibility branches', () {
    test(
      'covers configured, POSIX, common, duplicate, and missing paths',
      () async {
        final requested = <String>[];
        final locator = ClaudeCodeCliLocator(
          environment: const <String, String>{
            'PATH': '"/bin": :/usr/bin',
            'HOME': '/home/tester',
          },
          isWindows: false,
          fileExists: (path) async {
            requested.add(path);
            return path == '/home/tester/.npm-global/bin/claude';
          },
        );
        final config = AgentProviderConfig.defaultClaudeCode.copyWith(
          command: '/stale/claude',
          environment: const <String, String>{'PATH': '/bin:/bin'},
          extra: const <String, Object?>{'cliPath': ' /missing/claude '},
        );

        final result = await locator.locate(config);

        expect(result?.executable, '/home/tester/.npm-global/bin/claude');
        expect(requested.where((path) => path == '/bin/claude'), hasLength(1));
        expect(await locator.resolvePath(''), isNull);
        expect(await locator.resolvePath('/tools/codex'), isNull);
        expect(await locator.resolvePath('/missing/claude'), isNull);
      },
    );

    test('covers Windows common roots and launchers', () async {
      Future<ResolvedCliProcessCommand?> resolve(
        String expected, {
        Map<String, String> environment = const <String, String>{},
      }) {
        return ClaudeCodeCliLocator(
          environment: <String, String>{
            'SystemRoot': r'D:\Windows',
            ...environment,
          },
          isWindows: true,
          fileExists: (path) async => path == expected,
        ).locate(AgentProviderConfig.defaultClaudeCode);
      }

      expect(
        (await resolve(
          r'C:\Users\me\.local\bin\claude.exe',
          environment: const <String, String>{'USERPROFILE': r'C:\Users\me'},
        ))?.executable,
        r'C:\Users\me\.local\bin\claude.exe',
      );
      expect(
        (await resolve(
          r'C:\Users\me\AppData\Roaming\npm\claude.cmd',
          environment: const <String, String>{
            'APPDATA': r'C:\Users\me\AppData\Roaming',
          },
        ))?.arguments,
        contains('call'),
      );
      expect(
        (await resolve(
          r'C:\tools\claude.ps1',
          environment: const <String, String>{'PATH': r'C:\tools'},
        ))?.executable,
        r'D:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      );
      expect(
        await ClaudeCodeCliLocator(
          environment: const <String, String>{},
          isWindows: true,
          fileExists: (_) async => true,
        ).resolvePath(r'C:\tools\claude'),
        isNull,
      );
    });
  });

  test('memory stores defensively copy values', () async {
    final hidden = MemoryClaudeCodeHiddenThreadStore();
    final hiddenInput = <String>{'one'};
    await hidden.save(hiddenInput);
    hiddenInput.add('two');
    final hiddenOutput = await hidden.load()
      ..add('three');
    expect(await hidden.load(), <String>{'one'});
    expect(hiddenOutput, contains('three'));

    final decisions = MemoryClaudeCodeSessionDecisionStore();
    final decisionInput = <String, ClaudeCodeSessionToolDecision>{
      'Bash': ClaudeCodeSessionToolDecision.allow,
    };
    await decisions.save(decisionInput);
    decisionInput.clear();
    final decisionOutput = await decisions.load()
      ..clear();
    expect(
      await decisions.load(),
      containsPair('Bash', ClaudeCodeSessionToolDecision.allow),
    );
    expect(decisionOutput, isEmpty);
  });

  test(
    'bounded process output accepts malformed bytes and rejects overflow',
    () async {
      expect(
        await readClaudeCodeBoundedOutput(
          Stream<List<int>>.value(<int>[0x66, 0x80]),
        ),
        startsWith('f'),
      );
      await expectLater(
        readClaudeCodeBoundedOutput(
          Stream<List<int>>.fromIterable(<List<int>>[
            utf8.encode('abc'),
            utf8.encode('def'),
          ]),
          maxBytes: 5,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'keychain process runner covers success, timeout, and start failure',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'claude-keychain-runner-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final script = File('${temp.path}${Platform.pathSeparator}script.dart');
      await script.writeAsString("void main() { print('credential'); }");

      final result = await runClaudeCodeKeychainProcess(
        _dartExecutable(),
        <String>[script.path],
        timeout: const Duration(seconds: 10),
      );
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), 'credential');

      await script.writeAsString(
        "import 'dart:async'; Future<void> main() async { "
        'await Future<void>.delayed(const Duration(seconds: 5)); }',
      );
      await expectLater(
        runClaudeCodeKeychainProcess(
          _dartExecutable(),
          <String>[script.path],
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        runClaudeCodeKeychainProcess(
          '${temp.path}${Platform.pathSeparator}missing-executable',
          const <String>[],
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<ProcessException>()),
      );
    },
  );

  test('process starter resolves and delegates with host values', () async {
    final starter = claudeCodeProcessStarter(
      AgentProviderConfig.defaultClaudeCode,
      sessionId: 'session',
      model: 'sonnet',
      useConfiguredReasoningEffort: false,
      reasoningEffort: 'high',
      includePartialMessages: true,
      noSessionPersistence: true,
      locator: _FixedLocator(),
      delegate:
          (
            executable,
            arguments, {
            workingDirectory,
            environment,
          }) async {
            expect(executable, '/bin/claude');
            expect(
              arguments,
              containsAll(<String>['session', 'sonnet', 'high']),
            );
            expect(workingDirectory, '/workspace');
            expect(environment, containsPair('SAFE', 'true'));
            throw const ProcessException('/bin/claude', <String>[]);
          },
    );

    await expectLater(
      starter(
        'ignored',
        const <String>[],
        workingDirectory: '/workspace',
        environment: const <String, String>{'SAFE': 'true'},
      ),
      throwsA(isA<ProcessException>()),
    );
  });

  test('default locator filesystem check rejects a missing CLI', () async {
    const locator = ClaudeCodeCliLocator();
    expect(
      await locator.resolvePath(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'definitely-missing-claude${Platform.isWindows ? '.exe' : ''}',
      ),
      isNull,
    );
    final temp = await Directory.systemTemp.createTemp('claude-locator-');
    addTearDown(() => temp.delete(recursive: true));
    final executable = File(
      '${temp.path}${Platform.pathSeparator}'
      '${Platform.isWindows ? 'claude.exe' : 'claude'}',
    );
    await executable.writeAsString('fixture');
    expect(
      (await locator.resolvePath(executable.path))?.displayPath,
      executable.path,
    );
  });

  test(
    'credential sources cover platform fallbacks and callable adapters',
    () async {
      final temp = await Directory.systemTemp.createTemp('claude-credentials-');
      addTearDown(() => temp.delete(recursive: true));
      final file = File(
        '${temp.path}${Platform.pathSeparator}credentials.json',
      );
      final expires = DateTime.now().add(const Duration(hours: 1));
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'claudeAiOauth': <String, Object?>{
            'accessToken': 'sensitive-token',
            'expiresAt': expires.millisecondsSinceEpoch.toDouble(),
          },
        }),
      );
      const fileSource = FileClaudeCodeCredentialsFileSource();
      expect(await fileSource.call(file.path), isNotEmpty);
      expect(
        await fileSource.read('${temp.path}${Platform.pathSeparator}missing'),
        isNull,
      );
      final reader = ClaudeCodeOAuthCredentialsReader(
        credentialsPath: file.path,
        fileSource: fileSource.call,
      );
      expect((await reader.read())?.accessToken, 'sensitive-token');
      expect(
        ClaudeCodeOAuthCredentialsReader(
          homeDirectory: temp.path,
        ).resolveCredentialsPath(),
        '${temp.path}${Platform.pathSeparator}.claude'
        '${Platform.pathSeparator}.credentials.json',
      );

      final byLogName = ClaudeCodeMacOsKeychainSource(
        environment: const <String, String>{'LOGNAME': 'log-name'},
        processRunner: (_, _, {required timeout}) async =>
            const ClaudeCodeKeychainProcessResult(exitCode: 1, stdout: ''),
      );
      expect(byLogName.accountName, 'log-name');
      expect(await byLogName.call(), isNull);
      final fallback = ClaudeCodeMacOsKeychainSource(
        environment: const <String, String>{},
        processRunner: (_, _, {required timeout}) async =>
            const ClaudeCodeKeychainProcessResult(exitCode: 1, stdout: ''),
      );
      expect(fallback.accountName, 'claude-code-user');
    },
  );

  test('small mapper fallbacks remain explicit', () async {
    expect(
      mapClaudeCodeInitializeMetadata(<String, Object?>{
        'type': 'control_response',
        'response': <String, Object?>{
          'subtype': 'success',
          'response': null,
        },
      }).models.models,
      isEmpty,
    );
    final quota = mapClaudeCodeUsageQuota(
      const <String, Object?>{
        'extra_usage': <String, Object?>{
          'is_enabled': true,
          'utilization': 20,
        },
      },
      providerId: 'claude_code',
      providerName: 'Claude',
    );
    expect(quota?.credits?.hasCredits, isTrue);
    final adapter = ClaudeCodeUsageQuotaAdapter(
      providerId: 'claude_code',
      providerName: 'Claude',
      metadataLoader: () async => throw StateError('unused'),
      accountDataEnrichmentEnabled: false,
    );
    expect(await adapter.readUsageQuota(), isNull);
  });

  test(
    'control adapters tolerate non-generic maps and malformed duplicates',
    () {
      final question = ClaudeCodeQuestionAdapter();
      final malformedQuestion = question.handleControlRequest(
        <String, Object?>{
          'request': <Object?, Object?>{
            'subtype': 'can_use_tool',
            'tool_name': claudeCodeAskUserQuestionToolName,
          },
        },
      );
      expect(malformedQuestion.responseFrame, isNotNull);
      final validQuestion = question.handleControlRequest(
        <String, Object?>{
          'request_id': 'question-1',
          'request': <Object?, Object?>{
            'subtype': 'can_use_tool',
            'tool_name': claudeCodeAskUserQuestionToolName,
            'tool_use_id': 'tool-question',
            'input': <Object?, Object?>{
              'questions': <Object?>[
                <Object?, Object?>{'question': 'Continue?'},
              ],
            },
          },
        },
      );
      expect(validQuestion.events, hasLength(1));
      expect(question.pending, contains('question-1'));

      final permission = ClaudeCodeControlRequestHandler();
      for (final (index, toolName) in <String>[
        'MultiEdit',
        'NotebookEdit',
        'WriterTool',
      ].indexed) {
        final result = permission.handle(<String, Object?>{
          'request_id': 'permission-$index',
          'request': <Object?, Object?>{
            'subtype': 'can_use_tool',
            'tool_use_id': 'permission-tool-$index',
            'tool_name': toolName,
            'input': <Object?, Object?>{},
          },
        });
        expect(
          (result.events.single as AgentPermissionRequestedEvent).request.kind,
          AgentPermissionKind.fileChange,
        );
      }

      final plan = ClaudeCodePlanApprovalAdapter()
        ..recordExitPlanToolUse(
          toolUseId: 'plan-tool',
          input: const <String, Object?>{'plan': 'Plan'},
          sessionId: 'session',
          turnId: 'turn',
        );
      final malformedPlan = plan.handleControlRequest(<String, Object?>{
        'request': <Object?, Object?>{
          'tool_name': 'ExitPlanMode',
          'tool_use_id': 'plan-tool',
        },
      });
      expect(malformedPlan.responseFrame, isNotNull);
      expect(plan.malformedCount, 1);
      final firstPlan = plan.handleControlRequest(<String, Object?>{
        'request_id': 'plan-request-1',
        'request': <String, Object?>{
          'subtype': 'can_use_tool',
          'tool_name': 'ExitPlanMode',
          'tool_use_id': 'plan-tool',
          'input': <String, Object?>{'plan': 'Plan'},
        },
      });
      expect(firstPlan.events, hasLength(1));
      final conflictingPlan = plan.handleControlRequest(<String, Object?>{
        'request_id': 'plan-request-2',
        'request': <String, Object?>{
          'subtype': 'can_use_tool',
          'tool_name': 'ExitPlanMode',
          'tool_use_id': 'plan-tool',
          'input': <String, Object?>{'plan': 'Plan'},
        },
      });
      expect(conflictingPlan.responseFrame, isNotNull);
      expect(
        plan.resolveDecision(
          const AgentPlanApprovalDecision(
            requestId: 'unknown',
            kind: AgentPlanApprovalDecisionKind.cancelled,
          ),
        ),
        isNull,
      );
      expect(plan.unknownDecisionCount, 1);
    },
  );
}

final class _FixedLocator extends ClaudeCodeCliLocator {
  @override
  Future<ResolvedCliProcessCommand?> locate(AgentProviderConfig config) async {
    return ResolvedCliProcessCommand(
      executable: '/bin/claude',
      arguments: const <String>[],
      displayPath: '/bin/claude',
    );
  }
}

String _dartExecutable() {
  final executable = Platform.resolvedExecutable;
  final marker = '${Platform.pathSeparator}cache${Platform.pathSeparator}';
  final markerIndex = executable.indexOf(marker);
  if (markerIndex < 0) {
    return executable;
  }
  final flutterRoot = executable.substring(0, markerIndex);
  final suffix = Platform.isWindows ? '.exe' : '';
  return '$flutterRoot${marker}dart-sdk${Platform.pathSeparator}bin'
      '${Platform.pathSeparator}dart$suffix';
}

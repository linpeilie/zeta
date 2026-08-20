import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zeta/agent_management/agent_management.dart';

class _MockAgentManagementRepository extends Mock
    implements AgentManagementRepository {}

void main() {
  final loadedAt = DateTime.utc(2026, 8, 20);
  final document = AgentConfigurationDocument(
    path: '/cfg',
    format: 'toml',
    contents: 'model = "gpt"',
    maskedContents: 'model = "gpt"',
    exists: true,
    loadedAt: loadedAt,
    signature: 'sig',
  );
  final detection = AgentDetection(
    providerId: 'codex',
    detectedAt: loadedAt,
    installed: true,
    accountState: AgentAccountState.loggedIn,
    configurationPath: '/cfg',
    configurationExists: true,
    logPaths: const <String>['/log'],
  );
  final testResult = AgentConnectionTest(
    providerId: 'codex',
    success: true,
    testedAt: loadedAt,
    elapsed: const Duration(milliseconds: 10),
    cliCallable: true,
    accountValid: true,
    protocolReady: true,
    models: const [],
    capabilityIds: const <String>[],
  );
  const failure = AgentManagementRepositoryFailure(
    providerId: 'codex',
    operation: AgentManagementRepositoryOperation.detect,
    code: AgentManagementRepositoryFailureCode.clientFailure,
    diagnosticCode: 'detect',
  );
  final log = AgentLogEntry(
    id: '1',
    sourcePath: '/log',
    message: 'ready',
    level: AgentLogLevel.info,
    timestamp: loadedAt,
  );

  group(AgentManagementBloc, () {
    late AgentManagementRepository repository;

    setUp(() {
      repository = _MockAgentManagementRepository();
      when(() => repository.definitions).thenReturn(AgentDefinition.all);
      when(
        () => repository.readConfiguration(any()),
      ).thenAnswer((_) async => document);
      when(
        () => repository.discoverLogPaths(any()),
      ).thenAnswer((_) async => const <String>['/log']);
      when(
        () => repository.validateConfiguration(
          format: any(named: 'format'),
          contents: any(named: 'contents'),
        ),
      ).thenReturn(AgentConfigurationValidation.valid);
      when(
        () => repository.detect(any()),
      ).thenAnswer((_) async => detection);
      when(
        () => repository.testConnection(any()),
      ).thenAnswer((_) async => testResult);
      when(
        () => repository.saveConfiguration(
          any(),
          contents: any(named: 'contents'),
        ),
      ).thenAnswer(
        (_) async => AgentConfigurationSaveResult(document: document),
      );
      when(
        () => repository.readLogs(any(), any()),
      ).thenAnswer((_) async => <AgentLogEntry>[log]);
    });

    AgentManagementBloc build() {
      return AgentManagementBloc(agentManagementRepository: repository);
    }

    blocTest<AgentManagementBloc, AgentManagementState>(
      'loads definitions and the first agent',
      build: build,
      act: (bloc) => bloc.add(const AgentManagementStarted()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.definitions, AgentDefinition.all);
        expect(
          bloc.state.selectedProviderId,
          'codex',
        );
        expect(bloc.state.document, document);
      },
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'ignores a blank agent selection',
      build: build,
      act: (bloc) => bloc.add(const AgentManagementAgentSelected('  ')),
      expect: () => const <AgentManagementState>[],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'detects the selected agent',
      build: build,
      seed: () => const AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
      ),
      act: (bloc) => bloc.add(const AgentManagementDetectRequested()),
      expect: () => <Matcher>[
        isA<AgentManagementState>().having(
          (state) => state.detecting,
          'detecting',
          isTrue,
        ),
        isA<AgentManagementState>()
            .having((state) => state.detecting, 'detecting', isFalse)
            .having((state) => state.detection?.installed, 'installed', isTrue),
      ],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'emits failure when detect throws',
      build: () {
        when(() => repository.detect(any())).thenThrow(
          const AgentManagementRepositoryException(
            failure: failure,
            cause: 'cli',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      seed: () => const AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
      ),
      act: (bloc) => bloc.add(const AgentManagementDetectRequested()),
      expect: () => <Matcher>[
        isA<AgentManagementState>().having(
          (state) => state.detecting,
          'detecting',
          isTrue,
        ),
        isA<AgentManagementState>()
            .having(
              (state) => state.status,
              'status',
              AgentManagementStatus.failure,
            )
            .having((state) => state.failure, 'failure', failure),
      ],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'tests the selected agent connection',
      build: build,
      seed: () => const AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
      ),
      act: (bloc) => bloc.add(const AgentManagementTestRequested()),
      verify: (bloc) {
        expect(bloc.state.connectionTest?.success, isTrue);
      },
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'validates edited configuration through the repository',
      build: build,
      seed: () => AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
        document: document,
      ),
      act: (bloc) {
        bloc.add(const AgentManagementConfigEdited('broken'));
      },
      verify: (_) {
        verify(
          () => repository.validateConfiguration(
            format: 'toml',
            contents: 'broken',
          ),
        ).called(1);
      },
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'saves valid configuration sequentially',
      build: build,
      seed: () => AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
        document: document,
        editorContents: 'model = "gpt"',
      ),
      act: (bloc) {
        bloc.add(const AgentManagementConfigSaveRequested());
      },
      verify: (_) {
        verify(
          () => repository.saveConfiguration(
            'codex',
            contents: 'model = "gpt"',
          ),
        ).called(1);
      },
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'does not save invalid configuration',
      build: build,
      seed: () => const AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
        validation: AgentConfigurationValidation(failureCode: 'invalid'),
        editorContents: 'nope',
      ),
      act: (bloc) {
        bloc.add(const AgentManagementConfigSaveRequested());
      },
      expect: () => const <AgentManagementState>[],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'emits failure when saving configuration throws',
      build: () {
        when(
          () => repository.saveConfiguration(
            any(),
            contents: any(named: 'contents'),
          ),
        ).thenThrow(
          const AgentManagementRepositoryException(
            failure: failure,
            cause: 'save',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      seed: () => const AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
        editorContents: 'ok',
      ),
      act: (bloc) {
        bloc.add(const AgentManagementConfigSaveRequested());
      },
      expect: () => <Matcher>[
        isA<AgentManagementState>().having(
          (state) => state.saving,
          'saving',
          isTrue,
        ),
        isA<AgentManagementState>().having(
          (state) => state.status,
          'status',
          AgentManagementStatus.failure,
        ),
      ],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'emits failure when log loading throws',
      build: () {
        when(() => repository.readLogs(any(), any())).thenThrow(
          const AgentManagementRepositoryException(
            failure: failure,
            cause: 'logs',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      seed: () => const AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
        logPaths: <String>['/log'],
      ),
      act: (bloc) => bloc.add(const AgentManagementLogsRequested()),
      expect: () => <Matcher>[
        isA<AgentManagementState>().having(
          (state) => state.status,
          'status',
          AgentManagementStatus.loading,
        ),
        isA<AgentManagementState>().having(
          (state) => state.status,
          'status',
          AgentManagementStatus.failure,
        ),
      ],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'emits failure when test, save, or log loading throws',
      build: () {
        when(() => repository.testConnection(any())).thenThrow(
          const AgentManagementRepositoryException(
            failure: failure,
            cause: 'test',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      seed: () => const AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
        editorContents: 'ok',
      ),
      act: (bloc) => bloc.add(const AgentManagementTestRequested()),
      expect: () => <Matcher>[
        isA<AgentManagementState>().having(
          (state) => state.testing,
          'testing',
          isTrue,
        ),
        isA<AgentManagementState>().having(
          (state) => state.status,
          'status',
          AgentManagementStatus.failure,
        ),
      ],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'loads logs for the selected agent',
      build: build,
      seed: () => const AgentManagementState(
        status: AgentManagementStatus.ready,
        selectedProviderId: 'codex',
        logPaths: <String>['/log'],
      ),
      act: (bloc) => bloc.add(const AgentManagementLogsRequested()),
      expect: () => <Matcher>[
        isA<AgentManagementState>().having(
          (state) => state.status,
          'status',
          AgentManagementStatus.loading,
        ),
        isA<AgentManagementState>().having(
          (state) => state.logs,
          'logs',
          <AgentLogEntry>[log],
        ),
      ],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'does not detect, test, save, or load logs without a selection',
      build: build,
      act: (bloc) {
        bloc
          ..add(const AgentManagementDetectRequested())
          ..add(const AgentManagementTestRequested())
          ..add(const AgentManagementConfigSaveRequested())
          ..add(const AgentManagementLogsRequested());
      },
      expect: () => const <AgentManagementState>[],
    );

    blocTest<AgentManagementBloc, AgentManagementState>(
      'emits failure when selection load throws',
      build: () {
        when(() => repository.readConfiguration(any())).thenThrow(
          const AgentManagementRepositoryException(
            failure: failure,
            cause: 'cfg',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      act: (bloc) {
        bloc.add(
          const AgentManagementAgentSelected('codex'),
        );
      },
      expect: () => <Matcher>[
        isA<AgentManagementState>().having(
          (state) => state.status,
          'status',
          AgentManagementStatus.loading,
        ),
        isA<AgentManagementState>().having(
          (state) => state.status,
          'status',
          AgentManagementStatus.failure,
        ),
      ],
    );

    test('event equality uses value props', () {
      expect(const AgentManagementStarted().props, isEmpty);
      expect(
        const AgentManagementAgentSelected('codex').props,
        <Object?>['codex'],
      );
      expect(const AgentManagementDetectRequested().props, isEmpty);
      expect(const AgentManagementTestRequested().props, isEmpty);
      expect(
        const AgentManagementConfigEdited('x').props,
        <Object?>['x'],
      );
      expect(const AgentManagementConfigSaveRequested().props, isEmpty);
      expect(const AgentManagementLogsRequested().props, isEmpty);
    });

    test('toString omits configuration secrets', () {
      const secret = 'api_key = "sk-secret"';
      final state = AgentManagementState(
        editorContents: secret,
        document: AgentConfigurationDocument(
          path: '/cfg',
          format: 'toml',
          contents: secret,
          maskedContents: 'api_key = "***"',
          exists: true,
          loadedAt: loadedAt,
          signature: 'sig',
        ),
      );
      expect(state.toString(), isNot(contains('sk-secret')));
      expect(state.toString(), contains('editorLength: ${secret.length}'));
    });

    test('copyWith clears optional management fields', () {
      final state = AgentManagementState(
        selectedProviderId: 'codex',
        detection: detection,
        connectionTest: testResult,
        document: document,
        failure: failure,
      );
      final cleared = state.copyWith(
        clearSelected: true,
        clearDetection: true,
        clearTest: true,
        clearDocument: true,
        clearFailure: true,
      );
      expect(cleared.selectedProviderId, isNull);
      expect(cleared.selectedDefinition, isNull);
      expect(cleared.detection, isNull);
      expect(cleared.connectionTest, isNull);
      expect(cleared.document, isNull);
      expect(cleared.failure, isNull);
    });
  });
}

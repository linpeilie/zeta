import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zeta/agent_management/agent_management.dart';
import 'package:zeta/l10n/l10n.dart';

import '../../helpers/helpers.dart';

class _MockAgentManagementBloc
    extends MockBloc<AgentManagementEvent, AgentManagementState>
    implements AgentManagementBloc {}

class _MockAgentManagementRepository extends Mock
    implements AgentManagementRepository {}

void main() {
  group(AgentManagementPage, () {
    late AgentManagementRepository repository;

    setUp(() {
      repository = _MockAgentManagementRepository();
      when(() => repository.definitions).thenReturn(AgentDefinition.all);
      when(
        () => repository.readConfiguration(any()),
      ).thenAnswer((_) async {
        return AgentConfigurationDocument(
          path: '/cfg',
          format: 'toml',
          contents: '',
          maskedContents: '',
          exists: false,
          loadedAt: DateTime.utc(2026, 8, 20),
          signature: 'sig',
        );
      });
      when(
        () => repository.discoverLogPaths(any()),
      ).thenAnswer((_) async => const <String>[]);
      when(
        () => repository.validateConfiguration(
          format: any(named: 'format'),
          contents: any(named: 'contents'),
        ),
      ).thenReturn(AgentConfigurationValidation.valid);
    });

    testWidgets('renders $AgentManagementView', (tester) async {
      await tester.pumpApp(
        RepositoryProvider<AgentManagementRepository>.value(
          value: repository,
          child: const AgentManagementPage(),
        ),
      );
      await tester.pump();
      expect(find.byType(AgentManagementView), findsOneWidget);
    });
  });

  group(AgentManagementView, () {
    late AgentManagementBloc bloc;

    setUp(() {
      bloc = _MockAgentManagementBloc();
      when(() => bloc.state).thenReturn(
        const AgentManagementState(
          status: AgentManagementStatus.ready,
          definitions: AgentDefinition.all,
          selectedProviderId: 'codex',
        ),
      );
    });

    testWidgets('selects an agent and requests detect', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      await tester.tap(find.text('Grok'));
      await tester.pump();
      verify(
        () => bloc.add(const AgentManagementAgentSelected('grok')),
      ).called(1);
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.mgmtDetectingShort));
      await tester.pump();
      verify(
        () => bloc.add(const AgentManagementDetectRequested()),
      ).called(1);
    });

    testWidgets('requests test, save, and logs', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.mgmtTestConnection));
      await tester.tap(find.text(l10n.mgmtSaveConfig));
      await tester.tap(find.text(l10n.mgmtRuntimeLogsTitle('Codex')));
      await tester.pump();
      verify(
        () => bloc.add(const AgentManagementTestRequested()),
      ).called(1);
      verify(
        () => bloc.add(const AgentManagementConfigSaveRequested()),
      ).called(1);
      verify(
        () => bloc.add(const AgentManagementLogsRequested()),
      ).called(1);
    });

    testWidgets('renders detection, invalid config, and log rows', (
      tester,
    ) async {
      when(() => bloc.state).thenReturn(
        AgentManagementState(
          status: AgentManagementStatus.ready,
          definitions: AgentDefinition.all,
          selectedProviderId: 'codex',
          detection: AgentDetection(
            providerId: 'codex',
            detectedAt: DateTime.utc(2026, 8, 20),
            installed: true,
            accountState: AgentAccountState.loggedIn,
            configurationPath: '/cfg',
            configurationExists: true,
            logPaths: const <String>['/log'],
          ),
          validation: const AgentConfigurationValidation(
            failureCode: 'invalid',
          ),
          logs: <AgentLogEntry>[
            AgentLogEntry(
              id: '1',
              sourcePath: '/log',
              message: 'ready',
              level: AgentLogLevel.info,
              timestamp: DateTime.utc(2026, 8, 20),
            ),
          ],
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.mgmtFound('Codex')), findsOneWidget);
      expect(find.text(l10n.mgmtConfigExternallyModified), findsOneWidget);
      expect(find.text('ready'), findsOneWidget);
    });

    testWidgets('edits configuration through the text field', (tester) async {
      when(() => bloc.state).thenReturn(
        const AgentManagementState(
          status: AgentManagementStatus.ready,
          definitions: AgentDefinition.all,
          selectedProviderId: 'codex',
          editorContents: 'model = "gpt"',
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      await tester.enterText(find.byType(TextFormField), 'model = "codex"');
      await tester.pump();
      verify(
        () => bloc.add(const AgentManagementConfigEdited('model = "codex"')),
      ).called(1);
    });

    testWidgets('renders not-found detection without a selected agent', (
      tester,
    ) async {
      when(() => bloc.state).thenReturn(
        AgentManagementState(
          status: AgentManagementStatus.ready,
          detection: AgentDetection(
            providerId: 'missing',
            detectedAt: DateTime.utc(2026, 8, 20),
            installed: false,
            accountState: AgentAccountState.unknown,
            configurationPath: '/cfg',
            configurationExists: false,
            logPaths: const <String>[],
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.mgmtNotFound('')), findsOneWidget);
    });

    testWidgets('announces detect, test, and save progress', (tester) async {
      when(() => bloc.state).thenReturn(
        const AgentManagementState(
          status: AgentManagementStatus.ready,
          definitions: AgentDefinition.all,
          selectedProviderId: 'codex',
          detecting: true,
          testing: true,
          saving: true,
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.mgmtDetecting), findsWidgets);
      expect(find.text(l10n.mgmtTesting), findsWidgets);
      expect(find.text(l10n.mgmtSaving), findsWidgets);
    });

    testWidgets('renders connection test success copy', (tester) async {
      when(() => bloc.state).thenReturn(
        AgentManagementState(
          status: AgentManagementStatus.ready,
          definitions: AgentDefinition.all,
          selectedProviderId: 'codex',
          connectionTest: AgentConnectionTest(
            providerId: 'codex',
            success: true,
            testedAt: DateTime.utc(2026, 8, 20),
            elapsed: const Duration(milliseconds: 12),
            cliCallable: true,
            accountValid: true,
            protocolReady: true,
            models: const [],
            capabilityIds: const <String>[],
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.mgmtConnectionTestSuccess('12')), findsOneWidget);
    });

    testWidgets('renders connection test failure copy', (tester) async {
      when(() => bloc.state).thenReturn(
        AgentManagementState(
          status: AgentManagementStatus.ready,
          definitions: AgentDefinition.all,
          selectedProviderId: 'codex',
          connectionTest: AgentConnectionTest(
            providerId: 'codex',
            success: false,
            testedAt: DateTime.utc(2026, 8, 20),
            elapsed: const Duration(milliseconds: 4),
            cliCallable: false,
            accountValid: false,
            protocolReady: false,
            models: const [],
            capabilityIds: const <String>[],
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(l10n.mgmtConnectionTestFailed(l10n.mgmtNotUpdated)),
        findsOneWidget,
      );
    });

    testWidgets('renders a management failure message', (tester) async {
      when(() => bloc.state).thenReturn(
        const AgentManagementState(
          status: AgentManagementStatus.failure,
          failure: AgentManagementRepositoryFailure(
            providerId: 'codex',
            operation: AgentManagementRepositoryOperation.detect,
            code: AgentManagementRepositoryFailureCode.clientFailure,
            diagnosticCode: 'detect',
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentManagementView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(
          FailureMessages(l10n).agentManagementFailure(
            AgentManagementRepositoryFailureCode.clientFailure,
          ),
        ),
        findsOneWidget,
      );
    });
  });
}

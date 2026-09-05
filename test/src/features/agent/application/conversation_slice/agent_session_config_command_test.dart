import 'dart:async';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_presentation_l10n.dart';
import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import '../../presentation/harness/agent_pane_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session config preserves an explicit unsupported failure', () async {
    final provider = _RejectingConfigProvider();
    final controller = createAgentPaneViewModel(
      provider,
      initialThread: agentPaneThread(id: 'config-thread', title: 'Config'),
    );
    addTearDown(controller.dispose);
    await controller.initialization;
    await controller.sendMessage('start');

    await expectLater(
      controller.selectSessionConfigOption('mode', 'smart'),
      throwsUnsupportedError,
    );
  });

  test('session config without a runtime reports unavailable', () async {
    final provider = _RejectingConfigProvider();
    final controller = createAgentPaneViewModel(
      provider,
      initialThread: agentPaneThread(id: 'config-thread', title: 'Config'),
    );
    addTearDown(controller.dispose);
    await controller.initialization;

    await expectLater(
      controller.selectSessionConfigOption('mode', 'smart'),
      completion(
        isA<AgentCommandFailed>().having(
          (result) => result.kind,
          'kind',
          AgentCommandFailureKind.providerUnavailable,
        ),
      ),
    );
  });
  test(
    'missing port throws at executor and becomes unsupported at UI boundary',
    () async {
      final f = await _fixture(hasPort: false);
      await expectLater(
        f.controller.selectSessionConfigOption('mode', 'smart'),
        throwsUnsupportedError,
      );
      expect(
        await invokeSessionConfigCommand(
          () => f.controller.selectSessionConfigOption('mode', 'smart'),
        ),
        _failed(AgentCommandFailureKind.unsupported),
      );
      expect(f.provider.sessionConfigSelections, isEmpty);
    },
  );

  test('draft and closed commands never execute', () async {
    final f = await _fixture(draft: true);
    expect(
      await f.controller.selectSessionConfigOption('mode', 'smart'),
      _ignored(AgentCommandIgnoreReason.notAllowed),
    );
    f.close();
    expect(
      await f.controller.selectSessionConfigOption('mode', 'smart'),
      _failed(AgentCommandFailureKind.staleTarget),
    );
    expect(f.provider.sessionConfigSelections, isEmpty);
  });

  test('read-only entry rejects session configuration', () async {
    final f = await _fixture();
    await f.controller.providerController.setProviderEnabled(
      f.provider.config.id,
      false,
    );
    expect(
      await f.controller.selectSessionConfigOption('mode', 'smart'),
      _ignored(AgentCommandIgnoreReason.notAllowed),
    );
    expect(f.provider.sessionConfigSelections, isEmpty);
  });

  for (final value in <Object>[
    'missing',
    'true',
    double.nan,
    double.infinity,
    <String>['smart'],
    <String, Object>{'id': 'smart'},
    Object(),
  ]) {
    test(
      'invalid scalar or option value is rejected: ${value.runtimeType} / $value',
      () async {
        final f = await _fixture();
        expect(
          await f.controller.selectSessionConfigOption('mode', value),
          _ignored(AgentCommandIgnoreReason.notAllowed),
        );
        expect(f.provider.sessionConfigSelections, isEmpty);
      },
    );
  }

  test('empty and removed configuration ids do not execute', () async {
    final f = await _fixture();
    for (final id in [' ', 'removed']) {
      expect(
        await f.controller.selectSessionConfigOption(id, 'smart'),
        _ignored(AgentCommandIgnoreReason.notAllowed),
      );
    }
    expect(f.provider.sessionConfigSelections, isEmpty);
  });

  test('only select and boolean kinds accept typed values', () async {
    final f = await _fixture();
    for (final kind in [
      AgentSessionConfigOptionKind.string,
      AgentSessionConfigOptionKind.number,
      AgentSessionConfigOptionKind.unknown,
    ]) {
      f.provider.options = [
        AgentSessionConfigOption(id: 'mode', name: 'Mode', kind: kind),
      ];
      expect(
        await f.controller.selectSessionConfigOption('mode', 'smart'),
        _ignored(AgentCommandIgnoreReason.notAllowed),
      );
    }
    f.provider.options = [
      const AgentSessionConfigOption(
        id: 'mode',
        name: 'Mode',
        kind: AgentSessionConfigOptionKind.boolean,
        currentValue: false,
      ),
    ];
    expect(
      await f.controller.selectSessionConfigOption('mode', 'true'),
      _ignored(AgentCommandIgnoreReason.notAllowed),
    );
    expect(
      await f.controller.selectSessionConfigOption('mode', true),
      isA<AgentCommandSucceeded>(),
    );
    expect(f.provider.sessionConfigSelections, [
      ('config-thread', 'mode', true),
    ]);
  });

  test(
    'select keeps String bool and finite num ids without coercion',
    () async {
      final f = await _fixture();
      for (final value in <Object>['smart', true, 1, 1.5]) {
        expect(
          await f.controller.selectSessionConfigOption(' mode ', value),
          isA<AgentCommandSucceeded>(),
        );
      }
      expect(f.provider.sessionConfigSelections.map((call) => call.$3), [
        'smart',
        true,
        1,
        1.5,
      ]);
      expect(f.provider.options.first.currentValue, 'fast');
    },
  );

  test('unchanged value is ignored without contacting provider', () async {
    final f = await _fixture();
    expect(
      await f.controller.selectSessionConfigOption('mode', 'fast'),
      _ignored(AgentCommandIgnoreReason.unchanged),
    );
    expect(f.provider.sessionConfigSelections, isEmpty);
  });

  test(
    'request exception is typed and does not overwrite status or expose raw text',
    () async {
      final f = await _fixture();
      final before = f.controller.headerState;
      f.provider.onSessionConfigRequest = (_, _, _) async =>
          throw StateError('private raw config value');
      final result = await f.controller.selectSessionConfigOption(
        'mode',
        'smart',
      );
      expect(result, _failed(AgentCommandFailureKind.requestFailed));
      expect((result as AgentCommandFailed).diagnostic, isNull);
      expect(f.controller.headerState, before);
      expect(f.provider.options.first.currentValue, 'fast');
    },
  );

  test(
    'same config queues in order while another config runs independently',
    () async {
      final f = await _fixture();
      final gate = Completer<void>();
      f.provider.onSessionConfigRequest = (_, id, value) =>
          id == 'mode' && value == 'smart' ? gate.future : Future.value();
      final a = f.controller.selectSessionConfigOption('mode', 'smart');
      final b = f.controller.selectSessionConfigOption('mode', true);
      final c = f.controller.selectSessionConfigOption('toggle', true);
      expect(await c, isA<AgentCommandSucceeded>());
      expect(f.provider.sessionConfigSelections, [
        ('config-thread', 'mode', 'smart'),
        ('config-thread', 'toggle', true),
      ]);
      gate.complete();
      expect(await a, isA<AgentCommandSucceeded>());
      expect(await b, isA<AgentCommandSucceeded>());
      expect(f.provider.sessionConfigSelections.last, (
        'config-thread',
        'mode',
        true,
      ));
    },
  );

  test('unsupported request does not poison the next queued request', () async {
    final f = await _fixture();
    f.provider.onSessionConfigRequest = (_, _, value) async {
      if (value == 'smart') throw UnsupportedError('fixture');
    };
    final a = expectLater(
      f.controller.selectSessionConfigOption('mode', 'smart'),
      throwsUnsupportedError,
    );
    final b = f.controller.selectSessionConfigOption('mode', true);
    await a;
    expect(await b, isA<AgentCommandSucceeded>());
    expect(f.provider.sessionConfigSelections.length, 2);
  });

  test(
    'queued request revalidates the latest options after its predecessor',
    () async {
      final f = await _fixture();
      final gate = Completer<void>();
      f.provider.onSessionConfigRequest = (_, _, _) => gate.future;
      final a = f.controller.selectSessionConfigOption('mode', 'smart');
      final b = f.controller.selectSessionConfigOption('mode', true);
      await _flush();
      f.provider.options = [];
      gate.complete();
      expect(await a, isA<AgentCommandSucceeded>());
      expect(await b, _ignored(AgentCommandIgnoreReason.notAllowed));
      expect(f.provider.sessionConfigSelections.length, 1);
    },
  );

  test('disabling provider invalidates queued request scope', () async {
    final f = await _fixture();
    final gate = Completer<void>();
    f.provider.onSessionConfigRequest = (_, _, _) => gate.future;
    final a = f.controller.selectSessionConfigOption('mode', 'smart');
    final b = f.controller.selectSessionConfigOption('mode', true);
    await _flush();
    await f.controller.providerController.setProviderEnabled(
      f.provider.config.id,
      false,
    );
    gate.complete();
    await a;
    expect(await b, _failed(AgentCommandFailureKind.staleTarget));
    expect(f.provider.sessionConfigSelections.length, 1);
  });

  for (final error in <Object?>[
    null,
    StateError('late private error'),
    UnsupportedError('late private rejection'),
  ]) {
    test(
      'runtime replacement invalidates active and queued results: ${error.runtimeType}',
      () async {
        final f = await _fixture();
        final gate = Completer<void>();
        f.provider.onSessionConfigRequest = (_, _, _) => gate.future;
        final a = f.controller.selectSessionConfigOption('mode', 'smart');
        final b = f.controller.selectSessionConfigOption('mode', true);
        await _flush();
        final oldIdentity =
            f.controller.conversationBinding.currentRuntime!.runtimeIdentity;
        await f.controller.conversationBinding.invalidateRuntime();
        final activity = await f.controller.conversationBinding.beginTurn();
        expect(
          f.controller.conversationBinding.currentRuntime!.runtimeIdentity,
          isNot(oldIdentity),
        );
        if (error == null) {
          gate.complete();
        } else {
          gate.completeError(error);
        }
        expect(await a, _failed(AgentCommandFailureKind.staleTarget));
        expect(await b, _failed(AgentCommandFailureKind.staleTarget));
        expect(f.provider.sessionConfigSelections.length, 1);
        await activity.release();
      },
    );
  }

  test('runtime invalidated before queue starts never executes', () async {
    final f = await _fixture();
    final pending = f.controller.selectSessionConfigOption('mode', 'smart');
    await f.controller.conversationBinding.invalidateRuntime();
    expect(await pending, _failed(AgentCommandFailureKind.staleTarget));
    expect(f.provider.sessionConfigSelections, isEmpty);
  });

  for (final lateError in [false, true]) {
    test(
      'dispose settles active and queued waiters before provider finishes: $lateError',
      () async {
        final f = await _fixture();
        final gate = Completer<void>();
        f.provider.onSessionConfigRequest = (_, _, _) => gate.future;
        final a = f.controller.selectSessionConfigOption('mode', 'smart');
        final b = f.controller.selectSessionConfigOption('mode', true);
        await _flush();
        var publications = 0;
        f.controller.addUiUpdateListener((_) => publications++);
        f.close();
        expect(
          await a.timeout(const Duration(seconds: 1)),
          _failed(AgentCommandFailureKind.staleTarget),
        );
        expect(
          await b.timeout(const Duration(seconds: 1)),
          _failed(AgentCommandFailureKind.staleTarget),
        );
        if (lateError) {
          gate.completeError(UnsupportedError('late'));
        } else {
          gate.complete();
        }
        await _flush();
        expect(publications, 0);
        expect(f.provider.sessionConfigSelections.length, 1);
      },
    );
  }

  test('closing before queue execution sends no request', () async {
    final f = await _fixture();
    final pending = f.controller.selectSessionConfigOption('mode', 'smart');
    f.close();
    expect(await pending, _failed(AgentCommandFailureKind.staleTarget));
    await _flush();
    expect(f.provider.sessionConfigSelections, isEmpty);
  });

  test(
    'two thread controllers do not share queues or completion state',
    () async {
      final a = await _fixture();
      final b = await _fixture(
        threadId: 'other-thread',
        providerConfig: defaultGrokAgentProviderConfig,
      );
      expect(a.provider.config.id, isNot(b.provider.config.id));
      final gate = Completer<void>();
      a.provider.onSessionConfigRequest = (_, _, _) => gate.future;
      final pending = a.controller.selectSessionConfigOption('mode', 'smart');
      expect(
        await b.controller.selectSessionConfigOption('mode', true),
        isA<AgentCommandSucceeded>(),
      );
      expect(b.provider.sessionConfigSelections.single, (
        'other-thread',
        'mode',
        true,
      ));
      a.close();
      expect(await pending, _failed(AgentCommandFailureKind.staleTarget));
      gate.complete();
      await _flush();
      expect(b.provider.sessionConfigSelections.length, 1);
    },
  );
}

class _RejectingConfigProvider extends AgentPaneFakeProvider {
  @override
  List<AgentSessionConfigOption> sessionConfigOptions(String sessionId) =>
      const [
        AgentSessionConfigOption(
          id: 'mode',
          name: 'Mode',
          kind: AgentSessionConfigOptionKind.select,
          currentValue: 'fast',
          values: [AgentSessionConfigValue(id: 'smart', label: 'Smart')],
        ),
      ];

  @override
  Future<void> setSessionConfigOption({
    required String sessionId,
    required String configId,
    required Object value,
  }) async {
    throw UnsupportedError('fixture rejection');
  }
}

Matcher _failed(AgentCommandFailureKind kind) =>
    isA<AgentCommandFailed>().having((result) => result.kind, 'kind', kind);
Matcher _ignored(AgentCommandIgnoreReason reason) => isA<AgentCommandIgnored>()
    .having((result) => result.reason, 'reason', reason);
Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<_Fixture> _fixture({
  bool hasPort = true,
  bool draft = false,
  String threadId = 'config-thread',
  AgentProviderConfig? providerConfig,
}) async {
  final provider = _ConfigProvider(providerConfig);
  addTearDown(provider.closeEvents);
  final controller = createAgentPaneViewModel(
    provider,
    initialThread: draft
        ? null
        : agentPaneThread(
            id: threadId,
            title: 'Config',
          ).copyWith(providerId: provider.config.id),
    providerFactory: hasPort ? null : AgentPaneNoSessionConfigFactory(provider),
  );
  final fixture = _Fixture(provider, controller);
  addTearDown(fixture.close);
  await controller.initialization;
  if (!draft) await controller.sendMessage('start');
  return fixture;
}

class _Fixture {
  _Fixture(this.provider, this.controller);
  final _ConfigProvider provider;
  final AgentConversationRuntimeController controller;
  bool closed = false;
  void close() {
    if (closed) return;
    closed = true;
    controller.dispose();
  }
}

class _ConfigProvider extends AgentPaneFakeProvider {
  _ConfigProvider(this.providerConfig);
  final AgentProviderConfig? providerConfig;
  @override
  AgentProviderConfig get config => providerConfig ?? super.config;
  List<AgentSessionConfigOption> options = const [
    AgentSessionConfigOption(
      id: 'mode',
      name: 'Mode',
      kind: AgentSessionConfigOptionKind.select,
      currentValue: 'fast',
      values: [
        AgentSessionConfigValue(id: 'fast', label: 'Fast'),
        AgentSessionConfigValue(id: 'smart', label: 'Smart'),
        AgentSessionConfigValue(id: true, label: 'Boolean'),
        AgentSessionConfigValue(id: 1, label: 'Integer'),
        AgentSessionConfigValue(id: 1.5, label: 'Number'),
      ],
    ),
    AgentSessionConfigOption(
      id: 'toggle',
      name: 'Toggle',
      kind: AgentSessionConfigOptionKind.boolean,
      currentValue: false,
    ),
  ];
  @override
  List<AgentSessionConfigOption> sessionConfigOptions(String sessionId) =>
      options;
  // runtime 换代测试复用可控端口，流在测试结束时单独关闭。
  @override
  Future<void> dispose() async {}
  Future<void> closeEvents() => super.dispose();
}

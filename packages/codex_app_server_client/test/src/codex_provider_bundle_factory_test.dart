import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:clock/clock.dart';
import 'package:codex_app_server_client/codex_app_server_client.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  group('CodexProviderBundleFactory', () {
    test('production starter launches the requested executable', () async {
      final executable = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
      final arguments = Platform.isWindows
          ? const <String>['/d', '/c', 'exit 0']
          : const <String>['-c', 'exit 0'];
      final process = await CodexProviderBundleFactory.startProcess(
        executable,
        arguments,
        workingDirectory: Directory.current.path,
      );

      expect(await process.exitCode, 0);
    });

    test('builds every supported neutral port from injected seams', () async {
      final peer = _NoopJsonRpcPeer();
      final logger = loggerFor('zeta.test.codex_bundle');
      final fixedClock = Clock.fixed(DateTime.utc(2026, 8, 19));
      late AgentProviderConfig capturedConfig;
      late ProcessStarter capturedProcessStarter;
      late AppLogger capturedLogger;
      late Clock capturedClock;

      final factory = CodexProviderBundleFactory(
        peerFactory:
            ({
              required config,
              required processStarter,
              required logger,
              required clock,
            }) {
              capturedConfig = config;
              capturedProcessStarter = processStarter;
              capturedLogger = logger;
              capturedClock = clock;
              return peer;
            },
        processStarter: _unreachableProcessStarter,
        logger: logger,
        clock: fixedClock,
      );

      final config = AgentProviderConfig.defaultCodex;
      final bundle = factory.createBundle(config);
      addTearDown(bundle.runtime.dispose);

      expect(capturedConfig, same(config));
      expect(capturedProcessStarter, isNot(same(_unreachableProcessStarter)));
      expect(capturedLogger, same(logger));
      expect(capturedClock, same(fixedClock));
      expect(bundle.runtime.config, same(config));
      expect(bundle.conversation, same(bundle.runtime));
      expect(bundle.threadCatalog, same(bundle.runtime));
      expect(bundle.threadSubscription, same(bundle.runtime));
      expect(bundle.threadNaming, same(bundle.runtime));
      expect(bundle.threadArchival, same(bundle.runtime));
      expect(bundle.threadDeletion, same(bundle.runtime));
      expect(bundle.threadCompaction, same(bundle.runtime));
      expect(bundle.threadBranching, same(bundle.runtime));
      expect(bundle.turnSteering, same(bundle.runtime));
      expect(bundle.permissionResponses, same(bundle.runtime));
      expect(bundle.questions, same(bundle.runtime));
      expect(bundle.deniedActionOverride, same(bundle.runtime));
      expect(bundle.modelCatalog, same(bundle.runtime));
      expect(bundle.conversationModes, same(bundle.runtime));
      expect(bundle.skills, same(bundle.runtime));
      expect(bundle.usageQuota, same(bundle.runtime));
      expect(bundle.permissionPolicy, isNotNull);
      expect(bundle.capabilities, CodexStaticCapabilities.value);
    });

    test('production peer constructor preserves injected transport seams', () {
      final logger = loggerFor('zeta.test.codex_peer');
      final fixedClock = Clock.fixed(DateTime.utc(2026, 8, 20));
      final config = AgentProviderConfig.defaultCodex;

      final peer = CodexProviderBundleFactory.createPeer(
        config: config,
        processStarter: _unreachableProcessStarter,
        logger: logger,
        clock: fixedClock,
      );
      addTearDown(peer.close);

      expect(peer.command, config.command);
      expect(peer.arguments, config.arguments);
      expect(peer.environment, config.environment);
      expect(peer.clock, same(fixedClock));
    });
  });

  group('CodexCliLocator', () {
    test('accepts only exact Codex executable basenames', () {
      expect(looksLikeCodexCliPath('/tools/codex'), isTrue);
      expect(looksLikeCodexCliPath(r'C:\tools\codex.exe'), isTrue);
      expect(looksLikeCodexCliPath(r'C:\tools\codex.cmd'), isTrue);
      expect(looksLikeCodexCliPath(r'C:\tools\codex.ps1'), isTrue);
      expect(looksLikeCodexCliPath('/tools/codex-helper'), isFalse);
      expect(looksLikeCodexCliPath('/tools/not-codex'), isFalse);
    });

    test('wraps Windows command and PowerShell launchers safely', () async {
      final locator = CodexCliLocator(
        environment: const <String, String>{'SystemRoot': r'C:\Windows'},
        isWindows: true,
        fileExists: (_) async => true,
      );

      final command = await locator.resolvePath(r'C:\tools\codex.cmd');
      expect(command?.executable, r'C:\Windows\System32\cmd.exe');
      expect(
        command?.arguments,
        <String>['/d', '/s', '/c', 'call', r'C:\tools\codex.cmd'],
      );

      final powerShell = await locator.resolvePath(r'C:\tools\codex.ps1');
      expect(
        powerShell?.executable,
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      );
      expect(
        powerShell?.arguments,
        <String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-File',
          r'C:\tools\codex.ps1',
        ],
      );
    });

    test(
      'discovers every Windows install source without host branching',
      () async {
        const localAppData = r'C:\Users\tester\AppData\Local';
        const appData = r'C:\Users\tester\AppData\Roaming';
        final checked = <String>[];
        final locator = CodexCliLocator(
          environment: const <String, String>{
            'PATH': r'C:\tools;C:\secondary',
            'LOCALAPPDATA': localAppData,
            'APPDATA': appData,
            'SystemRoot': r'C:\Windows',
          },
          isWindows: true,
          fileExists: (path) async {
            checked.add(path);
            return path == '$appData\\npm\\codex.cmd';
          },
        );

        final resolved = await locator.locate(
          AgentProviderConfig.defaultCodex.copyWith(
            command: r'C:\stale\codex.ps1',
            extra: <String, Object?>{'cliPath': r'C:\also-stale\codex.exe'},
          ),
        );

        expect(resolved?.displayPath, '$appData\\npm\\codex.cmd');
        expect(resolved?.executable, r'C:\Windows\System32\cmd.exe');
        expect(checked, contains(r'C:\tools\codex.exe'));
        expect(checked, contains(r'C:\tools\codex.bat'));
        expect(
          checked,
          contains('$localAppData\\Programs\\OpenAI\\Codex\\bin\\codex.exe'),
        );
        expect(
          checked,
          contains('$localAppData\\Programs\\codex\\codex.exe'),
        );
        expect(checked, contains('$localAppData\\npm\\codex.cmd'));
      },
    );

    test(
      'preserves a Windows UNC root when joining a PATH candidate',
      () async {
        final locator = CodexCliLocator(
          environment: const <String, String>{'PATH': r'\\server\tools'},
          isWindows: true,
          fileExists: (path) async => path == r'\\server\tools\codex.exe',
        );

        final resolved = await locator.locate(AgentProviderConfig.defaultCodex);

        expect(resolved?.displayPath, r'\\server\tools\codex.exe');
      },
    );
  });
}

Future<Process> _unreachableProcessStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  throw StateError('The bundle factory test must not start a process.');
}

final class _NoopJsonRpcPeer implements JsonRpcPeer {
  @override
  Stream<JsonRpcNotification> get notifications => const Stream.empty();

  @override
  Stream<TransportException> get protocolErrors => const Stream.empty();

  @override
  Stream<JsonRpcRequest> get serverRequests => const Stream.empty();

  @override
  Stream<String> get stderrLines => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  void sendNotification(String method, {Object? params}) {}

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async => null;

  @override
  Future<void> sendResponse(
    Object id, {
    Object? result,
    JsonRpcError? error,
  }) async {}

  @override
  Future<void> start() async {}
}

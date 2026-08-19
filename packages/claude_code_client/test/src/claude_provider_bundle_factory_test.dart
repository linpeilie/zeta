import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/claude_code_client.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  group('ClaudeProviderBundleFactory', () {
    test('production starter launches the requested executable', () async {
      final executable = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
      final arguments = Platform.isWindows
          ? const <String>['/d', '/c', 'exit 0']
          : const <String>['-c', 'exit 0'];

      final process = await ClaudeProviderBundleFactory.startProcess(
        executable,
        arguments,
        workingDirectory: Directory.current.path,
      );

      expect(await process.exitCode, 0);
    });

    test('builds every supported neutral port from injected seams', () async {
      final logger = loggerFor('zeta.test.claude_bundle');
      final fixedClock = Clock.fixed(DateTime.utc(2026, 8, 19));
      final factory = ClaudeProviderBundleFactory(
        peerFactory: ClaudeProviderBundleFactory.createPeer,
        processStarter: _unreachableProcessStarter,
        logger: logger,
        clock: fixedClock,
      );

      final bundle = factory.createBundle(
        AgentProviderConfig.defaultClaudeCode,
      );
      addTearDown(bundle.runtime.dispose);

      expect(factory.peerFactory, same(ClaudeProviderBundleFactory.createPeer));
      expect(factory.processStarter, same(_unreachableProcessStarter));
      expect(factory.logger, same(logger));
      expect(factory.clock, same(fixedClock));
      expect(bundle.conversation, same(bundle.runtime));
      expect(bundle.threadCatalog, same(bundle.runtime));
      expect(bundle.threadCompaction, same(bundle.runtime));
      expect(bundle.permissionResponses, same(bundle.runtime));
      expect(bundle.questions, same(bundle.runtime));
      expect(bundle.modelCatalog, same(bundle.runtime));
      expect(bundle.localThreadList, same(bundle.runtime));
      expect(bundle.planApproval, same(bundle.runtime));
      expect(bundle.usageQuota, same(bundle.runtime));
      expect(bundle.permissionPolicy, isNotNull);
      expect(bundle.capabilities, ClaudeStaticCapabilities.value);
    });

    test('production peer constructor preserves injected transport seams', () {
      final logger = loggerFor('zeta.test.claude_peer');

      final peer = ClaudeProviderBundleFactory.createPeer(
        command: 'claude',
        arguments: const <String>['--input-format', 'stream-json'],
        workingDirectory: Directory.current.path,
        environment: const <String, String>{'ZETA_TEST': '1'},
        processStarter: _unreachableProcessStarter,
        logger: logger,
      );
      addTearDown(peer.close);

      expect(peer.command, 'claude');
      expect(peer.arguments, const <String>['--input-format', 'stream-json']);
      expect(peer.workingDirectory, Directory.current.path);
      expect(peer.environment, const <String, String>{'ZETA_TEST': '1'});
    });
  });
}

Future<Process> _unreachableProcessStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  throw StateError('The bundle factory test must not start Claude Code.');
}

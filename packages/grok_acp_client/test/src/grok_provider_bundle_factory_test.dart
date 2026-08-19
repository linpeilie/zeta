import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/grok_acp_client.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  group('GrokProviderBundleFactory', () {
    test('production starter launches the requested executable', () async {
      final executable = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
      final arguments = Platform.isWindows
          ? const <String>['/d', '/c', 'exit 0']
          : const <String>['-c', 'exit 0'];

      final process = await GrokProviderBundleFactory.startProcess(
        executable,
        arguments,
        workingDirectory: Directory.current.path,
      );

      expect(await process.exitCode, 0);
    });

    test('builds every supported neutral port from injected seams', () async {
      final logger = loggerFor('zeta.test.grok_bundle');
      final factory = GrokProviderBundleFactory(
        processStarter: _unreachableProcessStarter,
        logger: logger,
      );

      final bundle = factory.createBundle(AgentProviderConfig.defaultGrok);
      addTearDown(bundle.runtime.dispose);

      expect(factory.processStarter, same(_unreachableProcessStarter));
      expect(factory.logger, same(logger));
      expect(bundle.conversation, same(bundle.runtime));
      expect(bundle.threadCatalog, same(bundle.runtime));
      expect(bundle.threadNaming, same(bundle.runtime));
      expect(bundle.threadDeletion, same(bundle.runtime));
      expect(bundle.permissionResponses, same(bundle.runtime));
      expect(bundle.questions, same(bundle.runtime));
      expect(bundle.modelCatalog, same(bundle.runtime));
      expect(bundle.conversationModes, same(bundle.runtime));
      expect(bundle.skills, same(bundle.runtime));
      expect(bundle.planApproval, same(bundle.runtime));
      expect(bundle.usageQuota, same(bundle.runtime));
      expect(bundle.permissionPolicy, isNotNull);
      expect(bundle.capabilities.canCreateSession, isTrue);
      expect(bundle.capabilities.canResumeSession, isTrue);
      expect(bundle.capabilities.supportsPermissionRequests, isTrue);
      expect(GrokStaticCapabilities.value.canResumeSession, isTrue);
    });
  });
}

Future<Process> _unreachableProcessStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  throw StateError('The bundle factory test must not start Grok.');
}

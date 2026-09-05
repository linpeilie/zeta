import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../../testing/provider_architecture_audit.dart'
    show providerPluginLibRoots;

/// 架构守卫：钉住 native Bundle 边界，避免测试万能 fake
/// 或共享层分支出卖真实端口矩阵。
void main() {
  group('provider bundle architecture contracts', () {
    test('no production adapter implements session configuration', () {
      for (final file in <File>[
        for (final root in <String>[...providerPluginLibRoots()])
          ..._dartFiles(root),
      ]) {
        expect(
          file.readAsStringSync(),
          isNot(contains('AgentSessionConfigProvider')),
          reason: file.path,
        );
      }
    });

    test('domain capabilities stay vendor-neutral', () {
      final source = File(
        'packages/zeta_agent_core/lib/src/domain/agent_provider_capabilities.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('defaultsFor')));
      expect(source, isNot(contains('static const codexAppServer')));
      expect(source, isNot(contains('static const grokAcp')));
      expect(source, isNot(contains('static const claudeCode')));
      expect(source, isNot(contains('AgentProviderTypeId.')));
    });

    test('shared bundle has no adapt path or provider-kind branches', () {
      final source = File(
        'packages/zeta_agent_core/lib/src/domain/agent_provider_bundle.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('factory AgentProviderBundle.adapt')));
      expect(source, isNot(contains('_LegacyAgent')));
      expect(
        File(
          'packages/zeta_agent_core/lib/src/domain/agent_provider.dart',
        ).existsSync(),
        isFalse,
      );
      for (final token in const <String>[
        'codexAgentProviderType',
        'grokAgentProviderType',
        'claudeCodeAgentProviderType',
        'codexAppServer',
        'grokAcp',
        'claudeCode',
        'AgentThreadMutationsPort',
        'AgentInteractionPort',
        'threadMutations',
      ]) {
        expect(source, isNot(contains(token)), reason: token);
      }
    });

    test(
      'RuntimeController still AND-gates reasoning UI on capability and model efforts',
      () {
        final source = File(
          'lib/src/features/agent/application/conversation_slice/'
          'agent_conversation_runtime_controller.dart',
        ).readAsStringSync();

        expect(source, contains('bool get showReasoningEffort'));
        expect(source, contains('activeCapabilities.supportsReasoningOptions'));
        expect(source, contains('selectedModel?.supportedReasoningEfforts'));
      },
    );

    test('model config widget still reads model-level reasoning efforts', () {
      final source = File(
        'lib/src/features/agent/presentation/widgets/agent_model_config.dart',
      ).readAsStringSync();

      expect(source, contains('model.supportedReasoningEfforts'));
      expect(source, contains('state.supportsReasoningOptions'));
    });
  });
}

Iterable<File> _dartFiles(String root) {
  return Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

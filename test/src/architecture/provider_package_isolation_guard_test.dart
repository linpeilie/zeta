import 'package:flutter_test/flutter_test.dart';

import '../testing/provider_architecture_audit.dart';

void main() {
  test('Provider 包隔离、manifest 出口、共享纯度与贡献接缝保持目标边界', () {
    final sources = providerAuditSources();
    expect(
      sources.keys.where(
        (p) =>
            p.startsWith('packages/zeta_agent_provider_') &&
            p.contains('/lib/'),
      ),
      isNotEmpty,
    );
    final issues = auditProviderArchitecture(sources);
    expect(issues, isEmpty, reason: issues.join('\n'));
  });

  const guide = "const _setupGuideAgentId = 'claude_code';";
  const sdk = 'packages/zeta_agent_provider_sdk/lib/src/transport/peer.dart';
  const api = 'packages/zeta_agent_provider_api/lib/src/model.dart';
  const plugin = 'packages/zeta_agent_provider_future/lib/plugin.dart';
  final mutations = <(String, String, String)>[
    (
      'package-direction',
      plugin,
      "import 'package:zeta_agent_provider_codex/zeta_agent_provider_codex.dart';",
    ),
    (
      'package-direction',
      api,
      "export 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';",
    ),
    (
      'package-direction',
      sdk,
      "import 'safe.dart' if (dart.library.io) 'package:zeta_agent_provider_future/plugin.dart';",
    ),
    (
      'package-direction',
      plugin,
      "import '../../zeta_agent_provider_grok/lib/grok_plugin.dart';",
    ),
    ('pure-dart', api, "import 'dart:io';"),
    (
      'pure-dart',
      plugin,
      "import 'package:flutter_riverpod/flutter_riverpod.dart';",
    ),
    ('pure-dart', sdk, "export 'package:flutter/widgets.dart';"),
    (
      'manifest-only',
      'lib/src/app/bypass.dart',
      "export 'package:zeta_agent_provider_future/plugin.dart';",
    ),
    (
      'test-boundary',
      'test/src/app/plugins/fake_agent_provider_plugin_e2e_test.dart',
      "import 'package:zeta_agent_provider_future/plugin.dart';",
    ),
    (
      'private-import',
      plugin,
      "import 'package:zeta_agent_provider_api/src/model.dart';",
    ),
    (
      'testing-leak',
      plugin,
      "import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart';",
    ),
    (
      'manifest-export',
      providerManifestPath,
      "export 'package:zeta_agent_provider_future/plugin.dart' show RuntimeImplementation;",
    ),
    (
      'manifest-export',
      providerManifestPath,
      "export 'package:zeta_agent_provider_future/plugin.dart';",
    ),
    (
      'metric-constant',
      plugin,
      "final d = AgentProviderDefinition(metricLabel: ZetaMetricLabel.hashed('future'));",
    ),
    ('type-literal', 'lib/src/app/route.dart', 'const protocol = "acp";'),
    (
      'setup-guide',
      'lib/src/features/agent/presentation/other.dart',
      "const id = 'claude_code';",
    ),
    (
      'setup-guide',
      'lib/src/features/agent/presentation/widgets/agent_provider_icon.dart',
      "bool show(String id) => id == 'claude_code';",
    ),
    (
      'setup-guide',
      'lib/src/features/agent/presentation/widgets/agent_provider_icon.dart',
      "const _agentProviderIconAssets = {'claude_code': 'assets/brand.svg'};",
    ),
    ('setup-guide', providerSetupGuidePath, "const anotherId = 'claude_code';"),
    (
      'static-vendor-table',
      'lib/src/app/route.dart',
      'final id = AgentDefinition.claudeCode.id;',
    ),
    ('shared-purity', sdk, '/* comments are ignored */ final isGrok = true;'),
    (
      'shared-purity',
      'packages/zeta_agent_core/lib/src/application/reduction/new_handler.dart',
      "final providerId = 'codex';",
    ),
    (
      'contribution-seam',
      'lib/src/app/composition/bypass.dart',
      'final c = catalog.registry /* disguised */ . contributions<T>();',
    ),
    (
      'contribution-seam',
      'lib/src/app/usage_statistics_slice/bypass.dart',
      'final c = pluginRegistry;',
    ),
  ];
  for (final (rule, path, badSource) in mutations) {
    test('反例拦截 $rule $path $badSource', () {
      final issues = auditProviderArchitecture({
        providerSetupGuidePath: guide,
        path: badSource,
      });
      expect(
        issues.any((issue) => issue.startsWith('$rule:')),
        isTrue,
        reason: issues.join('\n'),
      );
    });
  }
  test('反例：常量实现对象仍不得经 manifest 倒灌', () {
    final issues = auditProviderArchitecture({
      providerSetupGuidePath: guide,
      plugin: 'const VendorRuntime runtime = VendorRuntime();',
      providerManifestPath:
          "export 'package:zeta_agent_provider_future/plugin.dart' show runtime;",
    });
    expect(issues, contains('manifest-export: $providerManifestPath'));
  });
  test('反例拦截删除唯一安装指引登记', () {
    expect(auditProviderArchitecture({}), contains('setup-guide-count: 0'));
  });
  test('注释不误报，中立 API、IO SDK 和测试入口允许合法依赖', () {
    expect(
      auditProviderArchitecture({
        providerSetupGuidePath: guide,
        sdk: "// codex grok claude\nimport 'dart:io';",
        plugin:
            "import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';",
        'test/src/testing/future.dart':
            "import 'package:zeta_agent_provider_future/plugin.dart';",
      }),
      isEmpty,
    );
  });
}

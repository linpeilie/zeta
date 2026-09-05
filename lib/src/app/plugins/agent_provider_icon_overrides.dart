import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta/src/features/agent/application/agent_provider_icon_resolver.dart';

/// 入口与测试复用同一静态装配，不读取激活目录或冻结本地化状态。
Override agentProviderIconsOverride({AgentProviderDefinitionCatalog? catalog}) {
  final definitions = catalog ?? zetaAgentProviderDefinitionCatalog;
  return agentProviderIconResolverProvider.overrideWithValue(
    (providerId) => definitions.definitionForProviderId(providerId)?.icon,
  );
}

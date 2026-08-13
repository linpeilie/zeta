import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

/// 把旧 [AgentProviderFactory] 适配成 Bundle 工厂。
///
/// 只允许出现在 data / 组合层和测试过渡路径；S5 删除。
/// 生产默认工厂不得经过这里。
final class LegacyAgentProviderFactoryBundleAdapter
    implements AgentProviderBundleFactory {
  const LegacyAgentProviderFactoryBundleAdapter(this._factory);

  final AgentProviderFactory _factory;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    return AgentProviderBundle.adapt(_factory.create(config));
  }
}

/// 将旧 Factory 或已实现 Bundle 工厂的对象收成 Registry 可用的入口。
AgentProviderBundleFactory asAgentProviderBundleFactory(
  AgentProviderFactory factory,
) {
  if (factory is AgentProviderBundleFactory) {
    return factory as AgentProviderBundleFactory;
  }
  return LegacyAgentProviderFactoryBundleAdapter(factory);
}

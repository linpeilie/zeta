import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

/// 测试过渡：旧 Factory 通过 adapt() 提供 Bundle。S4 删除。
mixin LegacyBundleFactoryMixin on AgentProviderFactory
    implements AgentProviderBundleFactory {
  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    return AgentProviderBundle.adapt(create(config));
  }
}

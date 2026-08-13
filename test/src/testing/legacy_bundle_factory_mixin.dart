import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

/// 测试过渡：把仍返回 raw [AgentProvider] 的工厂收成 Bundle 工厂。
///
/// 仅允许出现在 adapter 自测与尚未改写完的局部测试工厂；S5 删除。
mixin LegacyBundleFactoryMixin implements AgentProviderBundleFactory {
  AgentProvider create(AgentProviderConfig config);

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    return AgentProviderBundle.adapt(create(config));
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// 根据已登记的稳定 Provider id 查询静态图标，不猜测自定义实例的品牌。
typedef AgentProviderIconResolver = AgentProviderSvgIcon? Function(String);

/// 图标查询不接入插件激活链；生产入口通过 app 层注入静态 manifest。
///
/// 图标是可选展示元数据。独立组件未装目录时安全显示中立图标，不影响能力判断。
final agentProviderIconResolverProvider = Provider<AgentProviderIconResolver>(
  (ref) =>
      (_) => null,
  name: 'agentProviderIconResolver',
);

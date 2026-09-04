/// Zeta Agent Provider 插件的宿主侧契约。
///
/// 这里只放**不含厂商语义**的装配契约；协议机制在 `zeta_agent_provider_sdk`，
/// 厂商实现在 `zeta_agent_provider_<x>`。依赖方向：本包只依赖
/// core / kernel / foundation。契约面会随新的贡献类型继续扩展。
library;

export 'src/agent_provider_definition.dart';
export 'src/agent_provider_plugin_contribution.dart';

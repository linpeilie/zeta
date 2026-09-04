import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 包装 Provider 原文。
///
/// 这个函数刻意保持**内容盲**：只冻结 [json] 并携带 adapter 已经算好的
/// [capturedAt]，绝不扫描 `timestamp` / `createdAt` 等键。相同键名可能只是工具
/// 参数里的业务字段；只有知道具体 Provider envelope 形状的 mapper 才能决定它
/// 是否代表报文时间（G1/G2）。
AgentProviderRawPayload wrapAgentProviderPayload(
  Map<String, Object?> json, {
  DateTime? capturedAt,
}) {
  return AgentProviderRawPayload.wrap(json, capturedAt: capturedAt);
}

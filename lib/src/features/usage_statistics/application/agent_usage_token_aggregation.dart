import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';

/// 汇总多条中立用量记录中的 Token 字段。
///
/// 缺失字段按零处理；即使记录为空也返回各字段均为零的明细，以保持今日用量面板
/// 对“已支持但暂无记录”的既有展示语义。
UsageTokenBreakdown sumAgentUsageTokens(Iterable<AgentUsageRecord> records) {
  var input = 0;
  var cached = 0;
  var output = 0;
  var reasoning = 0;
  var total = 0;
  for (final record in records) {
    input += record.tokens.inputTokens ?? 0;
    cached += record.tokens.cachedInputTokens ?? 0;
    output += record.tokens.outputTokens ?? 0;
    reasoning += record.tokens.reasoningTokens ?? 0;
    total += record.tokens.effectiveTotal ?? 0;
  }
  return UsageTokenBreakdown(
    inputTokens: input,
    cachedInputTokens: cached,
    outputTokens: output,
    reasoningTokens: reasoning,
    totalTokens: total,
  );
}

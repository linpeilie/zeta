/// Zeta 自有 Agent 界面文案目录。
///
/// 只接收中立 enum/facts 与必要原文参数，返回当前进程语言的字符串。
/// 不暴露 ARB key、Flutter `Locale`、`BuildContext` 或 Provider raw payload。
abstract interface class AgentUiTextCatalog {
  /// 共享时间线在 reasoning 流尚未给出标题时使用的思考卡 fallback。
  String get thinkingToolTitle;
}

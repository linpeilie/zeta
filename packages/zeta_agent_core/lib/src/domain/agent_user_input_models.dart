/// 用户发给 Agent 的一条输入项（对应协议 `UserInput`）。
///
/// 覆盖 `text`、`localImage`、`mention`、`skill`；远程 `image` 按后续阶段扩展。
sealed class AgentUserInput {
  const AgentUserInput();

  /// 纯文本输入。
  const factory AgentUserInput.text(
    String text, {
    List<AgentTextElement> textElements,
  }) = AgentTextUserInput;

  /// 本地图片路径（粘贴落盘或文件选择器选中的绝对路径）。
  const factory AgentUserInput.localImage({
    required String path,
    String? detail,
  }) = AgentLocalImageUserInput;

  /// 文件/路径提及（协议 `mention`）。
  const factory AgentUserInput.mention({
    required String name,
    required String path,
  }) = AgentMentionUserInput;

  /// Skill 引用（协议 `skill`）；文本中应同时包含 `$name` marker。
  const factory AgentUserInput.skill({
    required String name,
    required String path,
  }) = AgentSkillUserInput;
}

/// 文本内嵌特殊 span（协议 `TextElement`）。
class AgentTextElement {
  const AgentTextElement({
    required this.start,
    required this.end,
    this.placeholder,
  });

  /// UTF-8 字节起始偏移。
  final int start;

  /// UTF-8 字节结束偏移（不含）。
  final int end;

  /// 可选占位符（如 mention 显示名）。
  final String? placeholder;
}

/// 文本输入项。
final class AgentTextUserInput extends AgentUserInput {
  const AgentTextUserInput(
    this.text, {
    this.textElements = const <AgentTextElement>[],
  });

  /// 发送给模型的文本内容。
  final String text;

  /// 文本内嵌特殊元素元数据。
  final List<AgentTextElement> textElements;
}

/// 本地图片输入项。
final class AgentLocalImageUserInput extends AgentUserInput {
  const AgentLocalImageUserInput({required this.path, this.detail});

  /// 图片文件的本地绝对路径。
  final String path;

  /// 可选的图片细节档位（协议 `ImageDetail`：auto/low/high/original）。
  final String? detail;
}

/// 文件提及输入项。
final class AgentMentionUserInput extends AgentUserInput {
  const AgentMentionUserInput({required this.name, required this.path});

  /// 展示名（通常为文件名）。
  final String name;

  /// 文件绝对或工作区相对路径。
  final String path;
}

/// Skill 输入项。
final class AgentSkillUserInput extends AgentUserInput {
  const AgentSkillUserInput({required this.name, required this.path});

  /// Skill 稳定标识。
  final String name;

  /// Skill 定义文件的绝对路径。
  final String path;
}

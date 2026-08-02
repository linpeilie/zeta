import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zeta/src/features/agent/domain/agent_skill_models.dart';
import 'package:zeta/src/ui/core/ide_chip.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';

/// Composer 内 Skill token 使用的对象替换符（单字符占位）。
const String kComposerSkillSentinel = '\uFFFC';

/// Composer 文档序列化结果。
@immutable
final class ComposerSerializedDocument {
  const ComposerSerializedDocument({required this.text, required this.skills});

  /// 发给协议的文本（skill 已展开为 `$name`；Codex 侧常呈现为 `[$name](path)`）。
  final String text;

  /// 按出现顺序、按 path 去重后的 skill 引用。
  final List<AgentSkillRef> skills;
}

/// 维护 text + 原子 Skill token 的 Composer 控制器。
///
/// 底层文本用 [kComposerSkillSentinel] 占位；[buildTextSpan] 渲染为 chip。
/// 退格/删除碰到 sentinel 时整块移除对应 skill。
final class ComposerDocumentController extends TextEditingController {
  final List<AgentSkillRef> _skills = <AgentSkillRef>[];
  bool _applyingInternalMutation = false;

  /// 当前文档中的 skill（与 sentinel 顺序一致）。
  List<AgentSkillRef> get skills => List<AgentSkillRef>.unmodifiable(_skills);

  /// 是否包含可发送内容（文本或 skill）。
  bool get hasContent {
    final plain = text.replaceAll(kComposerSkillSentinel, '').trim();
    return plain.isNotEmpty || _skills.isNotEmpty;
  }

  /// 光标前未完成的 `$query`（不含 `$`）；无触发时返回 null。
  String? get activeSkillQuery {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final text = value.text;
    final cursor = selection.start.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final match = RegExp(r'(?:^|[\s])\$([^\s$]*)$').firstMatch(before);
    if (match == null) {
      return null;
    }
    return match.group(1);
  }

  /// 光标前未完成的 `/query`（不含 `/`）；无触发时返回 null。
  ///
  /// 仅当 `/` 位于行首/文档开头，或前面为空白（空格/换行/制表）时生效，
  /// 避免把路径中间的 `/` 当成斜线命令。
  String? get activeSlashQuery {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final text = value.text;
    final cursor = selection.start.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final match = RegExp(r'(?:^|[\s])/([^\s/]*)$').firstMatch(before);
    if (match == null) {
      return null;
    }
    return match.group(1);
  }

  /// 移除光标前的 `/query` 触发片段；无触发时不改动。
  void consumeActiveSlashQuery() {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return;
    }
    final text = value.text;
    final cursor = selection.start.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final match = RegExp(r'(?:^|[\s])/([^\s/]*)$').firstMatch(before);
    if (match == null) {
      return;
    }
    final slashIndex = before.lastIndexOf('/');
    if (slashIndex < 0) {
      return;
    }
    final nextBefore = before.substring(0, slashIndex);
    _setValueInternal(
      TextEditingValue(
        text: '$nextBefore$after',
        selection: TextSelection.collapsed(offset: nextBefore.length),
        composing: TextRange.empty,
      ),
    );
  }

  /// 在光标处插入 skill；若正在输入 `$query` 或 `/query` 则替换该片段。
  void insertSkill(AgentSkillMetadata skill, {String? defaultPrompt}) {
    final ref = AgentSkillRef(
      name: skill.name,
      path: skill.path,
      displayName: skill.displayName,
    );
    final selection = value.selection;
    final text = value.text;
    final cursor = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final start = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : cursor;
    final left = start < cursor ? start : cursor;
    final right = start < cursor ? cursor : start;

    final before = text.substring(0, left);
    final after = text.substring(right);
    final skillQueryMatch = RegExp(
      r'(?:^|[\s])\$([^\s$]*)$',
    ).firstMatch(before);
    final slashQueryMatch = RegExp(r'(?:^|[\s])/([^\s/]*)$').firstMatch(before);
    late final String nextBefore;
    if (skillQueryMatch != null) {
      final dollarIndex = before.lastIndexOf(r'$');
      nextBefore = before.substring(0, dollarIndex);
    } else if (slashQueryMatch != null) {
      final slashIndex = before.lastIndexOf('/');
      nextBefore = before.substring(0, slashIndex);
    } else {
      nextBefore = before;
    }

    final prompt = defaultPrompt ?? skill.defaultPrompt?.trim();
    final trailing = (prompt != null && prompt.isNotEmpty)
        ? ' $prompt'
        : (after.isEmpty || after.startsWith(' ') || after.startsWith('\n')
              ? ''
              : ' ');

    // 计算插入位置对应的 skill 下标。
    final skillIndex = kComposerSkillSentinel.allMatches(nextBefore).length;
    _skills.insert(skillIndex.clamp(0, _skills.length), ref);

    final nextText = '$nextBefore$kComposerSkillSentinel$trailing$after';
    final nextCursor = nextBefore.length + 1 + trailing.length;
    _setValueInternal(
      TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextCursor),
        composing: TextRange.empty,
      ),
    );
  }

  /// 序列化为协议文本 + skill 列表。
  ComposerSerializedDocument serialize() {
    final buffer = StringBuffer();
    var skillIndex = 0;
    final seenPaths = <String>{};
    final orderedSkills = <AgentSkillRef>[];
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == kComposerSkillSentinel) {
        if (skillIndex < _skills.length) {
          final skill = _skills[skillIndex];
          final needsLeadingSpace =
              buffer.isNotEmpty && !_endsWithWhitespace(buffer.toString());
          if (needsLeadingSpace) {
            buffer.write(' ');
          }
          buffer.write(skill.marker);
          if (seenPaths.add(skill.path)) {
            orderedSkills.add(skill);
          }
          skillIndex += 1;
        }
      } else {
        buffer.write(char);
      }
    }
    return ComposerSerializedDocument(
      text: buffer.toString(),
      skills: List<AgentSkillRef>.unmodifiable(orderedSkills),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    if (_applyingInternalMutation) {
      super.value = newValue;
      return;
    }
    final normalized = _normalizeEdit(value, newValue);
    super.value = normalized;
  }

  @override
  void clear() {
    _skills.clear();
    _setValueInternal(TextEditingValue.empty);
  }

  void _setValueInternal(TextEditingValue next) {
    _applyingInternalMutation = true;
    try {
      value = next;
    } finally {
      _applyingInternalMutation = false;
    }
  }

  TextEditingValue _normalizeEdit(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    if (oldText == newText) {
      return newValue;
    }

    // 统计旧/新 sentinel，同步 skill 列表。
    final oldCount = kComposerSkillSentinel.allMatches(oldText).length;
    final newCount = kComposerSkillSentinel.allMatches(newText).length;

    if (newCount < oldCount) {
      // 找出被删除的 sentinel 下标并移除 skill。
      final removedIndexes = _removedSentinelIndexes(oldText, newText);
      for (final index in removedIndexes.reversed) {
        if (index >= 0 && index < _skills.length) {
          _skills.removeAt(index);
        }
      }
    } else if (newCount > oldCount) {
      // 禁止用户直接键入 sentinel；剥掉多出来的占位符。
      final sanitized = newText.replaceAll(kComposerSkillSentinel, '');
      // 恢复旧 sentinel。
      final rebuilt = _rebuildKeepingSkills(sanitized, oldText);
      return TextEditingValue(
        text: rebuilt,
        selection: TextSelection.collapsed(
          offset: rebuilt.length.clamp(0, rebuilt.length),
        ),
        composing: TextRange.empty,
      );
    }

    // 若删除区间紧贴 sentinel，确保整块删掉（退格整删）。
    if (newText.length < oldText.length && oldValue.selection.isCollapsed) {
      final cursor = oldValue.selection.baseOffset.clamp(0, oldText.length);
      if (cursor > 0 &&
          oldText[cursor - 1] == kComposerSkillSentinel &&
          newText.length == oldText.length - 1) {
        // 已按单字符删除 sentinel，skill 列表已在上面同步。
        return newValue;
      }
      // 若用户从 sentinel 右侧退格，Flutter 会删 sentinel 本身；已处理。
      // 若从 sentinel 左侧 Delete：同理。
    }

    // 防止在 sentinel「内部」插入：选区若覆盖 sentinel 的一部分已不可能（单字符）。
    // 若替换范围包含 sentinel，对应 skill 已按计数差移除。
    while (_skills.length > newCount) {
      _skills.removeLast();
    }
    return newValue;
  }

  List<int> _removedSentinelIndexes(String oldText, String newText) {
    final oldPositions = <int>[];
    for (var i = 0; i < oldText.length; i++) {
      if (oldText[i] == kComposerSkillSentinel) {
        oldPositions.add(i);
      }
    }
    final newPositions = <int>[];
    for (var i = 0; i < newText.length; i++) {
      if (newText[i] == kComposerSkillSentinel) {
        newPositions.add(i);
      }
    }
    // 简单 LCS：从两侧对齐，中间缺失即删除。
    final removed = <int>[];
    var ni = 0;
    for (var oi = 0; oi < oldPositions.length; oi++) {
      if (ni < newPositions.length) {
        // 仍有对应 sentinel，视为保留（位置可变）。
        ni += 1;
      } else {
        removed.add(oi);
      }
    }
    // 若数量差小于 removed，用前缀差补充。
    final expectedRemovals = oldPositions.length - newPositions.length;
    if (removed.length != expectedRemovals && expectedRemovals > 0) {
      removed
        ..clear()
        ..addAll(
          List<int>.generate(
            expectedRemovals,
            (i) => oldPositions.length - 1 - i,
          ).reversed,
        );
    }
    return removed;
  }

  String _rebuildKeepingSkills(String sanitizedPlain, String oldText) {
    // 将旧 sentinel 按原相对位置插回（保守：追加到末尾前的结构）。
    // 实际路径：用户粘贴含 FFFC 时剥掉即可，保留旧文本结构。
    if (_skills.isEmpty) {
      return sanitizedPlain;
    }
    // 回退到旧文本，避免破坏 token。
    return oldText;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final baseStyle =
        style ?? textStyles.bodyMedium.copyWith(color: colors.textPrimary);
    final text = value.text;
    if (!text.contains(kComposerSkillSentinel)) {
      return super.buildTextSpan(
        context: context,
        style: baseStyle,
        withComposing: withComposing,
      );
    }

    final children = <InlineSpan>[];
    var skillIndex = 0;
    var chunkStart = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] != kComposerSkillSentinel) {
        continue;
      }
      if (i > chunkStart) {
        children.add(
          TextSpan(text: text.substring(chunkStart, i), style: baseStyle),
        );
      }
      final skill = skillIndex < _skills.length ? _skills[skillIndex] : null;
      skillIndex += 1;
      // Chip 展示 displayName；tooltip 保留 Codex `[$name](path)` 形态。
      final label = skill?.label ?? r'$skill';
      final tooltip = skill?.markdownLink ?? label;
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space2),
            child: Tooltip(
              message: tooltip,
              child: IdeChip(
                label: label,
                variant: IdeChipVariant.secondary,
                semanticLabel: 'Skill $label',
              ),
            ),
          ),
        ),
      );
      chunkStart = i + 1;
    }
    if (chunkStart < text.length) {
      children.add(
        TextSpan(text: text.substring(chunkStart), style: baseStyle),
      );
    }
    return TextSpan(style: baseStyle, children: children);
  }

  static bool _endsWithWhitespace(String value) {
    if (value.isEmpty) {
      return true;
    }
    final code = value.codeUnitAt(value.length - 1);
    return code == 0x20 || code == 0x0a || code == 0x09;
  }
}

/// 确保删除/退格时整颗 skill token 被移除。
final class ComposerSkillTokenFormatter extends TextInputFormatter {
  ComposerSkillTokenFormatter(this.controller);

  final ComposerDocumentController controller;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length >= oldValue.text.length) {
      return newValue;
    }
    if (!oldValue.selection.isValid || !oldValue.selection.isCollapsed) {
      return newValue;
    }
    final cursor = oldValue.selection.baseOffset;
    // Backspace：光标前是 sentinel → 已删；若光标前是普通字符但新文本跳过了 sentinel，扩展删除。
    if (cursor > 0 &&
        cursor <= oldValue.text.length &&
        oldValue.text[cursor - 1] == kComposerSkillSentinel) {
      return newValue;
    }
    // Delete：光标后是 sentinel。
    if (cursor < oldValue.text.length &&
        oldValue.text[cursor] == kComposerSkillSentinel &&
        newValue.text.length == oldValue.text.length - 1) {
      return newValue;
    }
    return newValue;
  }
}

import 'dart:convert';

/// Provider 原文：**只能整体展示，不能取值**。
///
/// 上下文面板要给用户看原始报文，这是产品能力；但"能看"不等于"能读"。早期这些
/// 字段是裸 `Map<String, Object?>`，于是内核与 presentation 陆续开始
/// `raw['_progressAppend']`、`rawInput['command']`、`raw['inputModalities']`——
/// 协议形状顺着 raw 渗进了中立层与 UI，Provider 协议一升级就四处开裂。
///
/// 这个类型把那条规则交给编译器：
///
/// - 没有 `operator []`、没有 `keys`、没有 `toMap()` —— `raw['x']` 直接编译失败；
/// - 唯一出口是 [toPrettyJson]，只服务于"展示原始报文"这一个场景；
/// - [toString] **不吐内容**，误拼进日志或异常消息也不会泄露 payload（G7）；
/// - 构造只允许发生在 `zeta_agent_providers`（守卫强制）——原文只能从适配层进来。
///
/// 需要从原文里取值时，正确做法是让 adapter 解析成 typed 字段传出来，
/// 例如 `AgentToolCall.inputDetail` / `AgentToolCall.appendsProgress`。
final class AgentProviderRawPayload {
  /// 无原文。
  const AgentProviderRawPayload.empty()
    : _json = const <String, Object?>{},
      capturedAt = null;

  /// 由适配层包装 wire payload。
  ///
  /// [capturedAt] 是这份报文的时间（协议自带的时间戳，或适配层的接收时刻），
  /// 面板据此展示时间——避免 UI 再去 payload 里翻 `timestamp` / `created_at`。
  const AgentProviderRawPayload.wrap(
    Map<String, Object?> json, {
    this.capturedAt,
  }) : _json = json;

  final Map<String, Object?> _json;

  /// 报文时间；协议未提供时为 null。
  final DateTime? capturedAt;

  /// 是否没有原文。
  bool get isEmpty => _json.isEmpty;

  /// 是否有原文。
  bool get isNotEmpty => _json.isNotEmpty;

  /// 顶层键数量。仅用于"有没有内容"的判断与诊断计数，不暴露键名。
  int get entryCount => _json.length;

  /// 渲染成缩进 JSON 文本。**唯一的内容出口**。
  String toPrettyJson() {
    if (_json.isEmpty) {
      return '';
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(_json);
    } on JsonUnsupportedObjectError {
      // 协议里偶有不可序列化对象；退回逐键 toString，仍然只用于展示。
      return _json.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }
  }

  /// 合并两份原文（后者覆盖同名键）。
  ///
  /// 这是**内容盲**操作：合并只发生在同一 identity 的事件被 coalescing 合并时，
  /// 不需要、也不允许查看具体键值。
  AgentProviderRawPayload mergedWith(AgentProviderRawPayload other) {
    if (other.isEmpty) {
      return this;
    }
    if (isEmpty) {
      return other;
    }
    return AgentProviderRawPayload.wrap(<String, Object?>{
      ..._json,
      ...other._json,
    }, capturedAt: other.capturedAt ?? capturedAt);
  }

  /// 内容相等。
  ///
  /// 比较是**结构化深比较**，不经过字符串化：既避免大 payload 的编码开销，
  /// 也不因键序不同而误判。
  @override
  bool operator ==(Object other) {
    return other is AgentProviderRawPayload &&
        other.capturedAt == capturedAt &&
        _deepEquals(_json, other._json);
  }

  @override
  int get hashCode => Object.hash(capturedAt, _json.length);

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) {
        return false;
      }
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i += 1) {
        if (!_deepEquals(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  /// **不含内容**：防止误插值把整份 payload 写进日志。
  @override
  String toString() => 'AgentProviderRawPayload($entryCount entries)';
}

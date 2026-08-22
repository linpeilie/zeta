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
  const AgentProviderRawPayload._(this._json, this.capturedAt);

  /// 无原文。
  const AgentProviderRawPayload.empty()
    : _json = const <String, Object?>{},
      capturedAt = null;

  /// 由适配层包装 wire payload。
  ///
  /// [capturedAt] 是这份报文的时间（协议自带的时间戳，或适配层的接收时刻），
  /// 面板据此展示时间——避免 UI 再去 payload 里翻 `timestamp` / `created_at`；
  /// 统一转成本地时区，否则同一条报文在不同路径会显示成不同时间。
  ///
  /// 传入的 Map **会被递归冻结**（连同嵌套 Map / List）。这是值类型该有的样子：
  /// payload 会进 Timeline 与 UI snapshot 并参与相等性判定，适配层若还持有原
  /// Map 的引用并继续改它，已经展示出去的内容就会无声漂移。
  factory AgentProviderRawPayload.wrap(
    Map<String, Object?> json, {
    DateTime? capturedAt,
  }) {
    return AgentProviderRawPayload._(_freezeMap(json), capturedAt?.toLocal());
  }

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

  /// 补上报文时间：已有 [capturedAt] 时原样返回。
  ///
  /// 适配层有时先包装 payload、后才知道记录级时间（例如历史文件按行解析：
  /// 时间在记录外层，内容在 `update` 里）。这是**内容盲**操作，不看任何键值。
  AgentProviderRawPayload capturedAtOr(DateTime? fallback) {
    if (capturedAt != null || fallback == null) {
      return this;
    }
    return AgentProviderRawPayload._(_json, fallback.toLocal());
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
    // 两边都已冻结，合并结果只需冻结顶层。
    return AgentProviderRawPayload._(
      Map<String, Object?>.unmodifiable(<String, Object?>{
        ..._json,
        ...other._json,
      }),
      other.capturedAt ?? capturedAt,
    );
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

  /// 递归冻结：Map / List 换成不可修改视图的**副本**，标量原样。
  ///
  /// 复制一次的代价与产生这份 payload 的 `jsonDecode` 同量级；换来的是"拿到手
  /// 之后内容不会再变"这个类型不变量。
  static Map<String, Object?> _freezeMap(Map<String, Object?> json) {
    if (json.isEmpty) {
      return const <String, Object?>{};
    }
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in json.entries) entry.key: _freezeValue(entry.value),
    });
  }

  static Object? _freezeValue(Object? value) {
    if (value is Map) {
      return Map<Object?, Object?>.unmodifiable(<Object?, Object?>{
        for (final entry in value.entries) entry.key: _freezeValue(entry.value),
      });
    }
    if (value is List) {
      return List<Object?>.unmodifiable(<Object?>[
        for (final item in value) _freezeValue(item),
      ]);
    }
    return value;
  }

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

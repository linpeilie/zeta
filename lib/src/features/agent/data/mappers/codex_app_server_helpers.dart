part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 宽容读取 map。
Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        result[entry.key as String] = entry.value;
      }
    }
    return result;
  }
  return const <String, Object?>{};
}

/// 非空字符串读取。
String? _string(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

bool _isErrorNotification(String method) {
  return switch (method) {
    'error' || 'warning' || 'guardianWarning' || 'configWarning' => true,
    _ => false,
  };
}

/// 本地 MCP 软件未启动时，Codex/mrmcp 会持续向 stderr 写 transport worker
/// 断开日志；这类日志不影响 thread 本身，避免刷进用户可见的 Agent 时间线。
bool _isIgnorableMcpTransportStderr(String line) {
  if (!line.contains('mrmcp::transport::worker')) {
    return false;
  }
  if (!line.contains('127.0.0.1')) {
    return false;
  }
  return line.contains('Transport channel closed') ||
      line.contains('http/request failed') ||
      line.contains('/stream') ||
      line.contains('/mcp');
}

/// 从 Codex item 中挑选最适合 UI 展示的标题。
String _toolTitle(Map<String, Object?> item) {
  return _string(item['title']) ??
      _string(item['name']) ??
      _string(item['command']) ??
      _string(item['type']) ??
      'Tool call';
}

/// 根据进度通知方法名生成标题。
String _progressTitle(String method) {
  if (method.contains('fileChange')) {
    return 'File change';
  }
  if (method.contains('command')) {
    return 'Command output';
  }
  return 'Tool progress';
}

/// 将 Codex 工具类型映射到统一工具分类。
AgentToolKind _toolKind(String? value) {
  return switch (value) {
    'read' => AgentToolKind.read,
    'edit' => AgentToolKind.edit,
    'delete' => AgentToolKind.delete,
    'move' => AgentToolKind.move,
    'search' => AgentToolKind.search,
    'execute' ||
    'command_execution' ||
    'commandExecution' => AgentToolKind.execute,
    'think' || 'reasoning' => AgentToolKind.think,
    'fetch' => AgentToolKind.fetch,
    _ => AgentToolKind.other,
  };
}

/// 从 item 中提取文件位置。
List<String> _locations(Map<String, Object?> item) {
  final locations = item['locations'];
  if (locations is! List<Object?>) {
    return const <String>[];
  }
  return locations.map((location) {
    if (location is String) {
      return location;
    }
    final map = _map(location);
    return _string(map['path']) ?? '$location';
  }).toList();
}

/// 将用户输入数组转成历史消息文本。
String? _userInputText(Object? value) {
  if (value is! List<Object?>) {
    return _string(value);
  }

  final parts = <String>[];
  for (final itemValue in value) {
    final item = _map(itemValue);
    final type = _string(item['type']);
    switch (type) {
      case 'text':
        final text = _string(item['text']);
        if (text != null) {
          parts.add(text);
        }
      case 'image':
        final url = _string(item['url']);
        parts.add(url == null ? '[Image]' : '[Image: $url]');
      case 'localImage':
        final path = _string(item['path']);
        parts.add(path == null ? '[Image]' : '[Image: $path]');
      case 'skill':
      case 'mention':
        final name = _string(item['name']) ?? _string(item['id']);
        if (name != null) {
          parts.add('@$name');
        }
      default:
        final text = _string(item['text']) ?? _string(item['content']);
        if (text != null) {
          parts.add(text);
        }
    }
  }

  return parts.isEmpty ? null : parts.join('\n');
}

/// 宽容拼接字符串数组。
String? _joinedStrings(Object? value) {
  if (value is List<String>) {
    final parts = value.where((item) => item.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join('\n');
  }
  if (value is List<Object?>) {
    final parts = value
        .map(_string)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join('\n');
  }
  return _string(value);
}

/// 从工具返回内容里挑选一段适合卡片预览的文本。
String? _joinedContentItems(Object? value) {
  final map = _map(value);
  final content = map.isEmpty ? value : map['content'];
  if (content is List<Object?>) {
    final parts = <String>[];
    for (final itemValue in content) {
      if (itemValue is String) {
        parts.add(itemValue);
        continue;
      }
      final item = _map(itemValue);
      final text = _string(item['text']) ?? _string(item['content']);
      if (text != null) {
        parts.add(text);
      }
    }
    if (parts.isNotEmpty) {
      return parts.join('\n');
    }
  }
  return _string(content) ?? _string(map['text']);
}

/// 根据 Codex 历史 item 状态映射工具状态。
AgentToolStatus _historyToolStatus(String? status) {
  return switch (status) {
    'inProgress' || 'running' => AgentToolStatus.inProgress,
    'failed' || 'error' => AgentToolStatus.failed,
    'declined' || 'cancelled' || 'canceled' => AgentToolStatus.cancelled,
    'pending' => AgentToolStatus.pending,
    _ => AgentToolStatus.completed,
  };
}

/// 将单个路径字符串包装为列表，用于工具卡片的位置展示。
List<String> _singleLocation(String? location) {
  return location == null ? const <String>[] : <String>[location];
}

/// 从 Codex item 的 changes 中提取受影响的文件路径列表。
List<String> _fileChangeLocations(Object? value) {
  if (value is! List<Object?>) {
    return const <String>[];
  }
  return value
      .map((item) {
        if (item is String) {
          return item;
        }
        return _string(_map(item)['path']);
      })
      .whereType<String>()
      .toList();
}

/// 拼接工具调用的路径式标题，如 "MCP: serverName: toolName" 或 "namespace: toolName"。
String _toolPathTitle({String? prefix, String? first, String? second}) {
  final parts = <String>[?prefix, ?first, ?second];
  return parts.isEmpty ? 'Tool call' : parts.join(': ');
}

/// 去除字符串首尾空白，空字符串或 null 返回 null。
String? _trimmedText(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

/// 将任意对象转为适合 UI 预览的短文本。
String? _objectPreview(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map && value.isEmpty) {
    return null;
  }
  if (value is List && value.isEmpty) {
    return null;
  }
  if (value is String) {
    return _string(value);
  }
  return '$value';
}

/// 尝试将字符串值解析为 JSON，失败则返回原始字符串。
Object? _decodedJsonValue(Object? value) {
  if (value is! String) {
    return value;
  }
  try {
    return jsonDecode(value);
  } catch (_) {
    return value;
  }
}

/// 将值尝试作为 JSON 解析后再转为 map，常用于处理双重编码的参数。
Map<String, Object?> _decodedObjectMap(Object? value) {
  return _map(_decodedJsonValue(value));
}

String? _responseCallId(Map<String, Object?> payload) {
  return _string(payload['call_id']);
}

String? _jsonlUserMessageText(Map<String, Object?> payload) {
  final parts = <String>[];
  final message = _trimmedText(_string(payload['message']));
  if (message != null) {
    parts.add(message);
  }

  final textElements = payload['text_elements'];
  if (textElements is List<Object?>) {
    for (final itemValue in textElements) {
      final item = _map(itemValue);
      final text = _trimmedText(
        _string(item['text']) ?? _string(item['content']),
      );
      if (text != null && !parts.contains(text)) {
        parts.add(text);
      }
    }
  }

  final images = payload['images'];
  if (images is List<Object?> && images.isNotEmpty) {
    parts.add('[Images: ${images.length}]');
  }

  final localImages = payload['local_images'];
  if (localImages is List<Object?> && localImages.isNotEmpty) {
    parts.add('[Local images: ${localImages.length}]');
  }

  return parts.isEmpty ? null : parts.join('\n');
}

/// 判断工具调用名是否为权限类（用户输入或权限申请）。
bool _isPermissionHistoryToolName(String? name) {
  return switch (name) {
    'request_user_input' || 'request_permissions' => true,
    _ => false,
  };
}

/// 根据 jsonl 历史中的工具名称映射到统一工具分类。
AgentToolKind _jsonlToolKind(String? name) {
  return switch (name) {
    'exec_command' => AgentToolKind.execute,
    'apply_patch' => AgentToolKind.edit,
    'read_mcp_resource' ||
    'read_package_uris' ||
    'open' ||
    'find' => AgentToolKind.read,
    'rip_grep_packages' ||
    'tool_search_tool' ||
    'search_query' ||
    'image_query' => AgentToolKind.search,
    'web_search' || 'web.run' => AgentToolKind.search,
    'request_user_input' => AgentToolKind.other,
    _ => _toolKind(name),
  };
}

/// 根据 jsonl 历史中的工具名称和参数生成 UI 友好的工具卡片标题。
String _jsonlToolTitle({
  required String? name,
  Map<String, Object?> arguments = const <String, Object?>{},
  String? stringInput,
}) {
  if (name == 'exec_command') {
    return _trimmedText(_string(arguments['cmd'])) ?? 'Run command';
  }
  if (name == 'shell_command') {
    return _trimmedText(_string(arguments['command'])) ?? 'Run shell command';
  }
  if (name == 'apply_patch') {
    return 'Apply patch';
  }
  if (name == null || name.isEmpty) {
    return 'Tool call';
  }
  return _humanizeIdentifier(name);
}

/// 根据 jsonl 历史中的工具名称和参数生成工具卡片的内容预览。
String? _jsonlToolInvocationContent({
  required String? name,
  Map<String, Object?> arguments = const <String, Object?>{},
  String? stringInput,
}) {
  if (name == 'exec_command') {
    return _trimmedText(_string(arguments['cmd']));
  }
  if (name == 'apply_patch') {
    final paths = _patchPathsFromText(stringInput);
    return paths.isEmpty ? 'Patch prepared' : paths.join('\n');
  }
  return _trimmedText(_objectPreview(arguments)) ?? _trimmedText(stringInput);
}

/// 从工具调用参数中构建用于保存的 rawInput map。
Map<String, Object?> _jsonlRawInputMap({
  required Map<String, Object?> arguments,
  String? stringInput,
}) {
  if (arguments.isNotEmpty) {
    return arguments;
  }
  if (stringInput == null || stringInput.isEmpty) {
    return const <String, Object?>{};
  }
  return <String, Object?>{'input': stringInput};
}

/// 从 jsonl 历史工具调用参数中提取相关的文件/目录路径列表。
List<String> _jsonlToolLocations({
  required String? name,
  Map<String, Object?> arguments = const <String, Object?>{},
  String? stringInput,
}) {
  final locations = <String>{};

  void addString(Object? value) {
    final text = _string(value);
    if (text != null) {
      locations.add(text);
    }
  }

  addString(arguments['path']);
  addString(arguments['cwd']);
  addString(arguments['workdir']);
  addString(arguments['uri']);

  final uris = arguments['uris'];
  if (uris is List<Object?>) {
    for (final uri in uris) {
      addString(uri);
    }
  }

  if (name == 'apply_patch') {
    locations.addAll(_patchPathsFromText(stringInput));
  }

  return locations.toList();
}

String? _jsonlToolOutputPreview(String? output) {
  final trimmed = _trimmedText(output);
  if (trimmed == null) {
    return null;
  }

  final marker = '\nOutput:\n';
  final markerIndex = trimmed.indexOf(marker);
  if (markerIndex != -1) {
    return _trimmedText(trimmed.substring(markerIndex + marker.length)) ??
        trimmed;
  }

  return trimmed;
}

List<String> _patchPathsFromText(String? patchText) {
  if (patchText == null || patchText.isEmpty) {
    return const <String>[];
  }

  final paths = <String>{};
  final lineExp = RegExp(r'^\*\*\* (?:Add|Delete|Update) File: (.+)$');
  final moveExp = RegExp(r'^\*\*\* Move to: (.+)$');

  for (final line in const LineSplitter().convert(patchText)) {
    final match = lineExp.firstMatch(line);
    if (match != null) {
      paths.add(match.group(1)!);
      continue;
    }
    final moveMatch = moveExp.firstMatch(line);
    if (moveMatch != null) {
      paths.add(moveMatch.group(1)!);
    }
  }

  return paths.toList();
}

List<String> _patchApplyLocations(Object? value) {
  if (value is Map) {
    return value.keys
        .whereType<String>()
        .where((key) => key.isNotEmpty)
        .toList();
  }
  return _fileChangeLocations(value);
}

String? _patchApplySummary(
  List<String> locations, {
  String? stdout,
  String? stderr,
}) {
  if (locations.isNotEmpty) {
    return locations.join('\n');
  }
  return _jsonlToolOutputPreview(stdout) ?? _jsonlToolOutputPreview(stderr);
}

Map<String, Object?> _mcpResultMap(Object? value) {
  final map = _map(value);
  if (map.containsKey('Ok')) {
    return _map(map['Ok']);
  }
  if (map.containsKey('Err')) {
    return _map(map['Err']);
  }
  return map;
}

/// 判断 MCP 工具调用结果是否包含错误。
bool _mcpResultIsError(Map<String, Object?> result) {
  return result['isError'] == true || _string(result['error']) != null;
}

String? _mcpResultPreview(Map<String, Object?> result) {
  final content = result['content'];
  if (content is List<Object?>) {
    final parts = <String>[];
    for (final itemValue in content) {
      final item = _map(itemValue);
      final text = _trimmedText(
        _string(item['text']) ?? _string(item['content']),
      );
      if (text != null) {
        parts.add(text);
      }
    }
    if (parts.isNotEmpty) {
      return parts.join('\n');
    }
  }
  return _trimmedText(_string(result['text'])) ??
      _trimmedText(_string(result['message']));
}

String? _toolSearchQueryPreview(Map<String, Object?> arguments) {
  final query = _trimmedText(_string(arguments['query']));
  final limit = arguments['limit'];
  if (query == null) {
    return null;
  }
  return limit == null ? query : '$query\nlimit=$limit';
}

String? _webSearchQueryPreview(Map<String, Object?> action) {
  final queries = action['queries'];
  if (queries is List<Object?>) {
    final values = queries
        .map(_string)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (values.isNotEmpty) {
      return values.join('\n');
    }
  }
  return _trimmedText(_string(action['query']));
}

String? _permissionEventDescription({
  required String? name,
  required Map<String, Object?> arguments,
  String? stringInput,
}) {
  if (name == 'request_user_input') {
    final questions = arguments['questions'];
    if (questions is List<Object?> && questions.isNotEmpty) {
      final first = _map(questions.first);
      return _trimmedText(_string(first['question'])) ??
          _trimmedText(_string(first['header']));
    }
  }
  return _trimmedText(_string(arguments['reason'])) ??
      _trimmedText(stringInput);
}

String? _permissionEventContent({
  required String? name,
  required Map<String, Object?> arguments,
  String? stringInput,
}) {
  if (name == 'request_user_input') {
    final questions = arguments['questions'];
    if (questions is! List<Object?> || questions.isEmpty) {
      return null;
    }
    final parts = <String>[];
    for (final questionValue in questions) {
      final question = _map(questionValue);
      final header = _trimmedText(_string(question['header']));
      final text = _trimmedText(_string(question['question']));
      final options = question['options'];
      final optionLabels = <String>[];
      if (options is List<Object?>) {
        for (final optionValue in options) {
          final option = _map(optionValue);
          final label = _trimmedText(_string(option['label']));
          if (label != null) {
            optionLabels.add(label);
          }
        }
      }

      final buffer = StringBuffer();
      if (header != null) {
        buffer.write(header);
      }
      if (text != null) {
        if (buffer.length > 0) {
          buffer.write(': ');
        }
        buffer.write(text);
      }
      if (optionLabels.isNotEmpty) {
        if (buffer.length > 0) {
          buffer.write('\n');
        }
        buffer.write(optionLabels.join(', '));
      }
      final line = _trimmedText(buffer.toString());
      if (line != null) {
        parts.add(line);
      }
    }
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  if (arguments.isNotEmpty) {
    return _trimmedText(_objectPreview(arguments));
  }
  return _trimmedText(stringInput);
}

/// 从 `request_user_input` 的 arguments 中解析结构化问答对。
List<AgentUserInputQaPair> _userInputQaPairs(Map<String, Object?> arguments) {
  final questions = arguments['questions'];
  if (questions is! List<Object?>) {
    return const <AgentUserInputQaPair>[];
  }
  final pairs = <AgentUserInputQaPair>[];
  for (final questionValue in questions) {
    final question = _map(questionValue);
    final id =
        _trimmedText(_string(question['id'])) ??
        _trimmedText(_string(question['header'])) ??
        '';
    final header = _trimmedText(_string(question['header']));
    final text = _trimmedText(_string(question['question'])) ?? header ?? id;
    final options = <String>[];
    final opts = question['options'];
    if (opts is List<Object?>) {
      for (final optionValue in opts) {
        final option = _map(optionValue);
        final label = _trimmedText(_string(option['label']));
        if (label != null) {
          options.add(label);
        }
      }
    }
    if (text.isEmpty) {
      continue;
    }
    pairs.add(
      AgentUserInputQaPair(
        questionId: id,
        question: text,
        header: header,
        options: List<String>.unmodifiable(options),
      ),
    );
  }
  return List<AgentUserInputQaPair>.unmodifiable(pairs);
}

/// 从 `request_user_input` 的 output 中提取“问题 id -> 已选答案标签”的映射。
Map<String, List<String>> _userInputAnswersByQuestionId(Object? output) {
  final decoded = _decodedObjectMap(output);
  final rawAnswers = _map(decoded['answers']);
  final source = rawAnswers.isNotEmpty ? rawAnswers : decoded;
  if (source.isEmpty) {
    return const <String, List<String>>{};
  }

  final answersByQuestionId = <String, List<String>>{};
  for (final entry in source.entries) {
    final questionId = _trimmedText(entry.key);
    if (questionId == null) {
      continue;
    }
    final answers = _userInputAnswerLabels(entry.value);
    if (answers.isEmpty) {
      continue;
    }
    answersByQuestionId[questionId] = List<String>.unmodifiable(answers);
  }
  return Map<String, List<String>>.unmodifiable(answersByQuestionId);
}

/// 宽容提取单个问题的答案标签。
List<String> _userInputAnswerLabels(Object? value) {
  if (value is List<Object?>) {
    return value
        .map(_string)
        .whereType<String>()
        .map(_trimmedText)
        .whereType<String>()
        .toList();
  }

  final map = _map(value);
  if (map.isNotEmpty) {
    final nestedAnswers = _userInputAnswerLabels(map['answers']);
    if (nestedAnswers.isNotEmpty) {
      return nestedAnswers;
    }

    final answer = _trimmedText(
      _string(map['answer']) ?? _string(map['label']) ?? _string(map['value']),
    );
    if (answer != null) {
      return <String>[answer];
    }
  }

  final text = _trimmedText(_string(value));
  return text == null ? const <String>[] : <String>[text];
}

/// 将已解析出的答案回填到对应问题上；未命中的问题保持原样。
List<AgentUserInputQaPair> _mergeUserInputQaPairsWithAnswers(
  List<AgentUserInputQaPair> qaPairs,
  Map<String, List<String>> answersByQuestionId,
) {
  return List<AgentUserInputQaPair>.unmodifiable(
    qaPairs.map((pair) {
      final answers = answersByQuestionId[pair.questionId];
      if (answers == null) {
        return pair;
      }
      return AgentUserInputQaPair(
        questionId: pair.questionId,
        question: pair.question,
        header: pair.header,
        options: pair.options,
        answers: answers,
      );
    }),
  );
}

/// 比较问答列表是否发生了可见变化，避免无意义替换条目。
bool _sameUserInputQaPairs(
  List<AgentUserInputQaPair> left,
  List<AgentUserInputQaPair> right,
) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final a = left[index];
    final b = right[index];
    if (a.questionId != b.questionId ||
        a.question != b.question ||
        a.header != b.header) {
      return false;
    }
    if (a.options.length != b.options.length ||
        a.answers.length != b.answers.length) {
      return false;
    }
    for (
      var optionIndex = 0;
      optionIndex < a.options.length;
      optionIndex += 1
    ) {
      if (a.options[optionIndex] != b.options[optionIndex]) {
        return false;
      }
    }
    for (
      var answerIndex = 0;
      answerIndex < a.answers.length;
      answerIndex += 1
    ) {
      if (a.answers[answerIndex] != b.answers[answerIndex]) {
        return false;
      }
    }
  }
  return true;
}

String? _specialEventContent(Map<String, Object?> payload) {
  final content = _trimmedText(
    _string(payload['content']) ??
        _string(payload['details']) ??
        _string(payload['query']),
  );
  if (content != null) {
    return content;
  }

  final action = _map(payload['action']);
  if (action.isNotEmpty) {
    return _webSearchQueryPreview(action) ??
        _trimmedText(_objectPreview(action));
  }

  return null;
}

/// 将标识符转换为 UI 友好的标题文字。
String _humanizeIdentifier(String value) {
  final cleaned = value.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  if (cleaned.isEmpty) {
    return value;
  }
  return cleaned
      .split(RegExp(r'\s+'))
      .map((part) {
        if (part.isEmpty) {
          return part;
        }
        return '${part[0].toUpperCase()}${part.substring(1)}';
      })
      .join(' ');
}

/// 将 provider 原始消息 phase 映射到领域枚举。
AgentMessagePhase? _messagePhase(String? phase) {
  return switch (phase) {
    'commentary' => AgentMessagePhase.commentary,
    'response' || 'answer' || 'final' => AgentMessagePhase.response,
    null => null,
    _ => AgentMessagePhase.other,
  };
}

String? _normalizedAgentItemType(String? type) {
  final trimmed = type?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
}

/// 将 provider 原始消息状态映射到领域枚举。
AgentMessageStatus? _messageStatus(String? status) {
  return switch (status) {
    'completed' || 'complete' || 'done' => AgentMessageStatus.completed,
    'streaming' ||
    'inProgress' ||
    'running' ||
    'started' => AgentMessageStatus.streaming,
    null => null,
    _ => AgentMessageStatus.other,
  };
}

/// 从 Codex item/通知中提取或计算消息耗时。
Duration? _messageDuration(
  Map<String, Object?> item, [
  Map<String, Object?> notification = const <String, Object?>{},
]) {
  final explicitMs =
      _numberToInt(item['durationMs']) ??
      _numberToInt(notification['durationMs']) ??
      _numberToInt(item['elapsedMs']) ??
      _numberToInt(notification['elapsedMs']);
  if (explicitMs != null && explicitMs >= 0) {
    return Duration(milliseconds: explicitMs);
  }

  final startedAtMs =
      _numberToInt(item['startedAtMs']) ??
      _numberToInt(notification['startedAtMs']);
  final completedAtMs =
      _numberToInt(item['completedAtMs']) ??
      _numberToInt(notification['completedAtMs']);
  if (startedAtMs == null || completedAtMs == null) {
    return null;
  }

  final elapsedMs = completedAtMs - startedAtMs;
  return elapsedMs < 0 ? null : Duration(milliseconds: elapsedMs);
}

/// 宽容地将值转为整数，支持 int 和 double 类型。
int? _numberToInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  return null;
}

/// 从多种格式中解析 DateTime：ISO 8601 字符串或毫秒时间戳。
DateTime? _dateTimeFromAny(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value);
  }
  final milliseconds = _numberToInt(value);
  if (milliseconds == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

/// 从毫秒值创建 Duration，负值或 null 返回 null。
Duration? _durationFromMilliseconds(Object? value) {
  final milliseconds = _numberToInt(value);
  if (milliseconds == null || milliseconds < 0) {
    return null;
  }
  return Duration(milliseconds: milliseconds);
}

/// 将 Codex 历史回合的状态字符串映射到领域枚举。
AgentHistoryTurnStatus _historyTurnStatus(
  String? status, [
  DateTime? completedAt,
]) {
  return switch (status) {
    'completed' || 'complete' || 'done' => AgentHistoryTurnStatus.completed,
    'running' ||
    'started' ||
    'active' ||
    'inProgress' => AgentHistoryTurnStatus.running,
    _ when completedAt != null => AgentHistoryTurnStatus.completed,
    _ => AgentHistoryTurnStatus.unknown,
  };
}

/// Codex thread 时间戳是 Unix 秒。
DateTime? _unixSecondsToDateTime(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
  }
  return null;
}

/// 宽容映射 Codex thread status。
AgentThreadRuntimeStatus _threadRuntimeStatus(Map<String, Object?> status) {
  return switch (_string(status['type'])) {
    'notLoaded' => AgentThreadRuntimeStatus.notLoaded,
    'idle' => AgentThreadRuntimeStatus.idle,
    'active' => AgentThreadRuntimeStatus.active,
    'systemError' => AgentThreadRuntimeStatus.systemError,
    _ => AgentThreadRuntimeStatus.unknown,
  };
}

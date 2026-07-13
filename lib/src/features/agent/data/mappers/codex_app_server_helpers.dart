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

/// 将 JSON-RPC `RequestId`（string | int）规范为与审批卡片 id 一致的字符串。
///
/// 审批映射用 `'${request.id}'` 生成 [AgentPermissionRequest.id]；
/// `serverRequest/resolved` 的 `requestId` 需用同一规则对齐。
String? _requestIdString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  if (value is int) {
    return '$value';
  }
  return null;
}

bool _isErrorNotification(String method) {
  return switch (method) {
    'error' || 'warning' || 'guardianWarning' || 'configWarning' => true,
    _ => false,
  };
}

/// 从 Codex item 中挑选最适合 UI 展示的标题。
String _toolTitle(Map<String, Object?> item) {
  final normalizedType = _normalizedAgentItemType(_string(item['type']));
  return switch (normalizedType) {
    'reasoning' => '思考',
    'websearch' => 'Web 搜索',
    'imageview' => '查看图片',
    'imagegeneration' => '生成图片',
    'collabagenttoolcall' => _toolPathTitle(
      prefix: '协作',
      first: _string(item['tool']),
    ),
    'mcptoolcall' => _toolPathTitle(
      prefix: 'MCP',
      first: _string(item['server']),
      second: _string(item['tool']),
    ),
    'dynamictoolcall' => _toolPathTitle(
      first: _string(item['namespace']),
      second: _string(item['tool']),
    ),
    'commandexecution' => _string(item['command']) ?? 'Command',
    'filechange' => 'File change',
    _ =>
      _string(item['title']) ??
          _string(item['name']) ??
          _string(item['command']) ??
          _string(item['query']) ??
          _string(item['type']) ??
          'Tool call',
  };
}

/// 从 reasoning item 提取可展示正文。
///
/// 协议里 `summary` / `content` 是 `{ type, text }` 对象数组，优先用摘要。
String? _reasoningItemContent(Map<String, Object?> item) {
  return _joinedContentItems(item['summary']) ??
      _joinedContentItems(item['content']) ??
      _string(item['text']);
}

/// 根据进度通知方法名生成标题。
String _progressTitle(String method) {
  if (method.contains('mcpToolCall')) {
    return 'MCP tool';
  }
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
  final normalized = _normalizedAgentItemType(value) ?? value;
  return switch (normalized) {
    'read' || 'imageview' => AgentToolKind.read,
    'edit' || 'filechange' => AgentToolKind.edit,
    'delete' => AgentToolKind.delete,
    'move' => AgentToolKind.move,
    'search' || 'websearch' => AgentToolKind.search,
    'execute' ||
    'command_execution' ||
    'commandexecution' => AgentToolKind.execute,
    'think' || 'reasoning' => AgentToolKind.think,
    'fetch' || 'imagegeneration' => AgentToolKind.fetch,
    'mcptoolcall' ||
    'dynamictoolcall' ||
    'collabagenttoolcall' => AgentToolKind.other,
    _ => AgentToolKind.other,
  };
}

/// 是否为应渲染为系统事件卡（而非工具卡）的 ThreadItem。
bool _isSystemThreadItemType(String? normalizedType) {
  return switch (normalizedType) {
    'enteredreviewmode' ||
    'exitedreviewmode' ||
    'contextcompaction' ||
    'hookprompt' ||
    'sleep' ||
    'subagentactivity' => true,
    _ => false,
  };
}

/// 是否为实时路径应忽略的 ThreadItem（用户消息由本地发送路径负责）。
bool _isIgnoredLiveThreadItemType(String? normalizedType) {
  return normalizedType == 'usermessage';
}

/// 从 ThreadItem 提取工具卡正文。
String? _toolContentFromThreadItem(Map<String, Object?> item) {
  final normalizedType = _normalizedAgentItemType(_string(item['type']));
  return switch (normalizedType) {
    'reasoning' => _reasoningItemContent(item),
    'commandexecution' =>
      _string(item['aggregatedOutput']) ?? _string(item['command']),
    'filechange' => _joinedStrings(_fileChangeLocations(item['changes'])),
    'mcptoolcall' =>
      _string(_map(item['error'])['message']) ??
          _joinedContentItems(item['result']) ??
          _objectPreview(item['arguments']),
    'dynamictoolcall' =>
      _joinedContentItems(item['contentItems']) ??
          _objectPreview(item['arguments']),
    'websearch' =>
      _webSearchActionPreview(item['action']) ?? _string(item['query']),
    'imageview' => _string(item['path']),
    'imagegeneration' =>
      _string(item['result']) ??
          _string(item['savedPath']) ??
          _string(item['revisedPrompt']),
    'collabagenttoolcall' =>
      _string(item['prompt']) ?? _joinedStrings(item['receiverThreadIds']),
    _ =>
      _string(item['text']) ??
          _string(item['command']) ??
          _string(item['query']) ??
          _string(item['path']),
  };
}

/// 从 ThreadItem 提取涉及路径。
List<String> _toolLocationsFromThreadItem(Map<String, Object?> item) {
  final normalizedType = _normalizedAgentItemType(_string(item['type']));
  return switch (normalizedType) {
    'commandexecution' => _singleLocation(_string(item['cwd'])),
    'filechange' => _fileChangeLocations(item['changes']),
    'imageview' => _singleLocation(_string(item['path'])),
    'imagegeneration' => _singleLocation(_string(item['savedPath'])),
    'collabagenttoolcall' => _singleLocation(_string(item['senderThreadId'])),
    _ => _locations(item),
  };
}

/// 将系统类 ThreadItem 映射为历史事件条目。
AgentHistoryEventEntry? _systemHistoryEventFromThreadItem(
  Map<String, Object?> item, {
  required String id,
}) {
  final normalizedType = _normalizedAgentItemType(_string(item['type']));
  return switch (normalizedType) {
    'enteredreviewmode' => AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.system,
      title: '进入评审模式',
      description: _string(item['review']),
      raw: item,
    ),
    'exitedreviewmode' => AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.system,
      title: '退出评审模式',
      description: _string(item['review']),
      raw: item,
    ),
    'contextcompaction' => AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.system,
      title: '上下文已压缩',
      description: '会话上下文已压缩以腾出窗口空间。',
      raw: item,
    ),
    'hookprompt' => AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.system,
      title: 'Hook 提示',
      content: _hookPromptFragmentsText(item['fragments']),
      raw: item,
    ),
    'sleep' => AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.system,
      title: '等待中',
      description: _sleepDurationLabel(item['durationMs']),
      raw: item,
    ),
    'subagentactivity' => AgentHistoryEventEntry(
      id: id,
      kind: AgentHistoryEventKind.system,
      title: '子代理活动',
      description: _subAgentActivityLabel(
        kind: _string(item['kind']),
        agentPath: _string(item['agentPath']),
      ),
      content: _string(item['agentThreadId']),
      raw: item,
    ),
    _ => null,
  };
}

String? _hookPromptFragmentsText(Object? value) {
  if (value is! List) {
    return null;
  }
  final parts = <String>[];
  for (final fragmentValue in value) {
    final fragment = _map(fragmentValue);
    final text = _string(fragment['text']);
    if (text != null) {
      parts.add(text);
    }
  }
  return parts.isEmpty ? null : parts.join('\n');
}

String? _sleepDurationLabel(Object? durationMs) {
  final duration = _durationFromMilliseconds(durationMs);
  if (duration == null) {
    return null;
  }
  if (duration.inMinutes >= 1) {
    final seconds = duration.inSeconds % 60;
    return seconds == 0
        ? '休眠 ${duration.inMinutes} 分钟'
        : '休眠 ${duration.inMinutes} 分 $seconds 秒';
  }
  return '休眠 ${duration.inSeconds} 秒';
}

String _subAgentActivityLabel({String? kind, String? agentPath}) {
  final kindLabel = switch (kind) {
    'started' => '已启动',
    'interacted' => '已交互',
    'interrupted' => '已中断',
    _ => kind ?? '更新',
  };
  if (agentPath == null || agentPath.isEmpty) {
    return kindLabel;
  }
  return '$kindLabel · $agentPath';
}

String? _webSearchActionPreview(Object? value) {
  final action = _map(value);
  if (action.isEmpty) {
    return null;
  }
  final type = _string(action['type']);
  return switch (type) {
    'search' => _string(action['query']) ?? _joinedStrings(action['queries']),
    'openPage' => _string(action['url']),
    'findInPage' => () {
      final parts = <String>[
        ?_string(action['url']),
        ?_string(action['pattern']),
      ];
      return parts.isEmpty ? null : parts.join(' · ');
    }(),
    _ => _objectPreview(action),
  };
}

/// 将 ThreadItem 映射为工具卡；系统类 / 消息类返回 null。
AgentToolCall? _toolCallFromThreadItem(
  Map<String, Object?> item, {
  required String id,
  required AgentToolStatus status,
  String? sessionId,
  String? turnId,
  Map<String, Object?> raw = const <String, Object?>{},
}) {
  final normalizedType = _normalizedAgentItemType(_string(item['type']));
  if (normalizedType == null ||
      normalizedType == 'agentmessage' ||
      normalizedType == 'plan' ||
      _isIgnoredLiveThreadItemType(normalizedType) ||
      _isSystemThreadItemType(normalizedType)) {
    return null;
  }

  return AgentToolCall(
    id: id,
    title: _toolTitle(item),
    kind: _toolKind(_string(item['type'])),
    status: status,
    content: _toolContentFromThreadItem(item),
    locations: _toolLocationsFromThreadItem(item),
    sessionId: sessionId,
    turnId: turnId,
    rawInput: _map(item['arguments']).isNotEmpty
        ? _map(item['arguments'])
        : _map(item['rawInput']),
    rawOutput: _map(item['result']).isNotEmpty
        ? _map(item['result'])
        : _map(item['rawOutput']),
    raw: raw.isEmpty ? item : raw,
  );
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
///
/// 本地/远程图片不写入文本（由 [_userInputLocalImagePaths] 单独提取），
/// 避免气泡里再叠一层 `[Image: path]` 占位。
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
      case 'localImage':
        // 图片走独立路径字段，不拼进文本。
        break;
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

/// 从用户输入数组提取本地图片路径。
List<String> _userInputLocalImagePaths(Object? value) {
  if (value is! List<Object?>) {
    return const <String>[];
  }
  final paths = <String>[];
  for (final itemValue in value) {
    final item = _map(itemValue);
    if (_string(item['type']) != 'localImage') {
      continue;
    }
    final path = _string(item['path']);
    if (path != null && path.isNotEmpty) {
      paths.add(path);
    }
  }
  return List<String>.unmodifiable(paths);
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
///
/// 兼容 `List` / `List<Map>` 等 jsonDecode 常见形态（不用 `List<Object?>`
/// 精确匹配，避免因 List 不变性漏解析）。
String? _joinedContentItems(Object? value) {
  final map = _map(value);
  final content = map.isEmpty ? value : map['content'];
  if (content is List) {
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
    final optionItems = <AgentUserInputOption>[];
    final opts = question['options'];
    if (opts is List<Object?>) {
      for (final optionValue in opts) {
        final option = _map(optionValue);
        final label = _trimmedText(_string(option['label']));
        if (label != null) {
          options.add(label);
          optionItems.add(
            AgentUserInputOption(
              id:
                  _trimmedText(
                    _string(option['id']) ?? _string(option['value']),
                  ) ??
                  label,
              label: label,
              description: _trimmedText(_string(option['description'])),
            ),
          );
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
        optionItems: List<AgentUserInputOption>.unmodifiable(optionItems),
        allowMultiple: question['allowMultiple'] == true,
        isOther: question['isOther'] == true,
        isSecret: question['isSecret'] == true,
      ),
    );
  }
  return List<AgentUserInputQaPair>.unmodifiable(pairs);
}

/// 将 `commandActions` 解析为面向 UI 的短语义标签。
List<String> _commandActionSummaries(Object? rawActions) {
  if (rawActions is! List<Object?>) {
    return const <String>[];
  }
  final summaries = <String>[];
  for (final value in rawActions) {
    final action = _map(value);
    final type = _string(action['type']);
    final summary = switch (type) {
      'read' => () {
        final name = _string(action['name']);
        final path = _string(action['path']);
        if (name != null && path != null) {
          return 'Read $name ($path)';
        }
        return name != null
            ? 'Read $name'
            : (path != null ? 'Read $path' : 'Read');
      }(),
      'listFiles' => () {
        final path = _string(action['path']);
        return path != null ? 'List files in $path' : 'List files';
      }(),
      'search' => () {
        final query = _string(action['query']);
        final path = _string(action['path']);
        if (query != null && path != null) {
          return 'Search "$query" in $path';
        }
        if (query != null) {
          return 'Search "$query"';
        }
        return path != null ? 'Search in $path' : 'Search';
      }(),
      'unknown' => _string(action['command']) ?? 'Unknown command',
      _ => _string(action['command']) ?? type,
    };
    if (summary != null && summary.trim().isNotEmpty) {
      summaries.add(summary.trim());
    }
  }
  return List<String>.unmodifiable(summaries);
}

/// 解析 `proposedExecpolicyAmendment` 字符串列表。
List<String> _stringList(Object? value) {
  if (value is! List<Object?>) {
    return const <String>[];
  }
  final items = <String>[];
  for (final entry in value) {
    final text = _trimmedText(_string(entry));
    if (text != null) {
      items.add(text);
    }
  }
  return List<String>.unmodifiable(items);
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
        optionItems: pair.optionItems,
        answers: answers,
        allowMultiple: pair.allowMultiple,
        isOther: pair.isOther,
        isSecret: pair.isSecret,
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
        a.header != b.header ||
        a.allowMultiple != b.allowMultiple ||
        a.isOther != b.isOther ||
        a.isSecret != b.isSecret) {
      return false;
    }
    final aOptions = a.resolvedOptions;
    final bOptions = b.resolvedOptions;
    if (aOptions.length != bOptions.length ||
        a.answers.length != b.answers.length) {
      return false;
    }
    for (var optionIndex = 0; optionIndex < aOptions.length; optionIndex += 1) {
      if (aOptions[optionIndex].id != bOptions[optionIndex].id ||
          aOptions[optionIndex].label != bOptions[optionIndex].label) {
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
///
/// Codex 稳定 schema 的 [MessagePhase] 仅有 `commentary` / `final_answer`；
/// 额外兼容历史别名 `response` / `answer` / `final`。
AgentMessagePhase? _messagePhase(String? phase) {
  return switch (phase) {
    'commentary' => AgentMessagePhase.commentary,
    // final_answer：回合终端汇总；response/answer/final 为历史别名。
    'final_answer' ||
    'finalanswer' ||
    'response' ||
    'answer' ||
    'final' => AgentMessagePhase.response,
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

/// 依次尝试 camelCase 与 snake_case 键名读取整数值。
///
/// Codex 新协议（如 `thread/tokenUsage/updated`）使用 camelCase，
/// 旧通知与 JSONL 历史使用 snake_case，读取时统一做双键兼容。
int? _breakdownInt(
  Map<String, Object?> source,
  String camelKey,
  String snakeKey,
) {
  return _numberToInt(source[camelKey]) ?? _numberToInt(source[snakeKey]);
}

/// 从多种格式中解析 DateTime：ISO 8601 字符串、Unix 秒或毫秒时间戳。
DateTime? _dateTimeFromAny(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value);
  }
  final timestamp = _numberToInt(value);
  if (timestamp == null) {
    return null;
  }
  // Codex Turn.startedAt/completedAt 与 JSONL task_* 时间均为 Unix 秒；
  // 仍兼容旧测试或其他 provider 返回的毫秒值。
  final milliseconds = timestamp.abs() < 1000000000000
      ? timestamp * Duration.millisecondsPerSecond
      : timestamp;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
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
    'interrupted' ||
    'aborted' ||
    'cancelled' ||
    'canceled' => AgentHistoryTurnStatus.interrupted,
    'failed' || 'error' => AgentHistoryTurnStatus.failed,
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

/// 从 Codex `ThreadStatus.activeFlags` 解析等待标志。
({bool waitingOnApproval, bool waitingOnUserInput}) _threadActiveFlags(
  Map<String, Object?> status,
) {
  final flags = status['activeFlags'];
  if (flags is! List) {
    return (waitingOnApproval: false, waitingOnUserInput: false);
  }
  var waitingOnApproval = false;
  var waitingOnUserInput = false;
  for (final flag in flags) {
    final name = _string(flag);
    if (name == 'waitingOnApproval') {
      waitingOnApproval = true;
    } else if (name == 'waitingOnUserInput') {
      waitingOnUserInput = true;
    }
  }
  return (
    waitingOnApproval: waitingOnApproval,
    waitingOnUserInput: waitingOnUserInput,
  );
}

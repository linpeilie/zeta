import 'package:zeta_agent_core/zeta_agent_core.dart';

/// ACP permission response option。
class AcpPermissionOption {
  const AcpPermissionOption({
    required this.id,
    required this.name,
    required this.kind,
  });

  final String id;
  final String name;
  final String kind;
}

/// ACP 权限请求的领域映射结果。
class AcpPermissionMapping {
  const AcpPermissionMapping({required this.request, required this.options});

  final AgentPermissionRequest request;
  final List<AcpPermissionOption> options;

  String? preferredOptionId({required bool approved}) {
    if (approved) {
      for (final option in options) {
        if (option.kind == 'allow_once' || option.kind.contains('allow_once')) {
          return option.id;
        }
      }
      for (final option in options) {
        if (option.kind.contains('allow')) {
          return option.id;
        }
      }
      return options.isEmpty ? null : options.first.id;
    }
    for (final option in options) {
      if (option.kind.contains('reject')) {
        return option.id;
      }
    }
    return options.isEmpty ? null : options.last.id;
  }
}

/// 将标准 ACP `session/request_permission` 映射为中立审批模型。
class AcpPermissionMapper {
  const AcpPermissionMapper._();

  static AcpPermissionMapping mapRequest({
    required Object requestId,
    required Map<String, Object?> params,
    required String? runningTurnId,
  }) {
    final options = <AcpPermissionOption>[];
    final rawOptions = params['options'];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        if (item is! Map) {
          continue;
        }
        final map = item.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final id = map['optionId']?.toString();
        if (id == null || id.isEmpty) {
          continue;
        }
        options.add(
          AcpPermissionOption(
            id: id,
            name: map['name']?.toString() ?? id,
            kind: map['kind']?.toString() ?? '',
          ),
        );
      }
    }

    final requestKey = requestId.toString();
    final sessionId = params['sessionId']?.toString();
    final toolCall = params['toolCall'];
    var title = 'Approve tool execution';
    String? description;
    if (toolCall is Map) {
      title = toolCall['title']?.toString() ?? title;
      description = toolCall['kind']?.toString();
    }

    return AcpPermissionMapping(
      request: AgentPermissionRequest(
        id: requestKey,
        title: title,
        kind: AgentPermissionKind.other,
        description: description,
        sessionId: sessionId,
        turnId: runningTurnId,
        raw: AgentProviderRawPayload.wrap(params),
      ),
      options: List<AcpPermissionOption>.unmodifiable(options),
    );
  }
}

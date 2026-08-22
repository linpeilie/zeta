import 'dart:convert';
import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_providers/src/grok_cli_locator.dart';
import 'package:zeta_agent_providers/src/mappers/context_window_codec.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

final _log = zetaLoggerFor('zeta.agent.grok_models_cli');

/// 通过 `grok models` 子进程拉取模型列表（ACP 无列表时的降级路径）。
class GrokModelsCli {
  const GrokModelsCli({
    this.locator = const GrokCliLocator(),
    this.processRunner = _defaultRun,
  });

  final GrokCliLocator locator;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  })
  processRunner;

  /// 解析 `grok models` 文本输出为中立模型列表。
  Future<AgentModelList> listModels(AgentProviderConfig config) async {
    final resolved = await locator.locate(config);
    if (resolved == null) {
      _log.w('Could not locate Grok CLI for models list');
      return const AgentModelList(models: <AgentModelInfo>[]);
    }

    try {
      final result = await processRunner(
        resolved.executable,
        resolved.argumentsFor(const <String>['models']),
        environment: <String, String>{
          ...Platform.environment,
          ...config.environment,
        },
      );
      if (result.exitCode != 0) {
        _log.w(
          'grok models exited with ${result.exitCode} '
          '(${result.stderr.toString().length} stderr characters)',
        );
        return const AgentModelList(models: <AgentModelInfo>[]);
      }
      return parseModelsOutput(result.stdout.toString());
    } catch (error, stackTrace) {
      _log.w('Could not run grok models', error: error, stackTrace: stackTrace);
      return const AgentModelList(models: <AgentModelInfo>[]);
    }
  }

  /// 解析 `grok models` 的人类可读文本。
  ///
  /// 典型格式：
  /// ```text
  /// Default model: grok-4.5
  /// Available models:
  ///   * grok-4.5 (default)
  ///   - grok-composer-2.5-fast
  /// ```
  static AgentModelList parseModelsOutput(String stdout) {
    final models = <AgentModelInfo>[];
    String? defaultModel;
    for (final rawLine in const LineSplitter().convert(stdout)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final defaultMatch = RegExp(
        r'^Default model:\s*(\S+)',
        caseSensitive: false,
      ).firstMatch(line);
      if (defaultMatch != null) {
        defaultModel = defaultMatch.group(1);
        continue;
      }
      final modelMatch = RegExp(r'^[\*\-]\s+(\S+)').firstMatch(line);
      if (modelMatch == null) {
        continue;
      }
      final id = modelMatch.group(1)!;
      final isDefault =
          line.toLowerCase().contains('(default)') || id == defaultModel;
      models.add(
        AgentModelInfo(
          id: id,
          model: id,
          displayName: id,
          isDefault: isDefault,
          raw: <String, Object?>{'source': 'grok models', 'line': line},
        ),
      );
    }

    if (models.isEmpty && defaultModel != null) {
      models.add(
        AgentModelInfo(
          id: defaultModel,
          model: defaultModel,
          displayName: defaultModel,
          isDefault: true,
          raw: const <String, Object?>{'source': 'grok models'},
        ),
      );
    }
    return AgentModelList(models: List<AgentModelInfo>.unmodifiable(models));
  }

  static Future<ProcessResult> _defaultRun(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    return Process.run(
      executable,
      arguments,
      environment: environment,
      runInShell: false,
    );
  }
}

/// 从 ACP `session/new` / `session/load` 结果中的 `models` 字段构建列表。
AgentModelList? parseAcpModelsPayload(Object? value) {
  if (value is! Map) {
    return null;
  }
  final map = value.map(
    (key, item) => MapEntry(key.toString(), item as Object?),
  );
  final available = map['availableModels'];
  if (available is! List) {
    return null;
  }

  final currentId = map['currentModelId']?.toString();
  final models = <AgentModelInfo>[];
  for (final item in available) {
    if (item is! Map) {
      continue;
    }
    final entry = item.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final modelId =
        entry['modelId']?.toString() ?? entry['id']?.toString() ?? '';
    if (modelId.isEmpty) {
      continue;
    }
    final name = entry['name']?.toString() ?? modelId;
    final description = entry['description']?.toString();
    final meta = entry['_meta'];
    final metaMap = meta is Map
        ? meta.map((key, value) => MapEntry(key.toString(), value as Object?))
        : const <String, Object?>{};

    final efforts = <AgentModelReasoningEffort>[];
    final rawEfforts = metaMap['reasoningEfforts'];
    if (rawEfforts is List) {
      for (final effortItem in rawEfforts) {
        if (effortItem is! Map) {
          continue;
        }
        final effortMap = effortItem.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final effort =
            effortMap['value']?.toString() ??
            effortMap['id']?.toString() ??
            effortMap['effort']?.toString();
        if (effort == null || effort.isEmpty) {
          continue;
        }
        efforts.add(
          AgentModelReasoningEffort(
            effort: effort,
            description: effortMap['description']?.toString(),
          ),
        );
      }
    } else if (metaMap['supportsReasoningEffort'] == true) {
      final single = metaMap['reasoningEffort']?.toString();
      if (single != null && single.isNotEmpty) {
        efforts.add(AgentModelReasoningEffort(effort: single));
      }
    }

    models.add(
      AgentModelInfo(
        id: modelId,
        model: modelId,
        displayName: name,
        description: description,
        isDefault: modelId == currentId,
        supportedReasoningEfforts: List<AgentModelReasoningEffort>.unmodifiable(
          efforts,
        ),
        defaultReasoningEffort:
            metaMap['reasoningEffort']?.toString() ??
            (efforts.isNotEmpty ? efforts.first.effort : null),
        contextWindowTokens:
            ContextWindowCodec.positiveWindow(entry) ??
            ContextWindowCodec.positiveWindow(metaMap),
        raw: Map<String, Object?>.from(entry),
      ),
    );
  }

  if (models.isEmpty) {
    return null;
  }
  return AgentModelList(models: List<AgentModelInfo>.unmodifiable(models));
}

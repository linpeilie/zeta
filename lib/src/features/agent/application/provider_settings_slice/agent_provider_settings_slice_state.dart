import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Provider settings 切片只保存稳定失败分类，不保存原始异常文本。
enum AgentProviderSettingsFailureKind { load, persist }

@immutable
final class AgentProviderSettingsSliceFailure {
  const AgentProviderSettingsSliceFailure({
    required this.kind,
    required this.operationId,
  });

  final AgentProviderSettingsFailureKind kind;
  final OperationId operationId;

  @override
  bool operator ==(Object other) =>
      other is AgentProviderSettingsSliceFailure &&
      other.kind == kind &&
      other.operationId == operationId;

  @override
  int get hashCode => Object.hash(kind, operationId);
}

const Object _providerSettingsSliceUnset = Object();

/// 全局 Provider 设置的不可变 application state。
///
/// [settings] 是运行态唯一 owner；持久化 store 只是外部投影。请求阶段先更新
/// 内存候选值，保持旧 controller 的 getter 语义，只有确认回执才通知兼容监听方。
@immutable
final class AgentProviderSettingsSliceState {
  const AgentProviderSettingsSliceState({
    this.settings = const AgentProviderSettings(),
    this.loading = false,
    this.loadOperationId,
    this.persistOperationId,
    this.lastFailure,
  });

  final AgentProviderSettings settings;
  final bool loading;
  final OperationId? loadOperationId;
  final OperationId? persistOperationId;
  final AgentProviderSettingsSliceFailure? lastFailure;

  AgentProviderSettingsSliceState copyWith({
    AgentProviderSettings? settings,
    bool? loading,
    Object? loadOperationId = _providerSettingsSliceUnset,
    Object? persistOperationId = _providerSettingsSliceUnset,
    Object? lastFailure = _providerSettingsSliceUnset,
  }) {
    return AgentProviderSettingsSliceState(
      settings: settings ?? this.settings,
      loading: loading ?? this.loading,
      loadOperationId: identical(loadOperationId, _providerSettingsSliceUnset)
          ? this.loadOperationId
          : loadOperationId as OperationId?,
      persistOperationId:
          identical(persistOperationId, _providerSettingsSliceUnset)
          ? this.persistOperationId
          : persistOperationId as OperationId?,
      lastFailure: identical(lastFailure, _providerSettingsSliceUnset)
          ? this.lastFailure
          : lastFailure as AgentProviderSettingsSliceFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentProviderSettingsSliceState &&
      identical(other.settings, settings) &&
      other.loading == loading &&
      other.loadOperationId == loadOperationId &&
      other.persistOperationId == persistOperationId &&
      other.lastFailure == lastFailure;

  @override
  int get hashCode => Object.hash(
    identityHashCode(settings),
    loading,
    loadOperationId,
    persistOperationId,
    lastFailure,
  );
}

/// Provider settings 的纯只读派生函数。
abstract final class AgentProviderSettingsSelectors {
  static AgentProviderSettings settings(
    AgentProviderSettingsSliceState state,
  ) => state.settings;

  static String activeProviderId(AgentProviderSettingsSliceState state) =>
      state.settings.activeProvider.id;

  static AgentProviderConfig activeProviderConfig(
    AgentProviderSettingsSliceState state,
  ) => state.settings.activeProvider;

  static List<AgentProviderConfig> enabledProviders(
    AgentProviderSettingsSliceState state,
  ) => List<AgentProviderConfig>.unmodifiable(
    state.settings.providers.where((provider) => provider.enabled),
  );
}

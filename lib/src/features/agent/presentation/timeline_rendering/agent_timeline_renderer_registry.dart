/// 时间线渲染分发注册表。
///
/// 单层平表：block 级 block 直接按自身类型登记，entry 级 block 解包后按 entry
/// 类型登记。解析失败即抛（fail-closed），不允许静默回退成空白卡片。
library;

import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';

/// 按 payload 运行时类型分发的 renderer 注册表。
///
/// 不做全局单例：`AgentPane` 组合段创建一次并沿构造参数下传，测试可以注入裁剪版。
final class AgentTimelineRendererRegistry {
  /// 用 renderer 清单创建注册表。
  ///
  /// 同一 [AgentTimelineRenderer.payloadType] 重复登记直接抛
  /// [ArgumentError]——重复登记只可能是漏删旧 renderer，静默后写会让分发结果
  /// 取决于清单顺序。
  AgentTimelineRendererRegistry(List<AgentTimelineRenderer<Object>> renderers)
    : _byPayloadType = _indexByPayloadType(renderers);

  final Map<Type, AgentTimelineRenderer<Object>> _byPayloadType;

  static Map<Type, AgentTimelineRenderer<Object>> _indexByPayloadType(
    List<AgentTimelineRenderer<Object>> renderers,
  ) {
    final byType = <Type, AgentTimelineRenderer<Object>>{};
    for (final renderer in renderers) {
      final type = renderer.payloadType;
      if (byType.containsKey(type)) {
        throw ArgumentError.value(renderers, 'renderers', '时间线渲染类型重复注册: $type');
      }
      byType[type] = renderer;
    }
    return byType;
  }

  /// 已登记的 payload 类型（诊断与守卫测试用）。
  Iterable<Type> get registeredPayloadTypes => _byPayloadType.keys;

  /// 解析 block 对应的 renderer。
  ///
  /// 未注册即抛 [UnsupportedError]：新增 block/entry 类型时必须同步加 renderer，
  /// 不允许悄悄渲染成空白（G4 精神）。
  AgentTimelineRenderer<Object> resolve(AgentTimelineRenderBlock block) {
    final type = payloadOf(block).runtimeType;
    final renderer = _byPayloadType[type];
    if (renderer == null) {
      throw UnsupportedError('未注册的时间线渲染类型: $type');
    }
    return renderer;
  }

  /// 取 block 的渲染 payload：entry 级 block 解包成 entry，其余为 block 自身。
  static Object payloadOf(AgentTimelineRenderBlock block) {
    return block is AgentTimelineEntryRenderBlock ? block.entry : block;
  }
}

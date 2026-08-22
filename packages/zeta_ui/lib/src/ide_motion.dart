import 'package:flutter/animation.dart';

/// IDE 动效 token。
///
/// 交互反馈、展开/收起、主题切换相关动画的时长与曲线统一从这里取，
/// 避免各 feature 各自写 `Duration(milliseconds: …)`。
/// 若系统开启「减少动态效果」，调用方应自行降为 `Duration.zero`（见 Composer、
/// 模型配置等已有判断）。
abstract final class IdeMotion {
  /// 瞬时反馈：悬停高亮、窗口按钮 hover、小控件闪动。
  ///
  /// 生效位置：`WindowFrame` 窗口控制按钮 hover；拖拽手柄高亮
  /// （`IdeResizeHandle` 使用别名 [fast]）；Composer / 模型配置中的
  /// 快速状态切换。
  static const Duration durationFast = Duration(milliseconds: 100);

  /// 常规交互：Tab 选中态、折叠摘要、列表选中、多数 `AnimatedContainer`。
  ///
  /// 生效位置：`IdeTabs` 选中底色与文字过渡；`IdeCollapsibleCard` 摘要区；
  /// `PaneInteractiveSurface` 状态过渡；项目列表选中；Composer 外卡与
  /// 发送区切换；消息区展开/收起；模型配置面板动画等。
  static const Duration durationNormal = Duration(milliseconds: 160);

  /// 较慢过渡：大块内容展开、弹出层进出。
  ///
  /// 生效位置：`IdeCollapsibleCard` 正文展开；Agent 时间线段落展开
  /// （`agent_pane_sections`）；配合 [curvePopup] 的弹出感动画。
  static const Duration durationSlow = Duration(milliseconds: 260);

  /// 持续加载提示的呼吸周期，例如 Provider Tab 的文字透明度脉冲。
  static const Duration durationLoadingPulse = Duration(milliseconds: 900);

  /// Agent Composer 在回合运行期间的边框扫光周期。
  ///
  /// 该动效用于持续状态提示，速度应低于常规交互动画，避免干扰正文阅读。
  static const Duration durationRunningGlow = Duration(milliseconds: 2400);

  /// 最高思考档位的像素流光周期。
  ///
  /// 动效只用于持续表达增强推理状态；减少动态效果时由调用方停止循环，
  /// 并保留静态渐变作为状态提示。
  static const Duration durationIntelligenceShimmer = Duration(
    milliseconds: 1800,
  );

  /// 进入最高思考档位时，端点冲击波的一次性扩散时长。
  ///
  /// 该动效与持续流光分离，确保停留在最高档时不会反复闪烁。
  static const Duration durationIntelligenceImpact = Duration(
    milliseconds: 320,
  );

  /// [durationFast] 的简短别名。
  static const Duration fast = durationFast;

  /// [durationNormal] 的简短别名。
  static const Duration normal = durationNormal;

  /// [durationSlow] 的简短别名。
  static const Duration slow = durationSlow;

  /// 默认缓动：多数 IDE 内联动画。
  ///
  /// 生效位置：与 [durationNormal] / [durationFast] 配套的
  /// `AnimatedContainer`、`AnimatedSwitcher`、选中态过渡等。
  static const Curve curveDefault = Curves.easeInOutCubic;

  /// 桌面滚轮平滑滚动：快速响应输入，并在终点前自然减速。
  static const Curve curveScroll = Curves.easeOutCubic;

  /// 弹出/展开缓动：结束段更利落，适合浮层与折叠正文。
  ///
  /// 生效位置：`IdeCollapsibleCard` 正文；消息区弹出式控件
  /// （`agent_pane_messages` 中配合 [durationNormal]）。
  static const Curve curvePopup = Curves.easeOutQuint;
}

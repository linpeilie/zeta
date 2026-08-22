/// Zeta 的纯 Dart 最小公共契约。
///
/// 这个 Package **不依赖** Flutter、Riverpod、`dart:io` 或任何 Provider 协议：
/// 它只放跨 bounded context 都要用、且不含业务语义的基础类型。
///
/// 收录标准（不满足就不要放进来）：
///
/// 1. 纯 Dart，可在任何宿主运行；
/// 2. 至少两个 bounded context 需要，或用来建立可执行门禁；
/// 3. 不承载用户内容——这里的类型会进日志和指标。
library;

export 'src/collections/zeta_equality.dart';
export 'src/logging/zeta_logger.dart';
export 'src/mvi/transition.dart';
export 'src/observability/in_memory_zeta_metrics_port.dart';
export 'src/observability/zeta_metric.dart';
export 'src/observability/zeta_metric_label.dart';
export 'src/observability/zeta_metrics_port.dart';
export 'src/operation/operation_id.dart';
export 'src/time/clock.dart';
export 'src/typography/app_typography.dart';

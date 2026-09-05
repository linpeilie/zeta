/// Zeta 的最小公共契约与宿主平台工具。
///
/// 这里的核心契约保持平台中立；宿主相关能力集中在 `src/platform/`，不向
/// 领域模型泄漏平台协议。
///
/// 核心契约的收录标准（不满足就不要放进来）：
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
export 'src/storage/storage_service.dart';
export 'src/time/clock.dart';
export 'src/typography/app_typography.dart';
export 'src/security/sensitive_data_redactor.dart';
export 'src/paths/user_home_directory.dart';

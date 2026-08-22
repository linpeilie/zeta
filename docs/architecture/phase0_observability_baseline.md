# 阶段 0：测试与可观测性基线

最后更新：2026-08-21

状态：阶段 0 已落地。对应 [目标架构 §14 Phase 0](./target_architecture_riverpod_mvi_plugins_packages.md#phase-0增加测试与可观测性)。

本文件记录阶段 0 交付了什么、基线数值是多少、怎么复测，以及哪些指标**尚未**测量。
Phase 1–4 的每一步都要回到这里比对：数字变差就是回归，不是"迁移代价"。

---

## 1. 阶段 0 交付内容

| 交付物 | 位置 |
| --- | --- |
| 白名单指标定义 | [`zeta_metric.dart`](../../packages/zeta_foundation/lib/src/observability/zeta_metric.dart)（阶段 1 迁入 `zeta_foundation`） |
| 统一指标端口 + no-op 默认实现 | [`zeta_metrics_port.dart`](../../packages/zeta_foundation/lib/src/observability/zeta_metrics_port.dart) |
| 进程内有界聚合器 | [`in_memory_zeta_metrics_port.dart`](../../packages/zeta_foundation/lib/src/observability/in_memory_zeta_metrics_port.dart) |
| 脱敏 Riverpod 观察器 | [`lib/src/app/observability/zeta_provider_observer.dart`](../../lib/src/app/observability/zeta_provider_observer.dart) |
| app 级可观测性组合根 | [`zeta_observability.dart`](../../lib/src/app/observability/zeta_observability.dart) |
| 事件管线指标采样器 | [`agent_pipeline_metrics_reporter.dart`](../../lib/src/features/agent/application/agent_pipeline_metrics_reporter.dart) |
| 流式指标基线测试 | `test/src/features/agent/application/agent_streaming_metrics_baseline_test.dart` |
| 行为快照（发送/取消/审批/双会话） | `test/src/features/agent/presentation/agent_phase0_behavior_baseline_test.dart` |
| Package 候选依赖图守卫 | `test/src/architecture/package_boundary_candidate_graph_test.dart` |
| 可观测性隐私守卫 | `test/src/architecture/observability_privacy_guard_test.dart` |

### 1.1 默认关闭，显式开启

生产默认注入 `noopZetaMetricsPort`：所有探针只剩一次 `isEnabled` 常量分支，不分配对象、不做字符串处理。

```sh
flutter run -d macos --dart-define=ZETA_METRICS=true
```

开启后 `ZetaObservability.inMemory()` 接管，同时给根 `ProviderScope` 挂上 `ZetaProviderObserver`，并把同一个端口注入
`IdeShellController → AgentThreadWorkspaceController → AgentConversationViewModel → 事件管线采样器 / UI 帧调度器`
以及 `AgentProviderRuntimeRegistry`。回退方式就是不传这个 define。

### 1.2 共享层零改动

`AgentEventPipeline` 属于 G1 共享适配层且内容基线被冻结（T18），因此**没有在管线内部埋点**。
指标由 `AgentPipelineMetricsReporter` 在边界（帧发布、backpressure、pipeline 替换/关闭）读取
`AgentEventPipelineDiagnostics` 并上报增量。副作用是热路径上完全没有逐事件开销。

### 1.3 隐私约束

- 指标名是封闭枚举，端口签名不接受 `String`；
- 标签只有 `providerId` / `component` / `outcome` 三个维度，且**类型是
  `ZetaMetricLabel` 而不是 `String`**——运行期字符串在类型层面就进不来。标签只有
  三个入口：`constant`（源码字面量，架构守卫强制实参为字面量）、
  `declaredIdentifier`（声明期常量，形态异常自动降级为 hash）、
  `hashed`（会话内不可逆短 hash）。Provider ID 来自 `~/.zeta` 的自由 JSON，
  因此走 `AgentMetricLabels.forProviderId`：三个内置 Provider 映射常量，
  其余一律 `h.xxxxxxxx`。形态正则只做格式校验，不承担隐私职责；
- Riverpod 观察器不读取 `value` / `newValue` / `previousValue`，也不读 family 的 `argument`；
- 聚合器按 `maxSeries` 封顶，超出只累加 `droppedSeriesSamples`，不会无界增长。

以上四条都有源码级守卫测试兜底。

---

## 2. 基线数值

采集环境：macOS（darwin 23.6，Apple Silicon），`dart_test.yaml` 固定 `concurrency: 2`，Debug 构建。

### 2.1 工具链耗时

| 项目 | 数值 |
| --- | --- |
| `flutter analyze` | 3.8–5.8s，0 issue |
| `dart format .` | 629 个文件，约 3.5s |
| `bash tool/test_full.sh` | 2114 passed / 0 failed / 0 skipped，聚合 248.4s，墙钟约 4m10s |
| 最慢套件 | `agent_conversation_widget_test.dart` 18.4s；`ide_shell_widget_test.dart` 16.1s |

### 2.2 固定流式 fixture（`AgentEventStormFixture`，10 825 个输入事件）

**单元层**（同步源 + microtask flush，`agent_streaming_metrics_baseline_test.dart`）：

| 指标 | 基线 |
| --- | ---: |
| received | 10 825 |
| accepted | 309 |
| rejected | 0 |
| coalesced | 10 516 |
| dispatched | 309 |
| backpressure flushes | 0 |
| pending keys / queue depth（关闭时） | 0 / 0 |

不变式：`accepted + coalesced == received`。合并率约 97%，这是"流式不卡 UI"的量化前提。

**Widget 全链路层**（真实 `IdeHome` + AgentPane，`ide_shell_widget_test.dart`）：

| 指标 | 观测值 | 预算上界 |
| --- | ---: | ---: |
| buffer received / barrier / maxPendingKeys | 10 825 / 25 / 1 | pendingKeys ≤ 64 |
| dispatcher delivered / batches / yields / maxQueue | 10 825 / 10 821 / 0 / 2 | queue ≤ 64 |
| UI region publish | 227 | ≤ 400 |
| frame publish / immediate publish / invalidated callbacks | 0 / 227 / 204 | — |
| Shell thread snapshot 通知 | 2 | 精确断言 |
| `IdeHome` / `AgentPane` / `_AgentHeader` / `_AgentComposerSection` / `_AgentConversationTimeline` 重建 | 各 1 | 各 ≤ 2 |

> 逐事件 pump 的 Widget 环境里 buffer 没有合并机会（coalesced = 0），这与单元层的差异是**测试驱动方式**造成的，不是行为差异。
> 纯 message delta 与 reasoning/tool progress 两个子场景另有断言：Shell、Header、Composer 重建必须为 **0**，只有局部时间线重建。

### 2.3 Package 候选依赖图

| 项目 | 基线 |
| --- | ---: |
| 候选 Package 反向/越级依赖 | 10 处（`_knownEdgeViolations`） |
| 纯 Dart 层外部依赖越界 | 8 处（`_knownExternalViolations`） |
| `zeta_agent_core` 候选层依赖 Flutter 的文件 | 17 个 |
| 候选 Package 之间的循环依赖 | 0 |

这三个清单是 Phase 1 的燃尽表：只允许变小，修好一条就要从清单里删掉一条（守卫会因"过期条目"失败）。

---

## 3. 尚未测量（待执行）

以下项目**没有**在阶段 0 取得数据，不得推断或用 Debug 数据代替：

| 项目 | 阻塞原因 | 取得方式 |
| --- | --- | --- |
| 应用启动耗时（bootstrap 阶段 / 首个可交互帧） | 需要 Profile 构建与真实桌面会话 | `flutter run --profile -d macos --dart-define=ZETA_METRICS=true`，读 `appBootstrapDuration` |
| 1 / 2 / 4 个活跃会话的内存占用 | 同上，Debug 堆数据不能作为结论 | Profile 构建 + DevTools memory 快照 |
| frame time / jank | 同上；`AGENTS.md` 要求 Windows Profile 采样作为热路径结论来源 | Windows Profile 构建 + DevTools performance |
| 真实 CLI 冒烟对指标的影响 | 需要本机 Codex / Grok / Claude CLI 与凭据 | `tool/smoke_*.py`，记录时按 G7 脱敏 |

`ZetaMetric.appBootstrapDuration` 已在白名单里预留，但阶段 0 还没有接入 bootstrap 埋点——
接入它属于取得上表数据时的配套工作。

---

## 4. 复测方式

```sh
flutter analyze
bash tool/test_full.sh
flutter test test/src/features/agent/application/agent_streaming_metrics_baseline_test.dart
flutter test test/src/app/ide_shell_widget_test.dart --plain-name "records the current Agent event storm rebuild baseline"
flutter test test/src/architecture/package_boundary_candidate_graph_test.dart
```

两个基线测试都会 `debugPrint` 一行 `agent-pipeline-metrics-baseline …` /
`agent-event-widget-baseline …`，可直接抄进 PR 描述做前后对比。

---

## 5. 阶段 0 能检测到的告警条件

对应目标架构 §11.3：

| 告警条件 | 现在怎么检测 |
| --- | --- |
| 普通流式更新超过一帧一次 | `agentUiFramePublishes` 计数 + 基线测试里的每帧一次断言 |
| dispatcher / 缓存无界增长 | `agentPipelineQueueDepth` / `agentPipelinePendingKeys` gauge 高水位 + 预算断言 |
| 已 dispose 的 UI 端口仍收到更新 | `agentUiRequestsAfterDispose` |
| runtime generation 失配的结果被接受 | `agentPipelineEventsRejected` 与行为快照断言 |
| Provider runtime 泄漏 / 孤儿进程 | `agentRuntimeActiveCount` / `agentRuntimeActiveLeases` gauge |
| Riverpod provider 异常高频更新或反复重建 | `riverpodProviderUpdated` / `riverpodProviderAdded` 按 provider 名聚合 |
| 指标标签基数失控 | `InMemoryZetaMetricsPort.droppedSeriesSamples` |

阈值本身按 §11.3 的要求留到 Phase 1 之后固定；阶段 0 只保证**采得到**。

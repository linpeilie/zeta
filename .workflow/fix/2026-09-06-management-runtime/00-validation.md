# WP-1 · 按 Provider 实例聚合运行事实验收

- 实施日期：2026-09-05 至 2026-09-06；基线：`cf518b64`，开始时工作区干净。
- 前置证据：WP-6 实现 `8778a8ae`、验收登记 `cf518b64`。
- 工作包：[lib cohesion / WP-1](../../plan/2026-09-05-lib-cohesion/01-wp1-runtime-summary.md)。后继为 WP-4。
- 实现提交：`ea56f5c9`。

## 1. 实现与生产接线

`RuntimeController.runtimeObservationListenable + BindingManager + Workspace → WorkspaceAgentRuntimeFactSource → Management.runtimeFactsReplaced → aggregateManagementRuntime → runtimeByProviderId → 管理行/首页`。

- 事实源由 Shell 创建并 start，管理 composition 借用只读端口。关闭顺序为管理消费者退订/关闭 Store → source close → Workspace/BindingManager；source 不获取/释放租约、不启动插件、不清理 runtime。
- 按精确配置实例 id 汇总所有前后台会话；Binding 对象 identity 生成 opaque token，晋升不增量计数；完整 runtime identity 区分同 Provider 并存的不同 session scope/generation。
- 保留 active turn、ready runtime、starting/error/unavailable Binding 和未观测 turn 的 runtime 共六类计数。主状态按 running → error → starting → unavailable → idle → disabled → notRunning 投影；hasErrors 单独保留，宽窄管理行均展示错误图标。
- disabled 不代替实际进程状态。聚合测试保留尚存连接/运行事实；真实设置路径触发 runtime invalidation 后，source 才收敛为 disabled。
- RuntimeController 与 ThreadSnapshot 共用安全发布边界，连接单独变化也更新观测；source 以当前 Binding 生命周期、runtime identity、connection scope 与 attemptEpoch 拒绝旧事实。
- reducer 所有 ingress 统一投影兼容 `ManagedAgent.runtimeState`；初始化、探测 partial/result、连接测试和 settings 更新不再各自赋值。移除旧 tuple、runner runtime overlay、IdeHome 状态拼接及 Shell 运行订阅桥。
- 自定义 id 保留在 summary map，没有对应 management contribution 时不创建厂商卡片。global 预热、连接测试、外部 CLI、历史 active 与短 RPC 均不被误算为活跃 session turn。
- Store/镜像 Notifier 的当前 owner 结构保持原样；首页诊断缓存仍留给 WP-5，本次只从同一 runtime summary 覆盖实时状态。

## 2. 回归与设计细化

先新增真实 IdeHome/Shell 回归：在默认 Codex 下创建 Grok entry 并发送未结束回合，读取生产管理摘要。旧实现失败，期望 Grok running、实际 notRunning。修复后同一断言通过，另验证首页显示 running，切换 entry/Settings 后归属不变。仅外部 Provider/存储/检测端口使用 fake，未用 fake runtime tuple 绕过 source。

| 场景 | 验证位置 |
|---|---|
| 精确实例归属、自定义 id、同 Provider 多 generation、去重、固定优先级、running + error、禁用保留事实 | `agent_management_runtime_aggregation_test.dart` |
| 前后台、draft 晋升、历史 active、短 RPC、同 Provider 两个 session、旧 clear/事件、连接代次、失败重试、等待交互 | `workspace_agent_runtime_fact_source_test.dart` |
| retained runtime 的连接与未观测计数、连接关闭、重复 close、关闭后事件、重入 membership、相等抑制 | 同上；只观察端口的 factory/dispose 调用数不变 |
| 初始化/探测/连接测试晚到不覆盖实时事实，settings 与全量替换收敛，自定义实例不补造卡片 | `agent_management_slice_store_test.dart` |
| 宽窄管理行同时显示 running 和独立错误提示 | `agent_management_page_test.dart`，680/1280 两个宽度 |
| 默认 Codex / Grok 执行，管理摘要与首页一致，切换选中项/设置页不改变归属 | `ide_shell_widget_test.dart` |
| 生产文件非空扫描、禁止按默认/前台身份归属、禁止 observer 控制租约、旧 tuple 删除；负例确实被拒绝 | `agent_management_runtime_boundary_guard_test.dart` |

首轮受影响门禁发现隐藏首页的状态刷新导致 Workbench 多重建一次；限制首页可见性后，原有性能断言与全部 Shell 测试通过，未放宽测试。

实施相对目标伪代码的三处明确细化：

1. 观测来源 identity 与 connection scope 在 live 接线时冻结，scope 取实际 pipeline listener；不是每次发布都用当前连接给旧 thread facts 重新贴标签。连接 epoch 回归证明旧 active 被屏蔽为未观测。
2. 只有没有 controller 的 retained Binding 才额外监听事件通知，并且完全不读取事件内容，只同步重读生命周期。正常 entry 只随安全发布边界更新，避免沿 token 流重复扫描全体 Binding。首页在实际可见时才触发 Workbench 重建，隐藏时只刷新可用性缓存；原有 message/reasoning/tool 流式零 Shell 重建断言保持不变。
3. 尚未发起 session 启动（attemptEpoch 为 0）的 global 目录失败不算 session 启动错误；首次 beginTurn 与 Plan 执行复用观测 helper。startup error/unavailable 在同 attempt 内保留，新 starting 立即屏蔽旧失败。

## 3. 验证门禁

- `dart format .`：通过，1100 个 Dart 文件。
- `flutter analyze`：通过，0 issues。
- `dart run tool/check_localized_ui_strings.dart --check`：通过，0 个新增字面量、0 allowlist 项；本次复用既有错误文案，无 ARB/生成文件修改。
- `ide_shell_widget_test.dart`：完整文件 34 条通过，包含新增归属回归、流式性能和切页保活。
- `bash tool/test_affected.sh -- --reporter expanded`：通过，681 条，选中 81/307 个根测试文件；包含常驻/Agent 架构守卫、并行会话、审批、生命周期和真实 Shell 回归。
- `git diff --check`：通过。8 份计划/验收文档及新增文档链接共 29 处本地链接通过，无失效链接。
- 范围复核：pubspec/lock、packages、third_party、tool、macOS/Windows/Linux 原生目录均无改动。

本次为 WP-1 行为修复，按计划 §5.1 使用定向与受影响门禁；未移动 owner，未修改测试调度器、选择器、分片或并发配置，未运行 `test_full.sh`。最终集成仍须完整门禁。本次没有 Provider 协议、内部 Package、依赖锁、原生或持久化格式改动；未以 fake 测试声明真实 CLI 或跨平台实机验收通过。

## 4. 后继与回滚

下一项 WP-4 收口 Project Threads 的重复规则。WP-3 后续迁移 owner 时保留 `AgentManagementRuntimeFactSource` 契约，并把 source 放到独立 app 生命周期，不能回读依赖 management 的 workbench session。WP-5 再统一诊断已确认值/partial 与首页缓存，不得恢复探测结果覆盖 runtime summary。

回滚时整体回退本提交的 observation、source、聚合与消费者接线，不并存两套 runtime ingress；没有落盘数据迁移。

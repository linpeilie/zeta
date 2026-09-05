# WP-6 · 会话配置结果与等待状态验收

- 日期：2026-09-05；实施基线：`e951d9a5`；开始时工作区干净。
- 工作包：[lib cohesion / WP-6](../../plan/2026-09-05-lib-cohesion/06-wp6-session-config.md)。执行队列下一项为 WP-1。
- 实现提交：`8778a8ae`。

## 1. 实现与生产接线

`AgentComposerSection → invokeSessionConfigCommand → RuntimeController.selectSessionConfigOption → Binding.runCurrent → sessionConfiguration`。

- executor/CommandPort 返回 `Future<AgentCommandOutcome>`。缺端口或 Provider 明确拒绝能力的 `UnsupportedError` 继续抛出，由 UI 边界翻译为 `failed(unsupported)`；普通请求异常只返回 `requestFailed`。
- 无 thread/只读/无效目录项或值为 `notAllowed`，等值为 `unchanged`；无 runtime 为 `providerUnavailable`；关闭或目标换代为 `staleTarget`。只有实际调用完成且目标有效才成功。
- 当前端口是唯一能力真源；端口消失时当前 Composer 不再展示旧配置目录。迟到旧控件快照仍经过真实 Section 回调并得到 typed unsupported。
- 同 configId 队列在入队前冻结 thread/runtime identity/scope，执行前读取当前目录并二次校验只读；不同 configId、取消与审批不进入该队列。dispose 立即结算全部调用者，未执行闭包被释放，迟到完成幂等处理。
- 控件只有 pending、failure kind 和选择代数；entry/runtime 变化清理旧反馈。同 thread key 重开使用 controller 生命周期区分旧控件，旧浮层销毁。显示值仍来自 typed options/Provider 事件。
- 错误图标位于配置控件旁，悬停读取本地化原因，并有 live-region 语义提示；没有在固定工具栏内增加第二行错误文本。pending 不阻塞另一个配置项或取消回合。
- 不再把 session-config 失败写入全局 status.details；日志只记录固定操作文本与异常类型，不包含配置 id、值或异常原文。

## 2. 回归证据

先在旧实现上新增并运行两条测试：明确 UnsupportedError 被吞掉、无 runtime 返回 void。两条均失败，实际结果均为 Future<void> 正常完成；修复后通过。原有测试业务断言未删除或放宽。

| 场景 | 证据 |
|---|---|
| 缺端口、Provider 拒绝能力 | executor 抛错；真实 Section/配置控件翻译为 unsupported；无端口零调用 |
| 未附着、草稿、只读、关闭 | 分别返回 unavailable/notAllowed/notAllowed/stale；零 Provider 调用 |
| 标量与目录验证 | String/bool/有限 num select；boolean 只收 bool；非标量、非有限数、无效 id、未知 kind 拒绝；等值零调用 |
| 请求异常 | requestFailed 无 diagnostic；header 保持原值；失败控件可再次选择相同值 |
| 请求顺序 | 同 key A/B 串行；其他 key 并行；A UnsupportedError 不阻断 B；B 使用最新目录 |
| 设置禁用 | 发起后禁用会使既有 scope 失效，排队项返回 stale；新发起的只读命令返回 notAllowed |
| 目标过期 | 排队前/等待 Provider 期间/异常返回时换 runtime；旧结果不成功、不执行旧排队项 |
| 关闭 | 执行中 A 与排队 B 无需等待 Provider 即结算；迟到成功/异常无重复完成、无发布 |
| 两 Provider / 两 thread | 两个独立 controller/Binding 的同 key 请求不共享等待队列或完成状态 |
| 真实控件 | pending、单控件禁用、独立取消、事件确认显示值、失败保留值与重试、销毁及 runtime 失效的迟到结果静默 |
| 同 key entry 重开 | 真实 ComposerSection 复用位置，旧操作结果不清除新 entry 的 pending、不展示旧错误 |
| 既有布局 | 原窄窗口工具栏单行、焦点恢复、权限/模式/图片输入等回归保持通过 |

`Binding.runCurrent` 在当前实现中同步读取 runtime 后才执行 callback；无 runtime 的零调用路径和请求后目标消失均有行为测试。`outcome ?? failed(providerUnavailable)` 作为防御式空返回分支保留，未为单独注入该私有分支新增生产测试接缝。

测试 fake 的配置目录随 typed event 更新，不使用永远为空的旧 stub。Widget 中的 runtime 失效通过 `tester.runAsync` 等待真实异步清理；复用同一 fake 的 global/session 流在 registry/Binding 关闭后统一收尾。测试调度器、选择器、分片和并发配置未改动。

## 3. 本次验证

| 命令/检查 | 结果 |
|---|---|
| `dart format .` | 通过，1092 个 Dart 文件 |
| `flutter analyze` | 通过，0 issues |
| 两个定向文件 | 54 条通过；application 配置命令 29 条，Composer toolbar 25 条 |
| `bash tool/test_affected.sh -- --reporter expanded` | 通过，925 条；选中 126/304 个根测试文件，含常驻与 Agent 架构守卫 |
| `dart run tool/check_localized_ui_strings.dart --check` | 通过，0 个新字面量、0 allowlist 项 |
| ARB key/placeholder 对齐、生成文件 | `flutter gen-l10n` 已执行；1043 个 key 及 placeholder 对齐；相关 contract 测试通过 |
| `git diff --check` | 通过 |
| 计划与阶段记录本地链接 | 8 份文档、22 个本地链接通过，无失效链接 |
| 依赖/协议/持久化范围 | pubspec、lock、packages、third_party、tool 与原生目录无改动 |

WP-6 是局部行为修复，按总入口 §5.1 使用定向与受影响测试，未执行 `test_full.sh`；最终整合仍要求全量。未执行真实 CLI 或 Windows/Linux 人工验收，未据此声明跨平台实机通过。本次没有 Provider 协议或原生桌面改动。

## 4. 后继与回滚

WP-2 保留本阶段的 executor 结果分类、队列与控件行为；将 Section 回调改为 Actions，并把 `invokeSessionConfigCommand` 的翻译迁入统一 runner 后删除该临时 helper。WP-3 的单 owner 迁移尚未开始；本阶段不提前移动状态所有权。

本阶段无持久化格式迁移，可整体回滚实现提交；WP-2 接入后按工作包既定逆依赖顺序回滚，不只撤方法签名。

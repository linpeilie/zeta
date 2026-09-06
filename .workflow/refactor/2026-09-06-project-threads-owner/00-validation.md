# WP-3P · Project Threads owner 验收记录

状态：已完成，全部收尾门禁通过。实现提交见总入口。

## 1. 基线与范围

- 执行日期：2026-09-06；分支 `dev`；开始 HEAD `70a2dc8e`，工作区干净。前置 WP-4 `11c6d9c8`；WP-3M `62a16ed6` 与验收登记 `70a2dc8e`。
- 读取总入口、WP-3 §5/§7/§9、WP-4 与 M 验收记录、工程规范状态/生命周期章节；`docs/prompts/refactoring.md` 仍缺失，遵守 AGENTS 的重构全量门禁。
- 范围为 Project Threads 单 owner、执行排空、共享资源装配及真实 Shell/Widget 接线。未改 Provider 协议、依赖版本、String threadId、v4 持久化、reducer/intent/effect、分页与能力规则；Workspace/Conversation 的 owner 和完整 Shell 前移仍待 C。

## 2. 最终实现

- `ProjectThreadsSliceNotifier` 是唯一应用级 owner，非 family、非 autoDispose，独占状态、同步规则、thread → project 索引、OperationId waiter。build 用 `ref.read` 冻结 initialState/now/generator/factory，从初态建立索引后创建真实 runner，不在 build 前读 Notifier.state。
- 删除旧 Store、presentation 镜像和 Deferred。Widget 直接读取 selector，Shell 通过 `ProjectThreadsOperations` 发命令，通过真实 Riverpod subscription 接收变更；没有第二份状态或 Widget 回填 owner。
- `subscribe` 从 StateOwner 移到 app 订阅资源；Operations 不再暴露 dispose，生命周期走独立 `ProjectThreadsOwnerLifecycle`。选中项移除经过 `activeThreadCleared` 具名 ingress，Shell 构造完安装回调、卸载时解除。命令签名与业务结果不变。
- Runner 仍公开 void run / close，新增 drainExecutions。每个脱离 await 链的启动点先登记执行 Future 再调用任务，覆盖同步回流与重入 close；await 链中的内部任务不另建账本。关闭只取消 Timer/失效 token，不能提前清空执行集合。
- 恢复、激活、搜索防抖已经触发的无 waiter 查询，以及 initial/more/toggle/archived/rename/archive/unarchive/delete/fork 均跟踪至物理终态。停止后不再发下一页或 fork；既有 I/O 没有取消能力时等待原完成。整批等待 eagerError=false，缓存同一 drain Future，意外诊断只输出固定分类。
- caller 与执行分离：关闭时 void 正常完成、fork 为 null；真正业务失败保留原 error/stackTrace，未知/重复回执按原 stale 规则处理。迟到 ingress 不写已关闭 state/index，不触发 Shell 回调。
- app 的 `agentConversationBindingManagerProvider` 与 `agentProviderGlobalRuntimeProvider` 提供共享资源；Shell 不再创建/关闭 registry/global/manager，Workspace 不再有 manager fallback。文本目录冻结后、Widget 前创建 Project Threads owner；shutdown 先 stop M/P、等待全部真实执行，再 manager → registry → plugin → container。
- 额外封住 native shutdown 早于异步语言解析的竞态：关闭标记立即生效，迟到解析不能再创建 owner/manager。

## 3. 测试与断言保留

使用 Dart AST 对同名测试逐条比较 expect/expectLater token 序列，仅归一化 `.state → .current`、生命周期方法名、旧 `composition.store → controller` 与格式化尾逗号：

| 基线 | 测试保留 | 原断言保留 |
|---|---:|---:|
| WP-4 前 33 条原业务测试 | 33/33 | 131/131 |
| 本次开始的 application Store 测试 | 26/26 | 113/113 |
| 本次开始的 app Runner 测试 | 25/25 | 88/88 |

三行覆盖面重叠，不相加。源码 AST 另确认 51 个 owner 方法体与 9 个权限/排序/分页辅助方法体在状态访问名称归一化后无变化。原 codec 四条测试文件完全未变；同步用例仍断言零 Provider effect，时间仍由固定 now 注入。业务规则、排序、标题/preview、running/completed、v4 与多 Provider fork 权限断言没有删除或放宽。

新增 23 条测试：4 条 application 生命周期、15 条 app 查询/写入/根装配/早退出/同步关闭、4 条 AST owner 边界。覆盖同步回执全部命令、原错误/堆栈、工厂唯一、依赖变化与退订不重建、旧容器迟到结果、关闭两种 waiter、失败 drain 幂等、7 种查询启动来源/聚合最后一个 Provider、5 种写入、无 Widget 装配与 manager/runtime/plugin/container 关闭顺序；同步乐观重命名发布中重入 close/drain 时，未发出的远端写入不再启动。WP-4 Runner 守卫增加 drain 白名单，仍拒绝所有旧同步方法和第二份索引；新 AST 守卫有合法 selector/typed sink 正例及镜像、Deferred、Ref 回读、UI 拥有资源、借用者创建/关闭 manager 反例。

通用 Widget 测试使用 `ManualBindingSweepTimer` 注入 app sweep timer factory：只替换调度器，真实 manager/runner/owner/registry 保持生产链。原因是 Flutter 在 Widget 卸载后、应用 addTearDown 前检查 fake Timer，而 app manager 现在有意超出 Widget 生命周期。手动调度器可 fire/cancel，最终仍由 app.close 关闭；BindingManager 专项测试继续验证 idle sweep。

## 4. 验证记录

全部命令在仓库根执行，进程环境统一 `DASH__SUPPRESS_ANALYTICS=true PUB_HOSTED_URL=https://pub.dev`，不改用户全局设置或测试并发。

| 门禁 | 命令/范围 | 结果 |
|---|---|---|
| 修改前基线 | Project Threads application + app + WP-4 guard | 59 条通过 |
| 迁移回归 | 上述范围 + Shell/controller/workspace/runtime facts | 90 条通过 |
| 线程专项 | application + app + 两份 guard | 80 条通过；随后补早退出及同步关闭回归，app 40 条通过 |
| Widget 与守卫 | Shell Widget、Project Threads Widget、session restore、layering、hygiene，加 owner lifecycle/guard | 73 条通过 |
| Binding 结构守卫 | app → registry/manager → Shell 借用，保留旧 Factory 禁用 | 12 条通过 |
| 断言审计 | Dart AST 按同名测试和断言顺序比较 | 33/131、26/113、25/88 全保留 |
| format | `dart format .` | 1110 文件，0 改动 |
| analyze | `flutter analyze` | 退出 0，No issues found |
| affected | `bash tool/test_affected.sh -- --reporter expanded` | 退出 0；删除/改名触发全量：根 2047 条 + 内部包 1076 条通过，10 个包分析通过 |
| full | `bash tool/test_full.sh --reporter expanded` | 退出 0；根 2047 条 + 内部包 1076 条通过，10 个包分析通过；根 JSON 报告 success=true |
| 空白/范围 | `git diff --check`、锁文件/包目录/并发/session/reducer 核验 | 通过；依赖、所有 packages、并发、codec、intent/effect/reducer 无 diff |

最终完整门禁合计 **3123** 条。内部包分别为 core 7、api 3、Claude Code 345、Codex 175、Grok 193、SDK 74、foundation 32、markdown 208、kernel 23、UI 16，合计 1076。新增文档链接有效，无初始用户改动被覆盖或混入。

开发中修正了测试装配和新用例的编译/格式问题。首轮 Widget 回归受 app Timer 生命周期变化影响失败，已用注入调度器修正测试装配并重新通过，未为通过测试让页面重新拥有 manager。首轮 affected 另发现一条历史结构守卫仍要求 IdeHome 传工厂给 Shell，已改为检查 app registry/manager 的实际资源链，保留禁止旧 Factory 的负向断言，12 条专项通过。新早退出与同步重入测试属于关闭路径补强，不改变语言选择或用户数据。

原始运行日志在 `/tmp/zeta-wp3p-*.log`，不提交报错原文或运行快照。真实 CLI、macOS 手工工作台退出和 Windows/Linux Profile 未执行；自动化通过不作为平台实测证据。

## 5. 文档与交接

同步 AGENTS、工程规范、设计文档、双语概览、开发指南、双语 CONTRIBUTING 和旧计划后继引用。生命周期接口在本计划 §5.5 记录；未增加领域术语、门禁编号或用户界面功能，glossary/CLAUDE/CHANGELOG 无需扩写。

下一项为 **WP-3C**：Workspace/Conversation 单 owner、稳定 entry lifetime identity、完整 Shell 装配与关闭、snapshot relay。M/P 已完成部分不得回退成镜像或保留新旧两条写路径。回滚按工作包依赖逆序撤回本次提交；无数据迁移或降级脚本。

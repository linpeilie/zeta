# WP-4 · Project Threads 验收记录

状态：已完成，全部收尾门禁通过。实现提交 `11c6d9c8`。

## 1. 基线与范围

- 执行日期：2026-09-06；分支 `dev`；开始 HEAD `55955959`，工作区干净，无需保留同期未提交文件。前置 WP-1 实现提交 `ea56f5c9`，WP-6 实现提交 `8778a8ae`。
- 生产接收者核验：`IdeShellController` 将 `projectThreadsController` 与 `projectThreadsSliceStore` 都指向 composition.store；session 登记及 runtime snapshot 同步也由该 Store 接收。Shell、Widget 接线无需修改。
- 本次只收口当前 Store/Runner；不迁 Notifier，不改 Provider 包、权限策略、操作签名、intent/effect/reducer、v4 codec、分页算法、锁文件或测试并发。
- 仓库引用的 `AGENTS.md`、`.agents/skills`、`.claude/skills` 与 `.codegraph` 当前不存在；遵守 AGENTS 明示的重构 full 要求，使用源码与 import 调用图核验。
- 当前锁文件使用 `https://pub.dev`。首次按历史配置用镜像解析造成工具生成锁文件差异，已撤销并以官方源重新解析；最终必须确认锁文件无 diff。历史镜像配置不适用于本次 checkout。

## 2. 实现与保持的行为

- Runner 删除同步业务 API、session snapshot getter、重复 thread → project map 及登记 helper；唯一公开执行方法为 `run(effect)` / `close()`，保留 callback 接线、加载 token、搜索 Timer 和纯合并 helper。
- AST token 比对确认 9 个权限解析、能力检查、分页收集和纯合并 helper 的方法体完全不变。
- Store 实现 `StateOwner.threadFor`，按当前项目摘要的第一个匹配返回，不猜活跃 Provider。Runner 远端操作读取这一入口，能力检查及 fork 权限解析保持。
- Store 初始状态与恢复重建映射，page ingress 补齐提交态映射而不丢窗口外显式登记；retain/remove 只清理相应归属；关闭后 ingress 不再写索引。
- 选中项移除先由 owner 确认，再通过组合回调。关闭、包括移除通知期间重入关闭，均不再回调 Shell。
- 保留通知时点、reducer intent 顺序、全局唯一选择、标题/preview 合并、running 晋升及后台完成提示；保留首屏 5 / 追加 10 / 每 Provider 上限 50、搜索 300 ms、v4 和裸 String id。
- 保留 OperationId 结算、远端失败原异常、缺摘要的原 null 语义；dispose 时 pending void Future 完成、fork Future 返回 null，迟到结果不二次结算。
- 不声明支持跨 Provider 同 raw id 碰撞；测试只固定既有首匹配语义及不同 id / 多 Provider 隔离。

## 3. 33 条旧测试的唯一去向

旧文件：`test/src/features/project_threads/application/project_threads_slice_runner_test.dart`（本次删除）。S 为 Store + recording runner；I 为真实 composition.store；C 为 snapshot/restore plan 纯函数。

- S：`test/src/features/project_threads/application/project_threads_slice_store_test.dart`
- I：`test/src/app/project_threads_slice/project_threads_slice_runner_test.dart`
- C：`test/src/features/project_threads/application/project_threads_session_snapshot_codec_test.dart`

| 旧行号 | 原测试名称 | 目标 | 核验 |
|---|---|---|---|
| 22 | restores expanded active project and loads first 5 threads | I | 已迁移，原断言保留 |
| 47 | loads more with aggregate cursor and appends unique threads | I | 已迁移，原断言保留 |
| 74 | keeps cached threads when reload fails | I | 已迁移，原断言保留 |
| 97 | keeps a current session when an earlier initial load omits it | I | 已迁移，原断言保留 |
| 134 | keeps local provisional title when Grok list returns same id without title | I | 已迁移，原断言保留 |
| 182 | tracks running thread ids from conversation runtime snapshots | S | 已迁移，原断言保留 |
| 227 | syncRuntimeSnapshot updates thread preview beside title | S | 已迁移，原断言保留 |
| 271 | syncRuntimeSnapshot ignores placeholder New thread title for all providers | S | 已迁移，原断言保留 |
| 327 | registerSession drops session placeholder title so list title stays empty | S | 已迁移，原断言保留 |
| 350 | promotes an existing thread to the top when a turn starts | S | 已迁移，原断言保留 |
| 406 | setThreadRunning promotes mapped thread on idle-to-running edge | S | 已迁移，原断言保留 |
| 447 | applies waiting flags from runtime snapshots to list state | S | 已迁移，原断言保留 |
| 498 | ignores duplicate loads while a project is already loading | I | 已迁移，原断言保留 |
| 517 | sorts all provider threads by global recency | I | 已迁移，原断言保留 |
| 567 | builds snapshot from current list states | C | 已迁移，原断言保留 |
| 587 | builds restore plan from session snapshot | C | 已迁移，原断言保留 |
| 609 | restore plan only keeps the first five cached threads | C | 已迁移，原断言保留 |
| 630 | restore plan keeps only one selected thread across projects | C | 已迁移，原断言保留 |
| 648 | selectThreadId clears selection in other projects | S | 已迁移，原断言保留 |
| 663 | passes archived and searchTerm to listThreads | I | 已迁移，原断言保留 |
| 685 | renames thread through global runtime and updates cached title | I | 已迁移，原断言保留 |
| 705 | removes archived thread and notifies active clear | I | 已迁移，原断言保留 |
| 727 | caches provider ownership when a session is created | I | 已迁移，原断言保留 |
| 754 | registerSession can optimistically mark the new thread running | S | 已迁移，原断言保留 |
| 774 | setThreadRunning toggles list busy indicator for mapped threads | S | 已迁移，原断言保留 |
| 798 | background turn completion marks completed icon until dismissed or selected | S | 已迁移，原断言保留 |
| 852 | syncRuntimeSnapshot keeps multiple background thread states | S | 已迁移，原断言保留 |
| 910 | selected thread turn completion clears list busy when status lags active | S | 已迁移，原断言保留 |
| 972 | setThreadRunning false clears sticky active status on list summary | S | 已迁移，原断言保留 |
| 1010 | syncRuntimeSnapshot keeps waiting flags while turn still active | S | 已迁移，原断言保留 |
| 1045 | fork makes provider default source explicit when no pane is open | I | 已迁移，原断言保留 |
| 1081 | fork without Binding uses the persisted provider default | I | 已迁移，原断言保留 |
| 1134 | fork 优先使用已存在 Binding 的 thread 权限快照 | I | 已迁移，原断言保留 |

按 Dart AST 比较每个同名测试中 `expect` / `expectLater` 的 token 序列：**33 条测试各出现一次，131 条原断言按原顺序完整保留**。新增断言只加强观察点。

装配差异：15 条同步测试由 fake Provider 加载改为直接注入同等列表初态（原三条 recency 顺序仍为 2/1/0），统一使用固定 `2026-09-06 UTC` 时钟及 recording runner，并在 teardown 断言零 Provider effect。原有两条晋升时间宽泛断言保留，额外精确断言注入时刻；session 创建/更新时间也精确验证。14 条 I/O 测试经真实 Store → effect → Runner → owner 回流，保留多 Provider fixture 和全部权限请求参数断言。Grok 新 session 所属测试额外发起真实重命名，确认调用 Grok、未调用当前默认 Codex。

新增 14 条行为回归涵盖初态/selected-only 索引、restore/page/窗口外映射、retain、首匹配查询、remove、close/late ingress/Future、search 取消、回调重入关闭、远端错误及缺摘要不猜归属。新增 4 条 AST 结构守卫含生产扫描、合法调度正例、所有删除业务方法负例及改名索引负例。

## 4. 验证

所有命令在仓库根执行；收尾依赖解析统一 `PUB_HOSTED_URL=https://pub.dev`；内部包分析使用仅对命令进程生效的 `DASH__SUPPRESS_ANALYTICS=true`。

| 检查 | 实际命令 | 退出码与结果 |
|---|---|---|
| 修改前窄基线 | `flutter test test/src/features/project_threads/application test/src/app/project_threads_slice --reporter expanded` | 0；41 条通过 |
| 迁移及新增行为/结构守卫 | `flutter test --no-pub test/src/features/project_threads/application test/src/app/project_threads_slice test/src/architecture/project_threads_state_owner_guard_test.dart --reporter expanded` | 0；59 条通过 |
| Shell/Widget/恢复及分层 | `flutter test --no-pub test/src/app/ide_shell_controller_test.dart test/src/features/project_threads/presentation/project_threads_widget_test.dart test/src/features/ide_session/presentation/ide_session_restore_widget_test.dart test/src/architecture/feature_layering_guard_test.dart --reporter expanded` | 0；45 条通过 |
| format | `dart format .` | 0；1101 文件，0 改动 |
| analyze | `flutter analyze` | 0；No issues found |
| affected | `bash tool/test_affected.sh -- --reporter expanded` | 0；删除旧 Dart 测试触发根全量 2007 条 + 10 个内部包 1076 条；所有分析通过 |
| full（含内部包） | `bash tool/test_full.sh --reporter expanded` | 0；根 2007 条、10 个内部包 1076 条通过；内部包分析全部通过；根 JSON 报告 success=true |
| whitespace | `git diff --check` | 0；无空白错误 |

首轮 affected 因删除旧 Dart 测试文件自动升级根全量及所有内部包：根 2007 条和内部包 1076 条测试均通过，但 6 个纯 Dart 包的分析器在遥测连接 `google-analytics.com` 时抛 SocketException，命令退出 1。使用当前 unified_analytics 源码确认的进程环境开关 `DASH__SUPPRESS_ANALYTICS=true` 后，SDK 包单独 `dart analyze` 退出 0、No issues found；未改用户全局设置或仓库配置。完整门禁与 affected 重跑使用同一临时设置，最终结果另见上表。

开发中已修正测试装配残留参数、固定时钟变量及 fake fork 默认参数；结构守卫按当前 analyzer 12 的 ClassNamePart / ClassBody API 实现。首次 analyze 发现迁移后两个多余 import，已移除。未减少业务断言，也未修改生产权限或分页逻辑以迁就测试。

最终范围核验：`pubspec.yaml` / `pubspec.lock` / `dart_test.yaml`、全部 `packages/`、IDE session v4、Project Threads operations / intent / effect / reducer / composition 及 Shell 均无 diff。无初始用户修改被覆盖或混入。新增 Markdown 链接与 33 行迁移清单有效。

内部包通过数：agent_core 7、provider_api 3、Claude Code 345、Codex 175、Grok 193、provider_sdk 74、foundation 32、markdown 208、plugin_kernel 23、ui 16，合计 1076；与根 2007 合计 **3083**。

未运行真实 CLI 或桌面 Profile：本次未改协议、UI 渲染或性能路径；自动化结果不作为真实 CLI 版本兼容的新证据。

## 5. 文档与交接

同步 AGENTS、工程规范、设计文档、中英文概览、开发者文档及中英文 CONTRIBUTING；修正工程规范中错误的 `Runner.registerSession` 接收者说明。未新增术语或门禁编号，glossary / CLAUDE 无需改动；纯重构不写 CHANGELOG。

WP-3P 接收已经唯一的 Store 业务和测试契约；现有 listener、presentation 镜像、Deferred 未删除。按总队列下一任务是 WP-3M，随后 WP-3P；不得将本次完成解释为 WP-3 已完成。

可整体回退本工作包提交；不迁移或删除用户数据。后续 WP-3P 开始后应按依赖逆序回退，不能拼回 Store/Runner 双业务入口。

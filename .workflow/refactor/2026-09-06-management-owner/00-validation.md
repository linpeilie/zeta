# WP-3M · Management owner 验收记录

状态：已完成，全部收尾门禁通过；实现提交 `62a16ed6`。

## 1. 基线与范围

- 执行日期 2026-09-06；分支 `dev`；开始 HEAD `3afb87e9`，工作区干净。前置 WP-4 `11c6d9c8`、WP-1 `ea56f5c9`、WP-6 `8778a8ae` 已登记并核对。
- 本次只执行 WP-3M；不推进 WP-3P/C、WP-2 或 WP-5。保留现有 Project Threads/Conversation 的 Store、Deferred、registry 和 Shell 构造位置。
- 不修改 Provider 包、协议、权限、依赖版本、持久化格式或测试并发；management operations 的签名、state、intent、effect、reducer 保持原语义。
- 仓库引用的 `AGENTS.md`、`.agents/skills`、`.claude/skills` 和 `.codegraph` 当前不存在；执行 AGENTS 明示的完整重构门禁，不初始化额外工具。

## 2. 生产接线与生命周期

- `AgentManagementSliceNotifier` 是 application 单一 owner，非 family、非 autoDispose；保存原分类型 Completer 和 operation 校验。删除旧 Store、presentation Notifier 镜像、Deferred 和旧 management composition 类。
- `AgentManagementSliceDependencies` 与 Runner factory 在 build 用 `ref.read` 冻结；重复 build fail-closed。Runner 构造只捕获具名 `AgentManagementResultSink`，不持 Ref 或具体 Notifier。
- app 的 `AgentManagementCompositionInputs` 收集已激活并校验的贡献，冻结 repository/定义/设置端口/文本目录；空集、重复、身份冲突继续拒绝。独立 ingress provider 只持源订阅，不持第二份 management state。
- 根组合在 Widget 之前创建 owner、接入设置并调用 initialize。Page/Editor/LogView 从 provider 读取状态和 Operations；Settings 只传页面可用性，删除 Store/Operations 构造参数。配置编辑内容、dirty、搜索、焦点、确认弹窗仍属于 Widget。
- M 阶段接缝校正：Shell 仍由 IdeHome 创建，首次事实订阅在挂载后进行，先订阅再同步重读 current，不丢订阅前事实；实时回流不增加镜像或微任务缓存。Shell 卸载先释放借用订阅，再关 source 和 Workspace；管理 owner 继续存活。多个借用者共享订阅，最后一个释放只退订，同源立即重接可用。完整 Shell 前移和根快照 relay 删除仍归 WP-3C。
- 8 个 Runner 分支返回真实执行 Future。每项执行在调用 Runner 前登记完成桥，桥仅随真实 Future 完成；同步回流期间重入 stop/drain 也不会漏记。探测包含已发出的摘要写入；日志包括 discover 和 read；关闭后不启动下一 Provider/下一 I/O 步骤，已发出的写入按真实终态等待。
- `stopAcceptingCommandsAndSettleWaiters` 立即拒绝新命令、以原 `AgentManagementSliceStore is closed` StateError 结算所有等待者，不清物理执行集。具名 ingress 在读取 state 前检查 closed，旧 sink 不解析新 owner。
- `drainExecutions` 等待实际 I/O，失败批次也先等待其他已启动执行；重复调用复用同一 drain Future。仅固定分类报告意外执行异常，不记录错误对象、堆栈、配置值或原文。
- app shutdown 先 stop、退订管理输入、await drain，再 runtime registry → plugin catalog → container.dispose。`close()` 与 shutdown 均缓存 Future；同步 `dispose()` 启动同一关闭过程。失败不提前销毁容器。测试公共 teardown 改为等待 `composition.close`。

### Runner 回流矩阵

| effect 分支 | 具名结果入口 | 调用方失败语义 |
|---|---|---|
| initialize | initializationSucceeded / initializationFailed | 原 error + stackTrace；可重试 |
| detect | detectionStarted / detectionProgressReported / agentDetected / detectionCompleted / detectionFailed | 现有可展示错误，void 正常结算 |
| enabled | providerEnabledUpdated / providerEnabledUpdateFailed | 现有错误与回滚，void 正常结算 |
| account enrichment | accountDataEnrichmentUpdated / accountDataEnrichmentUpdateFailed | 现有错误，void 正常结算；缺能力仍拒绝 |
| connection | connectionTestSucceeded / connectionTestFailed | 完整 result 或 null |
| configuration load | configurationLoaded / configurationLoadFailed | document 或 null |
| configuration save | configurationSaved / configurationSaveFailed | result 或原 error + stackTrace |
| logs | logsLoaded / logsLoadFailed | 不可变 entries 或空列表 |

Runner 的原 state.agentsById 查询只改为 sink.current.agentsById；配置验证仍同步调用原仓库。设置/事实由独立 ingress 调用 providerSettingsChanged/runtimeFactsReplaced，不创建 waiter。

## 3. 原断言与新增回归

按 Dart AST 比对同名测试的 expect/expectLater token（只规范化 `store.state` → `store.current`、关闭方法改名和可选末尾逗号）：

| 原测试文件 | 原测试声明数 | 保留原断言的声明数 | 保留断言数 |
|---|---:|---:|---:|
| application `agent_management_slice_store_test.dart` → `agent_management_slice_notifier_test.dart` | 7 | 6 | 26 |
| presentation `agent_management_slice_page_test.dart` | 3 | 3 | 19 |
| presentation `agent_management_page_test.dart` | 10 | 10 | 74 |
| app `agent_management_slice_runner_test.dart` | 1 | 1 | 14 |
| 合计 | 21 | 20 | 133 |

唯一原预期调整是 O-04：`cold initialization can retry after a listener throws` 原来断言 listener 异常使 effect 不执行；现按设计改为 `listener errors do not suppress initialization or dispatch twice`，断言错误仍可观察、初始化共享 Future、业务 effect 一次且正常结算。不是为了通过测试降低断言。插件贡献拒绝测试改在 eager root 创建边界断言，经 Riverpod 包装后仍核验最内层原 StateError；原空表、重复、错身份输入均保留。

新增 13 条行为回归：同步回流/重复 ingress、原初始化与保存错误及堆栈、typed fallback/重复短路、设置/事实变化与 UI 退订不重建 owner、旧容器销毁后同序号旧结果隔离、关闭各类 waiter、账户增强失败/关闭、重入 stop/drain、排空失败缓存，以及真实 Runner 的探测持久化、两段日志与 app 无 Widget 初始化/保存排空/资源关闭。另增 4 条 AST 守卫，含生产扫描非空、合法 selector/Widget State 正例、改名镜像/旧 Store/UI 回写或关闭、Runner Ref/owner/隐藏执行负例。

开发发现并修正：

- 日志子页 initState 发命令会触发构建期写保护；由“查看日志”的用户动作先发起加载，原首帧断言保留。
- Shell initState 同步接入事实触发 Riverpod 写保护；改为仅首次连接在挂载后执行，source 先订阅再重读，owner/Runner 的同步结果不延迟。
- 同一 source 的 provider 尚未自动回收时立即重接，不能复用已永久关闭的订阅；用借用计数和独立 disconnect/close 修正。
- 通用 Shell Widget 测试原贡献工厂调用真实 CLI 探测仓库，旧同步 dispose 没有等待在途 I/O；改为 `memoryManagementContribution` 只替换外部管理 I/O、保留插件 identity/capability 元数据。专门的 Codex 配置编辑测试仍使用真实 repository + 临时目录，生产 owner/Runner 接线没有测试分支。

- 首轮受影响检查发现 3 条本地化夹具问题：内存探测需提供已安装样本以保持原列表分支，测试容器关闭前需先卸载仍由 Widget 持有的 Shell。修正外部样本及 teardown 顺序，3 条原本地化测试全部通过，原文案断言未调整。另一个测试卫生守卫要求 root 测试显式覆盖 bundle factory；在已覆盖 fake registry 外补上相同 factory，未放宽守卫。

## 4. 验证

根目录执行；每个命令仅进程内设置 `DASH__SUPPRESS_ANALYTICS=true PUB_HOSTED_URL=https://pub.dev`，避免分析器遥测网络失败，并与当前锁文件的 pub host 一致。

| 检查 | 命令 | 结果 |
|---|---|---|
| 修改前基线 | `flutter test --no-pub test/src/features/agent_management test/src/app/agent_management_slice --reporter expanded` | 0；45 条通过 |
| 定向、Shell、插件及 owner 守卫 | `flutter test --no-pub test/src/features/agent_management test/src/app/agent_management_slice test/src/app/ide_shell_widget_test.dart test/src/app/plugins/fake_agent_provider_plugin_e2e_test.dart test/src/architecture/agent_management_owner_guard_test.dart --reporter expanded` | 0；101 条通过 |
| format | `dart format .` | 0；1105 个 Dart 文件 |
| analyze | `flutter analyze` | 0；No issues found |
| affected | `bash tool/test_affected.sh -- --reporter expanded` | 0；删除旧 Dart 文件触发根全量 2024 条 + 10 个内部包 1076 条，分析全部通过 |
| full | `bash tool/test_full.sh --reporter expanded` | 0；根 2024 条 + 内部包 1076 条，10 包分析全部通过；根 JSON 报告 success=true |
| whitespace / 范围 / 链接 | `git diff --check` 及文件范围/Markdown 链接核验 | 通过；原文档的 `[$name](path)` 是示例占位，不是新增失效链接 |

内部包通过数：agent_core 7、provider_api 3、Claude Code 345、Codex 175、Grok 193、provider_sdk 74、foundation 32、markdown 208、plugin_kernel 23、ui 16，合计 1076。当前根 2024 + 内部包 1076 = **3100**。

最终范围核验：`packages/`、`pubspec.yaml`、`pubspec.lock`、`dart_test.yaml`、Management state/intent/effect/reducer 均无 diff。

未运行真实桌面手动验收、真实 CLI 或 Windows/Linux Profile；自动化切页/后台运行/冷启动与关闭测试不作为新 CLI 兼容或桌面性能证据。

## 5. 后继任务

同步 AGENTS、工程规范、设计、中英文概览/术语表、开发者文档、中英文 CONTRIBUTING 与旧计划后继引用。无门禁编号变化，CLAUDE 无需调整；纯重构不新增 CHANGELOG。

下一项是 **WP-3P · Project Threads owner 迁移**。WP-3M 的唯一 Notifier、具名结果/冻结输入与真实执行排空是后继模式；WP-4 的原同步规则与索引不应重复搬回 Runner。WP-3 整体尚未完成，Shell/Workspace/Conversation 的完整所有权与退出协调仍待 WP-3C。

回滚按 M 阶段提交整体撤回；后续 WP-3P/C 或 WP-5 已依赖时按逆序回退。不改变用户数据，也不保留两套 owner 作为切换开关。

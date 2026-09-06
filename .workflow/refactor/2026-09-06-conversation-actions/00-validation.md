# WP-2 · Conversation Actions 验收

> 日期：2026-09-06；基线 `2a6d956e`（WP-3C 文档登记），开始时工作区干净。实现提交：`16cba246`。状态：已完成。

## 1. 范围与调用链

UI/Shell 用户衍生命令 → 捕获的 `AgentConversationActions`（同一个 Notifier）→ 冻结 payload/OperationId/lifetime/scope → 纯 reducer → scoped runner → RuntimeController/executor → typed result sink → 唯一 waiter/账本结算。

35 个 Actions 覆盖原按钮与公开能力；四类审批 admission 独立，相同 scope 多个操作独立结算。同步展开在原调用栈执行。权限偏好在 runner 局部队列串行，WP-6 同 config key 队列保持；关闭清空队列并结算全部 UI Future，不声称撤销已发 I/O。捕获句柄关闭后无法重定向到重开的 entry。

发送冻结图片、mentions、skills、权限快照与 Unicode 原文；请求与回答的嵌套集合同样冻结。Start/Revise 独立，null revision 保持继续规划。模型逐保存 revision 回报真实成功/失败/覆盖，不读较新 saveError 推测旧请求。fork 的 createdSession 只在内存返回，激活失败保留产物；Shell 新 entry 初始发送回传 outcome。

## 2. 行为修正与边界

1. 旧模型 bool/null 断言改为精确 outcome；不削弱保存、回滚、顺序或权限断言。
2. 同步展开也登记并当栈结算 OperationId，旧 reducer 的“不登记”结构断言按设计更新。
3. Closed Actions 返回 staleTarget Future，替代旧 StateError；既有 WP-3C keepAlive/alias/lease 释放顺序保持。
4. G5 修正：移除本地 Plan 的 first-executable 权限回退；无有效历史选择/可执行目录默认时等待显式选择。adopt 期间换代禁止发送；分支交接返回后也再次校验 source scope 才恢复源状态。仅改 application，不动 Provider 协议、core 或持久化格式。
5. 已发 fork 在关闭以后才返回时，UI Future 已完成；结果中 session=null 仅表示结算时未知，不能推断没有创建或自动重试。

## 3. 生产入口逐项签收

| 原入口 | Actions / 结果 | 回归证据 |
|---|---|---|
| Pane / Composer send | sendMessage，捕获句柄与完整字段 | actions_widget_test 双 Canvas/晋升/关闭/失败/旧 epoch；actions_test payload 冻结；原 clipboard/mention/skill Widget |
| Section cancel | cancelActiveTurn | toolbar session config pending leaves cancel available；Actions 并发 |
| 消息编辑确认 | editLastUserMessageAndRetry | Shell 真实编辑对话框及 Actions 回归：新 entry 发送失败回传，两端各执行一次，保留 fork 边界/权限/source Binding |
| Header fork | typed fork | Widget more menu 成功/激活失败各一次；Actions 产物/epoch/关闭 |
| Header archive / rename | archiveCurrentThread / renameCurrentThread | `skill picker and header archive enter the same real Actions owner`；`renames the current thread from the header more menu` |
| Slash compact | compactCurrentThread | `slash Compact invokes the current thread mutation port` |
| Permission / Question | 独立 respondToPermission / respondToQuestion | 真实卡片重复点击、同 id、Skip；Actions 嵌套冻结 |
| Guardian override | approveGuardianDeniedAction | Actions 完整映射；原 Guardian 回归 |
| Provider Plan Approval 三种决定 | respondToPlanApproval，保留 reason | `renders and accepts an independent plan approval card`；`审批卡的修改把意见随 rejected 决定回传 Provider`；四类 admission/透传 |
| 本地 Plan 权限选择 | selectPlanExecutionPermissionOption | `执行权限可为本次覆盖且不会提前 apply 或持久化`；Actions 同步映射 |
| 本地 Plan revise/start/dismiss | 三种独立 payload | null revision 单测；`completed Plan shows local handoff and Run plan starts Default turn`；`放弃关闭交互卡，计划消息退回折叠卡并恢复 Composer` |
| Plan panel | toggleActivePlan | `shows a responsive active plan above the composer and preserves expansion`；Actions 完整映射 |
| command/file/tool cards | 三个 toggle Actions | `groups historical tools and searches into a collapsed command set`；`renders tool calls, approval cards, and approval responses`；Actions 当栈执行 |
| Plan message | togglePlanMessage | `renders plan messages as collapsible markdown cards`；Actions 完整映射 |
| Toolbar / slash mode | selectConversationMode | `more actions opens above composer and Plan configures the next turn`；原快捷命令回归 |
| Composer 六个模型操作 | 选择/冲突/保存重试/清 transient | `model config resolves Fast and xhigh conflict explicitly`、`model config rolls back failed save and retries inline`；逐 waiter 回归 |
| Plan 历史/上下文模型选择器 | 同一六个 Actions | AST 覆盖 card tear-offs；原 Plan/模型 Widget |
| 权限偏好 / 保存重试 | selectPermissionOption / retryPermissionPreferencePersistence | 局部队列/原权限测试；hint 沿用 region，删除破坏性 UI 读取 |
| Session config | selectSessionConfigOption | WP-6 全套，缺端口经真实 owner 翻译；旧翻译器移除 |
| Skill picker 预热 | ensureSkillsCatalog | `skill picker and header archive enter the same real Actions owner`；候选项选择回填 Composer |
| Shell Provider switch / retry open | 目标 entry Actions | 原 Shell/两 Provider 回归 |
| Shell 新 entry 初始发送 | 新 owner sendMessage | 编辑后发送失败回传及目录保留 |
| bootstrap / 非 UI 公共目录 | loadModels / retryConversationModes | bootstrap 内部调用有注释；公开 Actions 映射；未来 UI 禁用 executor |

测试路径均位于 `test/src/features/agent/`，Shell 位于 `test/src/app/ide_shell_controller_test.dart`。新 AST 守卫覆盖全部 presentation Dart 文件、调用/tear-off/别名、provider 依赖、RenderContext 独立字段、runner 双校验与禁止持 Ref；负例证明会失败。

## 4. 验证记录

环境：`DASH__SUPPRESS_ANALYTICS=true PUB_HOSTED_URL=https://pub.dev`。保持 dart_test concurrency=2；依赖、packages、协议与存储格式不得出现 diff。

| 门禁 | 结果 |
|---|---|
| 改前基线 | reducer + owner 21 条通过 |
| 开发回归 | 原 reducer/owner 21 条基线；中途定向 275 条通过，补充异常与真实对话框后以受影响/全量为最终覆盖 |
| format / analyze | 格式化完成；静态检查 No issues found |
| 受影响测试 | 87 个测试文件（import 闭包 54、常驻守卫 21、Agent 守卫 16，去重后 87），最终 778 条通过 |
| 完整门禁 | 最终 `bash tool/test_full.sh --reporter expanded` exit 0；根 2,087 + 10 个内部包 1,076 = **3,163** 条通过；所有包 analyze 通过 |
| localized checker / ARB | literal checker 通过；两语言 1,043 个 key、205 个 placeholder 名称与类型对齐 |
| 原断言审计 | 281 个原测试声明均保留，1,497/1,526 条原断言保留，29 条调整逐项登记于 [审计](01-assertion-audit.md) |
| 依赖与范围 | packages、pubspec.yaml/lock、dart_test.yaml 无 diff；无协议或存储格式改动 |
| diff / 文档链接 | diff --check 通过；15 份变更 Markdown 的 165 个真实本地链接可解析，代码围栏闭合（排除指南的内联协议语法示例） |

真实 CLI、macOS 手工退出与 Windows/Linux Profile 未执行，保持待验证，不将自动化结果替代平台实测。

完整门禁根报告为 `.dart_tool/test-results/full.json`，末事件 success=true，2,087 个非隐藏成功结果，failure/error 均为 0。根用例较 WP-3C 的 2,060 条增加 **27 条**：Actions 13、AST 守卫 3、真实 UI 5、模型结果 3、Shell 失败/对话框 2、fork 激活失败 1。内部包计数：core 7、api 3、Claude 345、Codex 175、Grok 193、sdk 74、foundation 32、markdown 208、kernel 23、ui 16。

最终格式化 1,125 个 Dart 文件，最后一次 0 改动；`flutter analyze` 无问题。最终日志：`/tmp/zeta-wp2-analyze-final.log`、`/tmp/zeta-wp2-affected-final.log`、`/tmp/zeta-wp2-full-final.log`、`/tmp/zeta-wp2-localized-final.log`。以最终运行记账，中途补测试前的门禁不计入上述总数。

## 5. 交接与回滚

完整门禁已通过，下一项为 WP-5 首页探测。回滚按整个 WP-2 提交撤回 Actions/UI/typed result/测试，保留 WP-3C 与 WP-6 的独立边界；无数据迁移，不长期保留双命令入口。

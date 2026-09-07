# WP-3C · Workspace / Conversation owner 验收记录

状态：已完成，全部收尾门禁通过。实现提交 `c2197f76`。

## 1. 基线与范围

- 2026-09-06，分支 `dev`，开始 HEAD `59837d63`，工作区干净。前置 WP-3P `c2a5219d`、WP-3M `62a16ed6`、WP-4 `11c6d9c8`。
- 已读总入口、WP-3C 与前置验收、AGENTS、工程规范状态/生命周期及 Conversation 接入章节。`AGENTS.md` 仍缺失，执行 AGENTS 明文要求的重构全量门禁。
- 只改根应用的状态发布、装配、entry 生命周期、页面恢复及对应测试/文档。不改 Provider 私有协议、packages、依赖或 lock、并发、session v4 持久化格式；Conversation intent/effect/reducer 与核心 TimelineStore 不变。Workspace reducer 仅增加 aliases 透传。

## 2. 最终生产链

- `AgentConversationWorkspaceNotifier` 直接持有 entry 资源表与不可变 state，entry 包含固定 Binding/controller 和 `AgentConversationOwnerKey(entryId, lifetimeToken)`。草稿晋升保留 ownerKey，BindingKey 的旧 draft 与 current thread alias 同时指向该 owner；重开分配新 token，旧 token 回收不会删除新 alias。
- application `AgentConversationSliceNotifier` 是轻量 regions/命令账本的唯一发布者。build 冻结 deps，直接把 typed sink 交给 Runner；不持 Store、手写 listener 或镜像。旧 WorkspaceStore、SliceStore、两个 registry、presentation 镜像、旧 workbench typedef 与 Shell snapshot relay 已删除。
- Closing/Closed selector 返回无正文、无能力的空投影；Unknown 返回 unavailable。真实 owner 关闭同步清空 pending/regions/executor 引用、停止 Runner，迟到结果不读取已失效 Ref。WP-3C 沿用旧 OperationId 契约，尚无 WP-2 Actions waiter；UI 命令仍走既有 executor，不能将此阶段登记为命令统一。
- lifetime coordinator 在同步通知前缓存 close Future，重复/重入关闭复用同一 Future。顺序为 mark Closing → close ingress → 撤下可见项 → 退订 snapshots → dispose controller → await lease release → 清理 entry/标 Closed → 标记释放完成 → 撤销保留订阅。失败停在 Closing，保留同一失败 Future；closeAll 尝试所有 entry，成功项不被失败项阻塞。lease release 只释放 consumer，CLI 退出以 registry close 为准。
- `workbenchSessionProvider` 仅构造完整 Shell，root 在语言冻结后、Widget 前显式启动 facts/management ingress/Shell.start。Shell 构造无启动副作用，start 幂等；IdeHome 只借用已有实例与 UI 订阅。snapshot 按需读取各 owner 的白名单字段，不缓存正文、不需要 Widget bind。
- root close 在通知前缓存 Future，捕获既有资源的关闭函数，先 stop Shell/M/P，再 flush session 保存、drain M/P 实际执行、停止事实消费者与 source、await 全部 entry，最后 manager → registry → plugin → container。失败不销毁容器掩盖未完成资源；Shell 迟到恢复/创建回调拒绝继续创建或发送。

## 3. 实施修正与附加接缝

**显式保活后的空投影回收。** 初版按计划使用非 autoDispose family；无 Widget 连续开关用例发现普通 family 的 invalidate 会清状态但仍保留 family element。已核验当前 lock 的 Riverpod **3.4.3**：`ProviderElement.invalidateSelf` 调用 `mayNeedDispose`，后者只调度 autoDispose provider。因此改成 autoDispose family + build 内 keepAlive + coordinator 容器级订阅。保活只在 lease 成功且空投影无人观察时撤销，再 invalidate；失败和 live entry 始终保活。这是对计划伪代码的明确修正，不把业务资源交给观察人数决定。25 次循环断言真实 family 节点、aliases、owner handles、完成标记和 close futures 全部不累积。

**页面重挂恢复。** Runtime 原先可常驻，但 Composer 草稿/scroll 仅存在 Widget 中。新增 presentation 内存 `AgentPaneRetention`，以弱 controller 身份保留文本/token/附件/滚动；entry 关闭清除并拒绝旧 Widget 写回。焦点、popover 与 IME composing 不保留，草稿不进 app persistence。右栏宽度/显隐采用只含 UI 布局值的会话内存；左栏沿用既有 session 状态。

**测试调度器。** 应用现在先于 Widget 创建且晚于 Widget 关闭。session save Timer 与 elapsed ticker 增加外部工厂接缝，Widget 测试注入 FrameDrivenAppTimer/FrameDrivenAgentElapsedTicker；正常生产实现不变。Binding idle sweep 沿用 WP-3P 手动调度器。语言和第四插件测试额外推进 1ms，排空挂载前创建的 Riverpod 回收任务；不删除 Timer 检查，不让 Widget 重获资源所有权。通用测试 fixture 最终 await app.close；关闭失败用例先断言失败与容器可检查，再单独清理 fixture。

## 4. 回归与断言审计

Dart AST 对本次改动的旧测试逐项匹配 expect/expectLater token 序列，只归一化 `.state → .current`、明确的 owner/关闭方法名、格式化尾逗号与一条测试重命名。287 条旧测试全部保留，282 条的原断言序列完整保留；1687 条原断言中 1679 条保持原序列。其余 8 条逐项登记：

| 调整 | 数量 | 理由与替代证据 |
|---|---:|---|
| 删除 snapshot relay bind/read/dispose 断言 | 4 | 该资源已删除；白名单/不可变快照断言全部保留，新增无 Widget root snapshot 读取 |
| Store provider → slice facade、IdeHome 读 manager → 读 workbench | 2 | 生产结构入口迁移；保留 factory/scope 禁用与真实 owner 存在检查 |
| 未知 BindingKey 由抛错改 unavailable | 1 | 计划明确要求退场安全空投影，覆盖不创建 runtime |
| closed header 从保留旧标题改为空 | 1 | 计划明确要求不保留内容，增加空 history 检查；迟到更新不发布的断言保留 |

关闭后发送的旧测试增加 `throwsStateError` 包装，原 pending/runner/发布断言保留。原“容器销毁镜像不释放外部 Store”改为“selector 退订不释放 owner”，两条原业务断言保持，真正 owner 由应用容器拥有。没有通过删除业务规则、权限、Provider 隔离或排序断言获得通过。

新增 **13 条**测试：10 条 app 生命周期、1 条真实 IdeHome 重挂（通过 Binding.beginTurn 持有非空 runtime 活动令牌）、2 条 AST 守卫（包含多组正反例）。

| 计划矩阵 | 证据 |
|---|---|
| O-01/O-02 | 无 Widget ready 读取全部 owners/snapshot；所有新用例通过外部 factory/release 端口 override |
| O-03/O-04 | M/P 原同步结果、listener 异常与执行账本回归保持；关闭新增同步重入 |
| O-05 | 原两 Provider/两 Canvas、后台运行与独立 region/账本 Widget 回归 |
| O-06/O-07 | draft 晋升 owner/两个 alias/pending；同 thread 重开新 token，旧结果不改新 owner |
| O-08/O-09 | 延迟 lease、重复 close、同帧旧 selector 空投影、无 UI 25 次开关回收 |
| O-10 | 真实 IdeHome 设置/统计切页与卸载重挂保持 Binding/runtime/草稿/scroll/面板宽度 |
| O-11 | 延迟 entry release 阻止 registry/container 关闭；既有 agent_resource_shutdown 回归保证 registry → plugin 顺序 |
| O-12/O-13 | 原 locale bootstrap/冻结/早退出回归；新增 runtime restart + input invalidation 不替换 owner |
| O-14 | WP-1 facts/管理与 WP-4 Project Threads 规则、codec、索引回归 |
| O-15 | entry release 和 registry 失败，重复 await 同一失败、后续阶段不伪报成功 |

AST 守卫扫描实际 owner/runner/workspace/IdeHome/Shell，拒绝旧 Store/registry、镜像、手写发布、owner watch 输入、无保活 family、BindingKey 物理 owner、UI 构造/关闭资源、runner 持 Ref、workspace 反向依赖。保留 selector/core listener 正例与各类负例；移除新增过渡 re-export，未扩大守卫白名单。

## 5. 验证记录

命令在仓库根执行，环境 `DASH__SUPPRESS_ANALYTICS=true PUB_HOSTED_URL=https://pub.dev`；不改用户全局设置。

| 门禁 | 结果 |
|---|---|
| 改前基线 | 33 条通过 |
| 首轮 Widget / 管理 / UI state | 57 条通过 |
| 非空 runtime 重挂补强 | 1 条通过，核对 runtimeIdentity/bundle 与活动令牌 |
| 最终生命周期 + Binding / owner 守卫 | 28 条通过 |
| locale + 第四插件 | 12 条通过 |
| 补充 workspace / transition / owner 守卫 | 14 条通过；最终增强的 owner 守卫 6 条通过 |
| dart format . | 1118 个文件，0 改动 |
| flutter analyze | No issues found |
| test_affected.sh | 退出 0；文件迁移自动扩大到全量：根 2060 + 内部包 1076 全通过，10 包 analyze 通过 |
| test_full.sh --reporter expanded | 退出 0；根 2060 + 内部包 1076 全通过，10 包 analyze 通过，根 JSON success=true |
| 断言审计 / diff --check / 范围 | AST 287 条旧测试、1679 条原断言保留；依赖/packages/并发/持久化无 diff |

首轮 affected 根 2051 通过/7 失败；7 项均已定位为挂载前回收调度（4）、旧 Workspace 路径（2）与新增过渡 export（1），修复后定向通过，需以最终两次全量结果为准。第二轮业务测试无失败，新增 AST 声明守卫因 analyzer 的 ClassDeclaration 使用 namePart 接口而编译失败；已改为现有守卫同一接口，6 条守卫重跑通过，并冻结代码重新执行完整门禁。各内部包前两轮全部通过。临时日志 `/tmp/zeta-wp3c-*.log` 与断言审计 JSON 不提交；最终根 JSON 报告在 `.dart_tool/test-results/full.json`。终审仅补强重挂用例的非空 runtime/活动令牌断言并定向复验；应用源码在最终两轮门禁期间无变化。

最终完整门禁合计 **3136 条**（根 2060 + 内部包 1076）。内部包依次为 core 7、api 3、Claude 345、Codex 175、Grok 193、SDK 74、foundation 32、markdown 208、kernel 23、UI 16。

真实 CLI、macOS 手工退出和 Windows/Linux Profile 未执行，记录为待执行；自动化通过不代表平台实测。

## 6. 文档与交接

同步 AGENTS、工程规范、设计文档、中英文概览/术语表/CONTRIBUTING、开发指南、CHANGELOG、计划总入口与 WP-3；旧 2026-09-03 计划只追加后继引用。门禁编号与数量未改，CLAUDE 无需同步。

下一项 **WP-2 · Conversation 统一 Actions**。必须沿用同一 owner lifetime/关闭入口与本次显式保活回收机制，把 UI 写入收口到 typed outcome/owner waiter；不得恢复 Store/registry/镜像。WP-5 首页探测仍未开始。回滚按后继依赖逆序撤回本阶段提交，无数据迁移或降级脚本。

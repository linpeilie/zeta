# Phase 3 第 3 批：Project Threads 与 Usage Statistics

> ⚠️ **历史迁移证据（Phase 4 已完成）。**
> 本文记录的是当时的迁移过程与决策，**不描述当前架构**——其中提到的过渡层、
> 燃尽清单与中间态符号多数已在 Phase 4 删除。
> 当前架构以 [`AGENTS.md`](../../AGENTS.md) 与 [`overview.md`](overview.md) 为准；
> Phase 4 的删除边界见 [`phase4_transition_cleanup.md`](phase4_transition_cleanup.md)。

> 对应 [Phase 3 开工文档 §5](phase3_slice_expansion.md) 与
> [目标架构 §15](target_architecture_riverpod_mvi_plugins_packages.md#15-迁移决策门禁)。
>
> 开工与关批日期：2026-08-23。
>
> 当前状态：**已关批**。3a Project Threads 与 3b Usage Statistics 均固定为 MVI
> 单一路径；三个旧 `ChangeNotifier` owner、两个批内 feature flag、Shell 中的 usage
> 装配链和全部 false-path 分支已删除。用户明确要求“直接进行下一阶段”，接受缩短
> 原定生产观察余量并直接执行四步节奏第 4 步；该授权不影响第 1、2 批各自的观察与
> 回滚边界。

---

## 1. 范围与不变项

本批完成两个独立 context：

1. **3a Project Threads**：列表状态由纯 Dart
   `ProjectThreadsSliceStore` 唯一持有；`ProjectThreadsController` 只执行 Provider
   查询、能力校验、写操作和搜索防抖，并通过 typed ingress 回流 store。
2. **3b Usage Statistics**：完整统计页与 Agent 用量侧栏分别由
   `UsageStatisticsSliceStore`、`AgentUsagePanelSliceStore` 唯一持有；QueryService、
   query repository、quota source 和 source registry 在 app 组合层创建。

本批没有改变：

- Codex、Grok、Claude Code 的协议、历史扫描和 Provider-local parser；
- `AgentEvent`、entryId、coalescing、Binding、runtime lease 或审批语义；
- `ide_session.json` v4、`usage_statistics_index.json` v4 及 codec；
- Project Threads 的单 Provider 上限 50、`agg:` 游标、首屏 5 条、后续 10 条、
  搜索 300 ms 防抖与 capability fail-closed 语义；
- usage 的时间窗口、报表算法、fingerprint 增量扫描、额度窗口与脱敏白名单；
- 页面视觉、路由与持久化格式。

新增业务事实：**0**。

---

## 2. 关批后的唯一装配

### 2.1 Project Threads

```text
IdeShellController
  └─ ProjectThreadsSliceComposition
       ├─ ProjectThreadsSliceStore       # 唯一列表 owner，纯 Dart listener
       └─ ProjectThreadsController       # effect/query runner，无列表状态
            └─ Provider ports / global runtime / BindingManager

IdeHome ProviderScope
  └─ projectThreadsSliceStoreProvider    # 必须由组合层覆盖，缺失即抛错
       └─ projectThreadsSliceProvider     # 只读镜像，不复制 owner
            ├─ ProjectListPane
            └─ ProjectHomePage
```

`ProjectThreadsOperations` 是 Shell 的稳定操作端口；
`ProjectThreadsStateOwner` 仅是 runner 写入 typed 结果的 application 端口。Riverpod
adapter 只订阅、投影，不关闭 store、runtime、Binding 或 plugin。

### 2.2 Usage Statistics

```text
MainApp / UsageStatisticsSliceComposition
  ├─ AgentUsageQueryService
  │    ├─ enabled Provider loader
  │    ├─ GlobalRuntimeAgentUsageQuotaSource
  │    └─ BuiltInAgentTokenUsageSourceRegistry
  ├─ QueryUsageStatisticsRepository
  ├─ QueryAgentUsagePanelRepository
  ├─ UsageStatisticsSliceStore + runner
  └─ AgentUsagePanelSliceStore + runner

IdeHome ProviderScope
  ├─ usageStatisticsSliceStoreProvider   # 必须覆盖，缺失即抛错
  └─ agentUsagePanelSliceStoreProvider   # 必须覆盖，缺失即抛错
       ├─ UsageStatisticsPage selectors
       └─ AgentUsagePanel selectors
```

enabled Provider loader 优先读取已存在的 Provider Settings slice；该 slice 尚未创建时，
直接读取同一个 `AgentProviderConfigStore`。它不会为读取目录额外创建 Provider settings
owner，也不会把第 2 批生命周期绑到 usage 组合。

Provider 设置变更到 usage 目录同步由 `IdeHome` 组合边界桥接；Shell 只保留“会话终态
选择实际 Provider”这一跨 feature workflow，不再构造或释放 usage repository。

---

## 3. Owner 映射

### 3.1 Project Threads

| 业务事实 | 当前 owner | 说明 |
| --- | --- | --- |
| `statesByProject` | `ProjectThreadsSliceStore` | Map 构造时冻结 |
| 展开、加载、列表、游标、错误 | store 内的 `ProjectThreadListState` | typed、无 raw payload |
| 全局唯一选中 thread | store reducer | 跨项目至多一个 |
| running / completed 指示 | store reducer | 仅内存，不持久化正文 |
| archived / searchTerm | store reducer | 查询条件；Timer 不进 reducer |
| `_loadTokens`、搜索 Timer | `ProjectThreadsController` | runner 临时状态，关闭时释放 |
| `OperationId` 与 completer | store | 只用于 effect 结算 |

### 3.2 Usage Statistics 页面

| 业务事实 | 当前 owner |
| --- | --- |
| 时间预设、自定义日期 | `UsageStatisticsSliceState` |
| project / provider / model 筛选 | `UsageStatisticsSliceState` |
| rank sort、typed source、report | `UsageStatisticsSliceState` |
| 加载覆盖边界、初始化、错误文案 | `UsageStatisticsSliceState` |
| load `OperationId`、仓储调用 | `UsageStatisticsSliceStore` / runner |

主趋势仍固定使用 `UsageTrendMetric.totalTokens`；筛选选项失效后仍先清理选择，再用原
`buildUsageStatisticsReport` 重建报表。

### 3.3 Agent Usage Panel

| 业务事实 | 当前 owner |
| --- | --- |
| Provider 目录、偏好、当前选择 | `AgentUsagePanelSliceState` |
| 每 Provider entry/status/error | `AgentUsagePanelSliceState` |
| directory drain/coalescing | panel runner |
| provider keyed single-flight / generation | panel runner |
| 选择持久化 effect | app composition 回写 workbench layout |

刷新失败继续保留最近成功 entry；后台 Tab 不展示前台 loading；Provider 移除后，旧
generation 的迟到结果直接丢弃。

---

## 4. MVI、竞态与生命周期

- reducer 只同步产出 state、typed effect 和 result intent，不创建 Timer/Future；
- Project Threads 写操作仍经过 `AgentProviderGlobalRuntime` operation scheduler；能力
  缺失继续抛 `UnsupportedError`；
- Project Threads 列表结果同时受 store `OperationId` 与 runner per-project token
  约束；
- usage 页面使用 `usage-statistics/load` operation identity；panel 分别使用 directory
  与 provider-scoped identity；
- store 关闭时先结算在途调用，再关闭 runner；关闭后的 typed ingress 全部丢弃；
- `MainApp` 拥有并释放 usage composition；Shell 拥有并释放 Project Threads
  composition；Widget/Riverpod adapter 均不拥有业务资源；
- 原始异常只在边界分类，state 仅保存文本目录投影后的稳定错误文案；
- prompt、回复、工具输出、文件 evidence、Provider raw payload 均不进入这些切片或
  持久化。

---

## 5. 删除清单（已兑现）

- `project_threads/presentation/project_threads_view_model.dart`；
- `usage_statistics/application/usage_statistics_controller.dart`；
- `usage_statistics/application/agent_usage_panel_controller.dart`；
- `projectThreadsSliceEnabled` 与 `usageStatisticsSliceEnabled`；
- Shell 的 legacy Project Threads owner/listener/null 分支；
- Shell 的 usage QueryService/repository/source registry 构造、字段与 dispose；
- Project Threads、Usage 页面和 Usage Panel 的 legacy Widget 分支；
- `knownApplicationFlutterImports` 中两个 usage controller 条目。

关批后 Riverpod store providers 为非空、fail-closed 契约；应用漏装配时立即抛错，不再
静默落到 legacy owner。

---

## 6. 等价性证据

Project Threads 覆盖：

- reducer/store 的唯一选择、running→completed、置顶、Map 不可变、typed effect、
  OperationId、关闭与迟到 ingress；
- runner 的真实 fake Provider 列表查询、300 ms 搜索防抖、rename/archive/
  unarchive/delete/fork 参数转发；
- Projects Pane 的分页、展开、运行/完成、多项目、hover/key、新建、打开位置、刷新、
  移除、重命名与 capability 菜单；
- Project Home 的最近 thread、选择、返回和 Agent pane 保活；
- Shell session 恢复、项目切换和持久化。

Usage Statistics 覆盖：

- 最新 load 获胜、旧 Future 正常结算、扩窗补读、筛选与报表等价、失效选项清理、
  关闭取消和迟到结果；
- panel 偏好恢复、Provider keyed single-flight、快速 Tab、目录尾随刷新、Provider
  移除和 selection persistence；
- 统计页、侧栏、v4 分区索引、fingerprint 和三 Provider 数据源回归；
- 真实 `MainApp → IdeHome → Shell → ProviderScope` 下两个非空 store owner 的装配。

最终格式化、静态分析、受影响测试与完整重构门禁结果记录在
`.workflow/refactor/2026-08-23-phase3-batch3-close/06-等价性验收.md`。

---

## 7. 执行历史与回滚

2026-08-23 依次完成：3a 默认关闭路径、双路径对照、生产翻旗；3b 默认关闭路径、
双路径对照、生产翻旗。随后用户明确要求直接进入下一阶段，授权跳过剩余观察时间并
执行关批删除。

关批前两条 flag 可各自回退；关批后不再维护双路径。若发现回归，使用提交 revert 或
发布 tag 回退，不恢复双 owner、双写或已删除的 false-path。Provider 配置、runtime、
session 与 usage 持久化数据均无需迁移或回滚。

下一批是 **Phase 3 第 4 批：workspace + ide session**；本次关批不包含其设计或实现。

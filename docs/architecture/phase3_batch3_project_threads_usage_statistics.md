# Phase 3 第 3 批：Project Threads 与 Usage Statistics

> 对应 [Phase 3 开工文档 §5](phase3_slice_expansion.md) 与
> [目标架构 §15](target_architecture_riverpod_mvi_plugins_packages.md#15-迁移决策门禁)。
>
> 开工日期：2026-08-23。
>
> 当前状态：**3a Project Threads 已推进到四步节奏第 3 步**。新 MVI 路径、
> Projects Pane 的 11 个完整交互双路径对照和 Project Home 的真实组合对照均已
> 落地；经后续显式确认，`projectThreadsSliceEnabled` 构造默认仍为 false，生产
> 入口已于 2026-08-23 显式翻为 true，进入至少 5 天的中风险观察，最早于
> 2026-08-28 关批。旧路径仅作为独立回退保留。3b Usage Statistics 尚未迁移。
> 第 1、2 批仍各自处于生产观察期。

---

## 1. 范围与不迁清单

本批分两个独立小步，一次只迁一个 context：

1. **3a Project Threads**：把按项目归一化的列表状态从 presentation
   `ProjectThreadsViewModel` 迁到纯 Dart `ProjectThreadsSliceStore`；既有
   `ProjectThreadsController` 降为 Provider 查询、能力校验、写操作和搜索防抖的
   effect runner。UI 通过只读 Riverpod adapter 消费。
2. **3b Usage Statistics**：分别迁移完整统计页与 Agent 用量侧栏的状态 owner，
   并把 QueryService / query repository / quota source / source registry 的装配从
   `IdeShellController` 移到 `lib/src/app`。

本批明确不做：

- 不修改 Codex、Grok、Claude Code 的协议、历史扫描语义或 Provider-local parser；
- 不修改 `AgentEvent`、entryId、coalescing、Binding、runtime lease 或权限语义；
- 不修改 `ide_session.json` v4、`usage_statistics_index.json` v4 及任何 codec；
- 不改变 Project Threads 的聚合上限 50、`agg:` 游标、首屏 5 条、后续 10 条、
  搜索 300 ms 防抖或 capability fail-closed 行为；
- 不改变 usage 的时间窗口、报表算法、fingerprint 增量扫描、套餐额度或脱敏白名单；
- 不迁 workspace / ide session（第 4 批），不顺手拆 conversation workspace；
- 不做视觉重设计，不引入新路由、代码生成或第三方状态库。

新增业务事实：**0**。

---

## 2. Owner、依赖图与切换边界

### 2.1 3a 当前与目标

```text
flag=false（legacy）
IdeShellController
  ├─ ProjectThreadsViewModel            # 唯一列表 owner / ChangeNotifier
  └─ ProjectThreadsController           # 查询、Timer、写操作；写入 ViewModel

flag=true（3a slice）
IdeShellController
  └─ ProjectThreadsSliceComposition
       ├─ ProjectThreadsSliceStore       # 唯一列表 owner / 纯 Dart listener
       └─ ProjectThreadsController       # effect/query runner；typed ingress 回 Store
            └─ Provider ports / global runtime / BindingManager

IdeHome 内层 ProviderScope
  └─ projectThreadsSliceStoreProvider
       └─ projectThreadsSliceProvider    # 只读镜像，不复制 owner
            ├─ ProjectListPane
            └─ ProjectHomePage
```

`ProjectThreadsOperations` 是迁移期 Shell 的稳定端口。flag 在构造时只选择一个实现；
不创建另一个 owner，也没有镜像双写。`ProjectThreadsStateOwner` 是 runner 的 typed
回流端口，因此 application 不再 import presentation，燃尽清单减少一项。

### 2.2 3b 目标装配

```text
MainApp / app composition
  ├─ AgentUsageQueryService
  │    ├─ enabled Provider query port
  │    ├─ GlobalRuntimeAgentUsageQuotaSource
  │    └─ BuiltInAgentTokenUsageSourceRegistry
  ├─ QueryUsageStatisticsRepository
  ├─ QueryAgentUsagePanelRepository
  ├─ UsageStatisticsSliceStore + runner
  └─ AgentUsagePanelSliceStore + runner

presentation Riverpod adapters
  ├─ UsageStatisticsPage selectors
  └─ AgentUsagePanel selectors
```

组装链移出 Shell，但健康的 QueryService、repository、source registry 与 partition
store 不重写，只换创建与 dispose 位置。

---

## 3. 字段级 owner 映射

### 3.1 Project Threads 列表状态

| 现状字段 | 3a 切片字段 | 迁移后 owner | 说明 |
| --- | --- | --- | --- |
| `ProjectThreadsViewModel._states` | `ProjectThreadsSliceState.statesByProject` | store | `Map<String, ProjectThreadListState>` 形状不变，构造时冻结 Map |
| `ProjectThreadListState.isExpanded` | 原字段 | store | 项目展开状态 |
| `hasLoaded` | 原字段 | store | 首屏是否成功加载过 |
| `isLoadingInitial` | 原字段 | store | 首屏/刷新在途投影 |
| `isLoadingMore` | 原字段 | store | 追加分页在途投影 |
| `threads` | 原字段 | store | typed `AgentThreadSummary` 列表；不复制正文 |
| `runningThreadIds` | 原字段 | store | 仅 Zeta 本进程 live turn |
| `completedThreadIds` | 原字段 | store | 仅内存完成提示，不持久化 |
| `nextCursor` | 原字段 | store | 客户端 `agg:` offset；Provider cursor 不泄漏给 UI |
| `errorMessage` | 原字段 | store | 仍由注入文本目录投影，不保存 raw error |
| `selectedThreadId` | 原字段 | store | 跨项目全局至多一个 |
| `archived` | 原字段 | store | `thread/list` typed 查询条件 |
| `searchTerm` | 原字段 | store | 值进 state；300 ms Timer 不进 state/reducer |

### 3.2 Project Threads runner 临时状态

| 现状字段 | 3a 去向 | owner / 生命周期 | 说明 |
| --- | --- | --- | --- |
| `ProjectThreadsController._loadTokens` | 原字段保留 | runner，随 store 关闭 | 每项目迟到 list 结果校验 |
| `_projectPathByThreadId` | runner + store 各自的内容盲索引 | 各自 scope | 只存 ID 映射；不是第二份列表事实 |
| `_searchDebounceTimers` | 原字段保留 | runner | reducer 禁止 Timer；dispose 全取消 |
| `_disposed` | 原字段保留 | runner | 关闭后拒绝 effect 回流 |
| store `OperationIdGenerator` | 新增机制字段 | store | 只标识命令完成，不是 UI 业务事实 |
| store completer maps | 新增机制字段 | store | 兼容既有 Future API；不持久化、不发布 |

`ProjectThreadsController` 不再持有 `ProjectThreadsViewModel`，只依赖纯 application
端口。session snapshot 仍由原 codec 从当前 owner 的 Map 构建。

### 3.3 Usage Statistics 页面（3b）

| 现状 `UsageStatisticsController` 字段 | 目标 `UsageStatisticsSliceState` | owner 说明 |
| --- | --- | --- |
| `_timePreset` | `timePreset` | 页面 slice |
| `_customStart` / `_customEndInclusive` | `customStart` / `customEndInclusive` | 页面 slice |
| `_projectPath` / `_providerId` / `_model` | `selectedProjectPath` / `selectedProviderId` / `selectedModel` | 页面 slice；不存在的选项仍自动清空 |
| `_rankSort` | `rankSort` | 页面 slice |
| `_source` | `source` | 页面 slice；typed、脱敏 snapshot |
| `_report` | `report` | 页面 slice 的派生结果，仍调用原 report builder |
| `_loadedEarliest` | `loadedEarliest` | 页面 slice 的加载覆盖边界 |
| `_loading` | `loadingOperationId != null` | 页面 slice |
| `_initialized` | `initialized` | 页面 slice |
| `_errorMessage` | `failure` 的文本目录投影 | 页面 slice；不保存 raw error |
| `_loadToken` | `OperationId` scope `usage-statistics/load` | store/runner 机制字段 |
| `_disposed` | store `isClosed` | store 生命周期字段 |

### 3.4 Agent Usage Panel（3b）

| 现状 `AgentUsagePanelController` 字段 | 目标 `AgentUsagePanelSliceState` / runner | owner 说明 |
| --- | --- | --- |
| `_providers` | `providers` | panel slice，顺序保持 Provider 配置目录顺序 |
| `_preferredProviderId` | `preferredProviderId` | panel slice；持久化仍由 workbench layout owner |
| `_selectedProviderId` | `selectedProviderId` | panel slice；必须存在于目录 |
| `_lastUpdated` | `lastUpdated` | panel slice |
| `_errorMessage` | `directoryFailure` | panel slice，文本目录投影 |
| `_discovering` | `directoryOperationId != null && showLoading` | panel slice |
| `_directoryDiscovered` | `directoryDiscovered` | panel slice |
| `_directoryRefreshPending` / `_directoryLoadingRequested` / `_directoryDrain` | 原队列语义 | runner；合并目录刷新，不进 reducer |
| `_providerGenerations` | `OperationId` / provider generation | runner + pending identity |
| `_providerLoads` | provider keyed single-flight | runner |
| `_disposed` | store `isClosed` | store 生命周期 |
| `onSelectionChanged` | typed selection effect | app composition 回写 workbench layout |

`AgentUsagePanelProviderState` 的 `provider`、`entry`、`status`、`loadError` 四字段原样；
刷新失败继续保留最近成功 entry，后台 Tab 不点亮顶部 loading。

---

## 4. Intent、Effect 与 Result Intent

### 4.1 3a 已落地

状态 intent：

- `ProjectThreadStatesReplaced`、`ProjectThreadProjectsRetained`、
  `ProjectThreadStateApplied`；
- `ProjectThreadSelected`、`ProjectThreadSelectionCleared`、
  `AllProjectThreadSelectionsCleared`；
- `ProjectThreadRunningChanged`、`CompletedProjectThreadDismissed`、
  `ProjectThreadRuntimeStatusChanged`；
- `ProjectThreadTitleChanged`、`ProjectThreadPreviewChanged`、
  `ProjectThreadRemoved`、`ProjectThreadPrepended`。

Effect：

- restore / activate / retain；
- toggle / archived view / search；
- initial load / load more；
- rename / archive / unarchive / delete / fork。

Result intent：

- `ProjectThreadsOperationSucceeded`；
- `ProjectThreadsForkSucceeded`；
- `ProjectThreadsOperationFailed`。

结果 intent 只结算兼容 Future，不把 raw exception 写进 state。简单的选择、运行态、
标题与 preview 更新由 reducer 同步完成；时间通过 intent 注入，reducer 不读时钟。

### 4.2 3b 计划

完整统计页 intent：initialize、refresh、time preset/custom range、project/provider/
model/rank selection、source loaded、load failed。Effect 只有 load source；result 带
`OperationId` 与 typed source/failure category。

侧栏 intent：directory refresh/synchronize、provider selected/restored/from-turn、
provider load requested、directory/provider loaded/failed。Effect 分 directory query、
provider query 与 selection persistence；不建立通用 usage command 基类。

---

## 5. 操作身份与迟到结果

### 5.1 3a

- Store 为 toggle、archive view、initial load、load more、rename、archive、
  unarchive、delete、fork 分 scope 铸造 `OperationId`；只结算仍在 completer registry
  中的结果，重复/关闭后回执计入 stale 诊断并丢弃。
- 列表数据的覆盖仍由 runner 的每项目 `_loadTokens` 二次校验；这是既有竞态语义，
  防止旧搜索/旧刷新覆盖新列表。
- store 关闭先让调用方 Future 收敛，再关闭 runner；随后 typed state/result ingress
  全部丢弃。
- thread 写操作仍经过 `AgentProviderGlobalRuntime` 的 operation scheduler；能力缺失
  继续抛 `UnsupportedError`，不得伪造成功。

### 5.2 3b

- 完整统计页：`usage-statistics/load`，result 同时校验 operation id 与 store 未关闭；
- panel 目录：`agent-usage/directory`，保留现有 drain/coalescing；
- panel Provider：`agent-usage/provider/<normalized-id>`，校验 operation id、当前目录
  generation 与 provider 仍存在；
- 旧 result 只丢弃，不清 loading、不覆盖 entry、不触发选择持久化。

---

## 6. 生命周期与 dispose

| 对象 | 创建者 | dispose / close | 不拥有 |
| --- | --- | --- | --- |
| legacy `ProjectThreadsViewModel` | Shell（flag=false） | Shell | runtime / repository |
| legacy `ProjectThreadsController` | Shell（flag=false） | Shell | Provider runtime registry |
| `ProjectThreadsSliceStore` | `ProjectThreadsSliceComposition`（flag=true） | Shell 经 operations port | Provider runtime、Binding |
| Project Threads runner/controller | composition | store close 反序关闭 | state owner |
| Riverpod adapter | `IdeHome` 内层 ProviderScope | autoDispose 只摘 listener | store / CLI 生命周期 |
| 3b 两个 usage store | app composition | IdeHome/app composition | partition store / runtime registry |
| 3b query services/repositories | app composition | 无资源者随组合释放 | Provider CLI 进程 |
| usage partition store | MainApp | 现有 owner | UI 状态 |

Riverpod `autoDispose` 绝不关闭 store、runtime、Binding 或 plugin。

---

## 7. §15 十问答卷

1. **唯一 owner**：3a flag=false 是 ViewModel，flag=true 是
   `ProjectThreadsSliceStore`，构造时二选一；3b 分别由 page store 与 panel store
   持有，QueryService 只查询。
2. **Intent / State / Effect / Result**：见 §3–4；均为 feature-local typed 契约。
3. **边界类型**：无 raw Provider payload、文件结构或协议字段进入 slice；Riverpod
   只在 presentation；application 新文件无 Flutter。Project Threads controller 的
   application→presentation import 已删除。
4. **创建与释放**：见 §6。Binding/runtime/plugin owner 不变，UI autoDispose 不释放
   业务对象。
5. **迟到结果**：见 §5；OperationId + per-project token / provider generation + closed
   三重判定。
6. **正文与发布频率**：不复制 prompt、回复、工具输出或 patch；线程只存既有摘要。
   Riverpod adapter 将同一 microtask 的多次 store publish 合并一次。
7. **缓存**：Project Threads source of truth 仍是 Provider catalog，Map 是内存投影；
   usage source of truth 仍是分区索引 + Provider quota，key/fingerprint/TTL 不变。
8. **持久化**：白名单与 schema version 均不变；Project Threads session codec 与 usage
   v4 partition codec 不动。
9. **回滚与删除**：见 §9–10；无双写。flag=false 一行回退。观察关批后删除旧 owner
   和 flag。
10. **证据**：纯 reducer/store 单测、runner Provider 查询与防抖测试、真实
    `IdeHome` flag 双路径 Widget 测试、既有 Project Threads controller 回归、G6
    分层守卫、affected/full 门禁。

---

## 8. 验收测试清单

3a 已建立：

- reducer/store：全局唯一选择、running→completed、置顶、Map 不可变、同步 session
  登记、typed effect、OperationId 结算、dispose 与迟到 ingress；
- runner：真实 fake Provider 列表查询、300 ms 搜索防抖，以及 rename / archive /
  unarchive / delete / fork 五类 lifecycle effect 的参数转发与 Future 结算；
- legacy controller：既有 33 条分页、聚合、恢复、runtime、写操作、fork 权限测试；
- Widget：`MainApp → IdeHome → Shell → inner ProviderScope` 在 flag 开/关下分别解析
  store/null，切片 publish 可被 Riverpod 读取；
- Projects Pane：11 个真实根组合场景使用同一套断言在 flag=false/true 下逐一运行，
  覆盖分页与历史加载、展开/收起、运行与后台完成、多项目指示、hover/key 稳定性、
  新建与 session 持久化、打开位置、刷新、移除项目、重命名及 G4 capability 菜单；
- Project Home：真实 `IdeHome` 在两条路径都覆盖项目首页、最近五条、选择 thread 与
  返回当前项目且不重置 Agent pane；
- 架构：`feature_layering_guard_test` 将 application→presentation 基线从 2 减到 1；
- 生产入口已为 flag=true；关批前只剩至少 5 天的真实使用观察与记录，最早于
  2026-08-28 执行删除清单。

3b 必补：时间窗口与扩窗加载、过滤选项保留、报告等价、目录 refresh 合并、Tab
single-flight、静默刷新、Provider 移除迟到结果、选择持久化 exactly-once、v4 索引与
fingerprint 回归、Usage 页面/侧栏双路径 Widget 测试。

热路径预算：Project Threads 不消费 raw stream，只接列表/运行态摘要；观察期若 Shell
或 Project Pane rebuild 超 Phase 0 基线，再以证据细化 selector，不预先拆碎 provider。

---

## 9. 删除清单与关批条件

3a 观察关批时删除：

- `project_threads/presentation/project_threads_view_model.dart`；
- legacy Shell 构造、nullable legacy getter 与旧 listener 分支；
- `projectThreadsSliceEnabled` flag 及 false-path Widget 对照；
- `ProjectThreadsStateOwner` 中只为 legacy ViewModel 保留的适配表面（runner typed ingress
  保留或收窄重命名）；
- 文档中的 legacy 路径说明。

3b 观察关批时删除：

- `UsageStatisticsController`；
- `AgentUsagePanelController`；
- Shell 中 usage QueryService/repository/source registry 的构造、字段与 dispose；
- 本批 usage flag 与 legacy Widget 分支；
- `knownApplicationFlutterImports` 对应两项。

第 3 批整体关门必须满足：3a、3b 各自生产观察通过；三个 ChangeNotifier 全删；usage
装配从 Shell 移出；持久化/行为/能力门禁全绿；本批 flag 随旧路径一起删除。

---

## 10. 回滚与执行记录

批内 flag：

- 3a：`projectThreadsSliceEnabled`；构造默认 false，生产入口自 2026-08-23 起显式
  true；
- 3b：开工时新增独立 `usageStatisticsSliceEnabled`，不得借用 3a flag 原子切换两个
  context。

回滚只切对应 flag，不回滚 Provider 配置、runtime、session 或持久化数据。关批后的
回滚依赖提交 revert / 发布 tag，不恢复双写。

**提前开工记录（2026-08-23）**：用户显式要求直接开启第 3 批，接受与第 1、2 批
生产观察窗口重叠。授权范围仅为第 3 批字段级契约、3a 默认关闭 flag、切片实现与
双路径对照；未授权 3a 生产翻旗，也未把 3b 合并进同一 owner 切换。生产行为因此
保持不变。

**3a 执行记录（2026-08-23）**：纯 Dart state/intent/effect/reducer/store、app runner
与 presentation Riverpod adapter 已落地；controller 的 application→presentation
反向依赖已清除；初始落地时生产 flag 保持 false。

**3a 对照补全记录（2026-08-23）**：Projects Pane 的 11 个真实根组合场景已改为
flag=false/true 同体测试，Project Home 的真实 `IdeHome` 场景也完成双路径验证；第 2
步因此完成。当时下一步必须先取得显式确认，再把 3a flag 翻为 true 进入生产观察。

**3a 生产翻旗记录（2026-08-23）**：完整双路径对照、受影响测试与完整重构门禁通过
后，经后续显式确认，`main.dart` 已传 `projectThreadsSliceEnabled: true`。3a 按
中风险取至少 5 天观察期，最早于 2026-08-28 关批；若回退则一行拨回 false，修复并
复测后重新起算。3b 仍在 3a 接缝取得真实使用稳定证据后单独开工。

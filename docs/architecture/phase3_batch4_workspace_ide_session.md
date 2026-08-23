# Phase 3 第 4 批：Workspace 与 IDE Session

> 对应 [Phase 3 开工文档 §6](phase3_slice_expansion.md) 与
> [目标架构 §15](target_architecture_riverpod_mvi_plugins_packages.md#15-迁移决策门禁)。
>
> 开工与关批日期：2026-08-23。当前状态：**已关批**。4a Workspace 与 4b IDE
> Session 均固定为 MVI 单一路径；两个批内 flag、Shell 旧状态字段、直接目录树构造和
> Session false-path 已删除，只读根 `ZetaStateSnapshot` 已建立。
>
> 用户明确要求“执行关批和旧路径删除”，接受缩短原定至 2026-08-30 的观察余量；
> 该授权不改变第 1、2 批各自的观察与回滚边界。

## 1. 范围与不迁清单

第 4 批拆成两个独立 context 顺序推进：

1. **4a Workspace**：迁移项目/树/文件选择 owner，文件索引去 ChangeNotifier，
   `@mention` 改走 port；
2. **4b IDE Session**：保持 coordinator 的防抖和 restore token，新增 persistence
   effect adapter；最后建立只读 `ZetaStateSnapshot`。

4a 不迁 `projectHomeActive`、entry↔thread 映射、Binding/runtime、Workbench layout
owner；前两项属于第 5 批 conversation workspace，layout 与恢复 lifecycle 属于 4b。
不改 v4 schema、文件树视觉、Provider 协议或任何 Agent identity。新增业务事实为 0。

## 2. Owner 与字段映射

### 2.1 4a Workspace

| 旧 Shell 字段 | 新 owner / 字段 | 说明 |
| --- | --- | --- |
| `_projects` | `WorkspaceSliceState.projects` | 顺序与去重不变 |
| `_projectPath` | `activeProjectPath` | 单一活动项目 |
| `_workspaceTree` | `tree` | 只含已加载层级 |
| `_expandedDirectoryPaths` | `expandedDirectoryPaths` | Set 不可变 |
| `_currentFilePath` | `currentFilePath` | Agent context 投影来源 |
| `_selectedTreePath` | `selectedTreePath` | 文件/目录选择 |
| `_projectLastOpenedAtByPath` | `projectLastOpenedAtByPath` | MRU 排序 |
| `_isLoadingProject` | `isLoadingProject` | application operation 状态 |
| `_fileIndexController` corpus | 保持原 controller | derived cache，不复制入 slice |

关批后旧字段已删除，只有 store 接收 intent。Shell 仅通过只读 getter 与操作 facade
编排跨 feature workflow。

### 2.2 4b IDE Session

| 当前事实 | 目标 owner |
| --- | --- |
| coordinator `isRestoring` / restore result | `IdeSessionSliceState.isRestoring` / `restoreStatus` |
| Shell `_initialRestoreCompleted` | `IdeSessionSliceState.initialRestoreCompleted` |
| Shell `_initialRestoreCompleter` | `IdeSessionSliceStore.initialRestoreDone` 兼容等待口 |
| Shell `_workbenchLayout` | `IdeSessionSliceState.workbenchLayout` |
| debounce timer / restore token / pending snapshot | 既有 coordinator，由 app runner 持有 |
| v4 persistent snapshot | 各 feature owner 的白名单投影，不作为第二份运行态 owner |

关批后 Shell 只消费必选 `IdeSessionSliceOperations`；coordinator 仅由 app runner 持有，
旧字段与 Shell 构造入口均已删除。`MainApp` 始终创建稳定 composition，Riverpod
override 数量在 rebuild 中保持不变。

## 3. Intent、Effect 与结果

4a Intent：project load requested/succeeded/failed、session workspace restored、project
opened/removed、active workspace cleared、tree expansion changed、directory loaded、tree node
selected、current file cleared。Effect：读取项目顶层、按需读取单目录、启动/失效文件索引。
结果 intent 携带同一个 `OperationId`；raw `Directory`/`FileSystemException` 不进入 state。

4b Intent：restore requested/result received/cancellation requested/initial completed、save
requested/save-now requested/completed、workbench layout changed。Effect 只调用现有
coordinator；result 继续使用
`IdeSessionRestoreResult` typed 状态，不重写 store/codec。

## 4. 操作身份、缓存与生命周期

- project load scope 为 `workspace/load-project`；新 load 或 close 使旧 operation 失效，
  runner 回流前和 store 提交时各校验一次；
- restore 的迟到拒绝仍以 coordinator restore token 为权威，4b 不增加第二套猜测；
- workspace index 四元组不变：source=文件系统，key=project root + generation，
  invalidation=project clear/invalidate/watch structural event，budget=50,000 文件；
- Shell 创建/释放 workspace composition 和 index controller；Riverpod adapter 只订阅，
  不拥有 store、watch、runtime 或 Binding；
- 4b app 根创建 session composition，Shell 只消费操作 port；composition 生命周期不由
  Riverpod 或 Shell 拥有。

## 5. §15 门禁答卷

1. 唯一 owner：4a 开启时为 `WorkspaceSliceStore`；4b 后 session lifecycle 为
   `IdeSessionSliceStore`，持久化 DTO 仍是投影。
2. Intent/State/Effect/result：见 §2–3，按 context 分离。
3. 越界类型：state/reducer/store 无 Flutter/Riverpod/`dart:io`；I/O 只在 runner/既有 data。
4. 生命周期：Shell 暂时拥有 workspace composition；4b app 拥有 session composition；
   runtime/Binding owner 不变。
5. 迟到结果：Workspace `OperationId`；session restore token；dispose/closed 二次校验。
6. 大正文/频率：不复制正文、diff 或 corpus；树仍按交互更新，索引无变化不通知。
7. 缓存：见 §4；树本身是业务状态，corpus 是有界 derived cache。
8. 持久化：白名单与 `ide_session.json` v4 均不变。
9. 回滚/删除：旧 Shell 字段、两个 flag 与全部 false-path 已删除；回滚走提交 revert。
10. 证据：slice 单测、索引/mention 契约、双路径真实 IdeHome Widget、v1–v4 codec、
    慢恢复取消、架构守卫、affected 与 full suite。

## 6. 验收与删除清单

4a 必须证明：顶层读取、惰性展开、目录优先排序、忽略项、symlink、选择/context、MRU、
移除项目、恢复树、索引 single-flight/generation/debounce、mention fallback 在两路径等价。

4b 已证明：restore empty/failed/cancelled/restored、防抖保存、restore 期间排队保存、
关闭前 saveNow、损坏/旧版 session 与真实 IdeHome 跨页保活等价。

关批删除已兑现：Shell 的八个 workspace 字段及直接 repository/tree 构造、
`workspaceSliceEnabled`、`ideSessionSliceEnabled`、session coordinator 构造与旧恢复/保存
入口、两条 false-path。Workspace index 的 application Flutter 条目与过期 domain 条目已在
4a 纯化时提前清零，本次守卫继续钉住零回归。

## 7. 只读根状态快照

`MainAppState.takeStateSnapshot()` 按需聚合 app 生命周期切片；唯一 Workbench 组合边界通过
无监听 relay 提供 Workspace、Project Threads、Conversation 身份与 Agent Management
安全摘要。根快照：

- 没有 Provider、Notifier、listener、subscribe 或持久化 API；
- 生产 Widget 仍只 watch feature selector，不 watch 根快照；
- Conversation 只含 entry/project/provider/thread 身份、阶段与计数，不含标题、消息、
  工具或 diff 正文；
- Agent Management 不含配置正文、路径、日志或原始错误；
- 第 1、2 批尚未关批时对应节点允许为空，关批后再收敛为必选节点。

## 8. 执行历史与回滚

4a/4b 先完成默认关闭实现、双路径对照与生产翻旗，随后进入原定至少 7 天观察。用户于
同日明确授权提前关批，旧路径与 flag 随即删除。

关批后通过提交 revert/tag 回退，不恢复双 owner、双写或长期 feature flag。
`ide_session.json` v4 与 Workspace 文件系统数据均无需迁移或回滚。

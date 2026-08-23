# Phase 3 第 4 批：Workspace 与 IDE Session

> 对应 [Phase 3 开工文档 §6](phase3_slice_expansion.md) 与
> [目标架构 §15](target_architecture_riverpod_mvi_plugins_packages.md#15-迁移决策门禁)。
>
> 开工日期：2026-08-23。当前状态：**4a Workspace 与 4b IDE Session 已通过完整
> 双路径门禁并进入生产观察**。生产 `workspaceSliceEnabled` 与
> `ideSessionSliceEnabled` 均为 `true`，可独立回退。

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

flag false 时只有旧字段接收写入；flag true 时只有 store 接收 intent。Shell 仅通过只读
getter 与操作 facade 编排跨 feature workflow。

### 2.2 4b IDE Session

| 当前事实 | 目标 owner |
| --- | --- |
| coordinator `isRestoring` / restore result | `IdeSessionSliceState.isRestoring` / `restoreStatus` |
| Shell `_initialRestoreCompleted` | `IdeSessionSliceState.initialRestoreCompleted` |
| Shell `_initialRestoreCompleter` | `IdeSessionSliceStore.initialRestoreDone` 兼容等待口 |
| Shell `_workbenchLayout` | `IdeSessionSliceState.workbenchLayout` |
| debounce timer / restore token / pending snapshot | 既有 coordinator，由 app runner 持有 |
| v4 persistent snapshot | 各 feature owner 的白名单投影，不作为第二份运行态 owner |

flag false 时 Shell 只构造旧 coordinator 并写旧字段；flag true 时 Shell 只消费
`IdeSessionSliceOperations`，旧 coordinator 不构造、旧字段不写。`MainApp` 始终创建稳定
composition，关闭 flag 时 store dormant，避免 Riverpod override 数量在 rebuild 中变化。

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
9. 回滚/删除：4a flag 一行回退且无双写；关批删除旧 Shell 字段、flag 与 false-path。
10. 证据：slice 单测、索引/mention 契约、双路径真实 IdeHome Widget、v1–v4 codec、
    慢恢复取消、架构守卫、affected 与 full suite。

## 6. 验收与删除清单

4a 必须证明：顶层读取、惰性展开、目录优先排序、忽略项、symlink、选择/context、MRU、
移除项目、恢复树、索引 single-flight/generation/debounce、mention fallback 在两路径等价。

4b 默认关闭路径必须证明：restore empty/failed/cancelled/restored、防抖保存、restore 期间
排队保存、关闭前 saveNow、损坏/旧版 session 与真实 IdeHome 跨页保活等价。生产翻旗已
完成；观察、旧路径删除和 root `ZetaStateSnapshot` 仍是独立后续步骤。

关批删除：Shell 的八个 workspace 字段及直接 repository/tree 构造、
`workspaceSliceEnabled`、session coordinator 构造与旧恢复/保存入口、两条 false-path；同步
清除 `knownApplicationFlutterImports` 的 workspace index 条目和过期 domain 清单项。

## 7. 回滚

观察期间 `workspaceSliceEnabled` 与 `ideSessionSliceEnabled` 可分别拨回 `false`，不影响
第 1/2 批或 conversation slice；任一路径回退并修复复测后，只重新起算自身观察窗口。
关批后通过提交 revert/tag 回退，不恢复双写。root `ZetaStateSnapshot` 等待第 4 批关批时
统一建立。

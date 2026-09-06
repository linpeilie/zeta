# WP-4 · Project Threads 同步业务与索引收口

返回 [开发总入口](00-index.md)。下文保留设计与迁移清单；2026-09-06 实现与全部收尾门禁已完成，见 §10。

| 项目 | 约定 |
|---|---|
| 状态 | 已完成；实现与验收见 §10 |
| 目标 | Shell、Widget 与测试使用同一个 ProjectThreadsOperations 入口；同步业务规则和 thread→project 映射只归一个 owner |
| 前置 | 无代码前置；先复核本章证据与现有测试基线 |
| 后继 | WP-3P：把本章已经收口的 Store 迁成 application Notifier |
| 性质 | 保持现有行为的重构；每个可交付重构提交必须完成全量门禁 |
| 不包含 | Provider 协议升级、复合 thread key 迁移、v4 持久化变更、分页算法重写、Runner 取消协议重写 |
| 代码基线 | 2026-09-05；下列行号只作查找辅助，实施时以符号与最新调用图为准 |

## 1. 已核实的现状与需要解决的问题

本章针对的是两份同步业务实现，不是认为 EffectRunner 本身多余。

1. lib/src/app/shell/ide_shell_controller.dart:96–104 创建 ProjectThreadsSliceComposition 后，将 projectThreadsController 与 projectThreadsSliceStore 都指向 composition.store。Shell:1002、1011、1043 的 session 登记和 runtime 快照同步实际调用 Store。
2. lib/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart:182–335 实现选择、session 登记、运行态同步、标题与预览更新。Store:59 持有 _projectPathByThreadId。
3. lib/src/app/project_threads_slice/project_threads_slice_runner.dart:192–387 另有同名、近似同内容的旧 Controller API；Runner:50 也持有 _projectPathByThreadId。Runner 的 run(effect) 只分发恢复、分页、搜索与远端写操作，不使用这组同步 API。
4. 两份实现已有细节漂移：Runner.registerSession 使用 DateTime.now()（:241），Store.registerSession 使用构造注入的 _now()（:222）。本章保留生产 Store 的时钟行为。
5. test/src/features/project_threads/application/project_threads_slice_runner_test.dart 的 _createController（:1223）返回 Runner，许多标题/状态测试因此验证旧 Runner 入口。生产 Store 出现回归时，这些测试可能仍然通过。
6. Runner 的异步 thread 操作没有依赖它自己的反查 map：_runForThread → _providerIdForThread（:1021 起）从 stateOwner.stateFor(projectPath).threads 查询 providerId。因此，在迁走同步业务后，可以移除 Runner 的重复映射；不能因此移除分页 token、Timer 或 Provider 操作所需的状态读取。

代码规模只用于定位，不能充当问题证明。问题的判断依据是同一规则有两份可独立演化的实现，且测试入口与生产入口不同。

## 2. 完成后的职责与保持不变的行为

目标调用关系：

~~~text
Shell / Widget / 测试
  → ProjectThreadsOperations（当前实现仍为 ProjectThreadsSliceStore）
      → 同步命令：同一份规则 → typed intent → 纯 reducer
      → 异步命令：OperationId → effect
          → ProjectThreadsSliceRunner.run(effect)
              → Provider / 调度 / 分页
              → ProjectThreadsStateOwner typed ingress
                  → 同一个 Store / reducer
~~~

| 状态或职责 | 本章完成后的唯一归属 | 保留边界 |
|---|---|---|
| statesByProject、选中/运行/完成标志、标题/预览 | Store 的 _state；变更经过现有 reducer | Runner 不持有第二份列表状态 |
| threadId→projectPath 反查映射 | Store 私有 _projectPathByThreadId | 保留已有 String key 语义，不在本章改键形状 |
| session 创建时的时间、状态晋升时间 | Store 注入的 _now；时间随 intent 进入 reducer | Runner 不另取 DateTime.now() 来实现同一业务命令 |
| 每项目 load token | Runner 的 _loadTokens | 它描述在途 I/O，不是列表事实；不得随重复 map 一起删除 |
| 搜索防抖 Timer | Runner 的 _searchDebounceTimers | 继续保持 300 ms、防抖取消、close 清理 |
| 聚合游标、单 Provider 收集窗口、seenIds | Runner / 一次查询的局部变量 | 继续保持聚合偏移、Provider 分页以及 50 条上限 |
| 页面合并策略 | 现有 Runner 纯 helper，提交由 Store 负责 | 本章不要求为缩短 Runner 把所有 helper 搬进 reducer |
| command Future / OperationId 结算 | Store | Runner 只回流 operationSucceeded / operationFailed / forkSucceeded |
| thread 被移除后通知 Shell | Runner 发出的现有 onActiveThreadCleared 回调，经 composition 转发 | 回调只在 Store 已确认移除当前选中项后触发；WP-3P 再调整装配方式 |

需要保持的业务行为：

- 全局最多一个 project 持有选中的 thread；选择 thread 会清除其完成提示。
- 新 session 优先使用 Provider 已有正式标题；占位标题不覆盖首条消息形成的 preview；正式标题随后仍可同步。
- 运行开始会按现有规则晋升列表项；非选中 thread 完成后显示完成提示；等待审批/等待输入继续按 runtime 快照保留。
- turn 结束而 Provider status 尚为 active 时，保留现有 idle 收敛规则，避免残留 busy。
- 第一页默认 5 条、追加页 10 条、每 Provider 收集上限 50 条；跨 Provider 按原 recency 排序规则聚合。
- 早发起的首页查询不能删掉随后乐观登记的当前/运行/已完成 thread；Provider 索引弱标题与弱 preview 不能覆盖本地更丰富的展示字段。
- Provider list 的 active/waiting 不自动等同于 Zeta 本进程正在运行；原有 live 投影规则保持。
- 无可用 Provider、全部查询失败、部分查询失败、保留旧缓存的逻辑保持；不借本章改变能力缺失时的返回/异常类型。
- fork 的 Binding 权限快照、Provider 保守默认、catalog 查询及失败路径逐字保留；本章不能扩大权限或改变 G5。

## 3. 方法逐一去向

### 3.1 删除 Runner 的同步业务入口

下表“删除”均指完成调用方与测试迁移后删除 Runner 中的方法；Store 中的对应公开方法及 ProjectThreadsOperations 契约保留。

| Runner 成员 | 唯一目标 | 迁移时要保留的语义 |
|---|---|---|
| selectThread | Store.selectThread | 从摘要登记归属后，执行全局互斥选择 |
| selectThreadId | Store.selectThreadId | 恢复/导航的 id 入口继续可用 |
| clearSelectedThread | Store.clearSelectedThread | 仅清当前 project 选择 |
| clearAllSelectedThreads | Store.clearAllSelectedThreads | 回项目首页时清全局选择 |
| registerThreadMapping | Store.registerThreadMapping | 可登记尚未位于当前分页窗口中的 thread |
| registerSession | Store.registerSession | 摘要建立、正式标题过滤、preview、注入时钟、选择、markRunning |
| setThreadRunning / _setThreadRunning | Store.setThreadRunning / applyThreadRunning | 反查映射、运行边沿晋升、完成提示、active 收敛 |
| dismissCompletedThread | Store.dismissCompletedThread | 只移除目标完成提示 |
| syncRuntimeSnapshot | Store.syncRuntimeSnapshot | sessionId 校验、标题/preview 更新、waiting/status/running 更新顺序 |
| _effectiveListRuntimeStatus | Store 同名私有纯函数 | 不复制成公共“工具类”后仍保留两条业务路径 |
| updateThreadTitle | Store.updateThreadTitle | 保持原 thread 映射和标题 intent |
| updateThreadPreview | Store.updateThreadPreview | 保持原 thread 映射和 preview intent |
| sessionSnapshot getter | Store.sessionSnapshot | 快照编码仍经现有 buildProjectThreadsSessionSnapshot |
| _projectPathByThreadId | Store 同名私有 map | 删除 Runner 存储，仅保留一个维护点 |
| _registerThreadMapping / _registerThreadSummaries / _registerStateThreadMappings | Store 现有映射维护方法 | Runner 在 restore/page 路径不再登记第二份 map |

Runner 的 stateFor 可以保留为私有 _stateFor 包装，调用 stateOwner.stateFor；它只是读取，不构成第二个 owner。公开的同名查询不是生产能力需求，旧测试应从 operations/stateOwner 读取。

### 3.2 保留 Runner 的真实 effect 执行路径

把下列实现改为私有 effect 执行 helper，行为不变；调用方一并迁移至 operations/effect 入口。对外生产入口只保留 run(effect) 与 close()。

| run(effect) 的现有分支 | Runner 内保留 | Store ingress / 回执 |
|---|---|---|
| RestoreProjectThreadsEffect | 调 buildProjectThreadsRestorePlan；按 plan 触发需要预加载的项目 | applyStatesReplacement；不要再写 Runner map |
| ActivateProjectThreadsEffect | 展开、触发首屏加载 | applyProjectState |
| RetainProjectThreadsEffect | 计算 removed paths；取消对应搜索 Timer、清对应 load token | applyProjectsRetention；Store 负责清归属映射 |
| ToggleProjectThreadsEffect | 当前展开态读取、展开后必要时首屏加载 | applyProjectState + operationSucceeded/Failed |
| SetArchivedProjectThreadsEffect | archived 切换、重置原列表窗口、触发首屏 | applyProjectState + operationSucceeded/Failed |
| SetProjectThreadSearchEffect | 写入搜索状态、300 ms 防抖、触发首屏 | applyProjectState；保留无独立 Future 的现有语义 |
| LoadInitialProjectThreadsEffect | _loadPage，首页参数与已加载/加载中判断 | applyProjectState + operationSucceeded/Failed |
| LoadMoreProjectThreadsEffect | 读取当前聚合 cursor；追加与去重 | applyProjectState + operationSucceeded/Failed |
| RenameProjectThreadEffect | globalRuntime 调用、能力/端口检查、远端命名成功后应用标题 | applyThreadTitle + operationSucceeded/Failed |
| ArchiveProjectThreadEffect | globalRuntime、归档端口、移除本地列表项 | applyThreadRemoval + 需要时 onActiveThreadCleared + 回执 |
| UnarchiveProjectThreadEffect | globalRuntime、取消归档、移出当前归档窗口 | 同上 |
| DeleteProjectThreadEffect | 删除能力 / localThreadList 分支、原有失败边界 | 同上；不改变“删除远端”和“仅本地移除”的用户语义 |
| ForkProjectThreadEffect | globalRuntime、Binding/权限快照、分叉端口 | forkSucceeded；新 session 的选择仍由 Shell→Store.registerSession 完成 |

注意：恢复、切 archived、搜索属于 Runner 已有异步流程的一部分。本章消除的是两份规则，不能以“同步的都移去 reducer”为理由同时重写这几个现有流程。

## 4. 唯一索引 owner 与 StateOwner 端口

### 4.1 无损收口方案

保留现有 Store 的 map 与维护规则，不新建独立可变“索引服务”。Runner 通过 typed ingress 提交结果；map 是 Store 的内部派生索引，并包含 explicit registerThreadMapping 登记的窗口外 thread。不可在每次发布时仅从当前 5/10 条 visible rows 全量重建，否则会丢掉未进入当前列表窗口的运行态归属。

| 场景 | 唯一维护点 | 不可做的简化 |
|---|---|---|
| Store 构造 | _rebuildThreadMappings | 删除 initialState 中的 selectedThreadId 映射 |
| restore 替换全部项目状态 | applyStatesReplacement → _rebuildThreadMappings | 只替换 state 而忘记 map；由 Runner 再建一份 map |
| 页面提交/展开状态提交 | applyProjectState → _registerStateThreadMappings | 将 map 改成“仅当前页条目”，误删窗口外显式登记 |
| Shell 登记 session / 选择已有 thread | registerThreadMapping / applyThreadPrepend / applyThreadSelection | 要求每个 thread 必须先被 Provider 列表查询发现 |
| retainProjects | applyProjectsRetention 清被移除 project 的映射 | 清所有项目映射，影响后台仍开着的 project |
| archive/unarchive/delete 成功 | applyThreadRemoval 更新列表并清目标映射 | Runner 独立 remove 映射，产生两种删除时点 |
| close | Store 清 map；Runner 清 I/O 调度字段 | autoDispose 或 UI 不再 watch 时回收业务资源 |

StateOwner 现有接口已具有写回列表所需的 typed ingress。确定增加一个中立查询，供 Runner 统一读取当前摘要；其余签名不因本章更名。下面是“需保留与可能新增部分”的可实现接口草图，不是宣称当前代码已有新成员：

~~~dart
abstract interface class ProjectThreadsStateOwner {
  Map<String, ProjectThreadListState> get states;
  ProjectThreadListState stateFor(String projectPath);

  // 新增：保持现有 _providerIdForThread 的 first-match 行为。
  // 不返回/暴露 map；不根据当前 active provider 猜归属。
  AgentThreadSummary? threadFor(String projectPath, String threadId);

  void applyStatesReplacement(Map<String, ProjectThreadListState> states);
  void applyProjectsRetention(List<String> projectPaths);
  void applyProjectState(String projectPath, ProjectThreadListState state);
  void applyThreadSelection(String projectPath, String threadId);
  void applyThreadSelectionClear(String projectPath);
  void applyAllThreadSelectionsClear();
  void applyThreadPrepend({
    required String projectPath,
    required AgentThreadSummary thread,
  });
  void applyThreadRunning({
    required String projectPath,
    required String threadId,
    required bool isRunning,
  });
  void applyCompletedThreadDismissal({
    required String projectPath,
    required String threadId,
  });
  void applyThreadRuntimeStatus({
    required String projectPath,
    required String threadId,
    required AgentThreadRuntimeStatus status,
    required bool waitingOnApproval,
    required bool waitingOnUserInput,
  });
  void applyThreadTitle({
    required String projectPath,
    required String threadId,
    required String? title,
  });
  void applyThreadPreview({
    required String projectPath,
    required String threadId,
    required String preview,
  });
  bool applyThreadRemoval({
    required String projectPath,
    required String threadId,
  });
  void operationSucceeded(OperationId operationId);
  void operationFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  );
  void forkSucceeded(OperationId operationId, AgentSession? session);

  // 现有 subscribe 暂留，留待 WP-3P 清理发布机制。
  void Function() subscribe(void Function() listener);
}
~~~

确定新增 threadFor，把现有摘要查询收回 owner；Runner 统一使用该入口，不再自行扫描或新增 provider ownership cache。StateOwner 测试固定当前查找口径。

~~~dart
// 仍在现有 Store 中；不先改成 Notifier。
AgentThreadSummary? threadFor(String path, String threadId) {
  return _threadById(stateFor(path), threadId);
}

void applyProjectState(String path, ProjectThreadListState next) {
  if (_closed) return; // 迟到 ingress 不复活已关闭的派生索引。
  _dispatch(ProjectThreadStateApplied(path, next));
  _registerStateThreadMappings(path, next);
}

void applyStatesReplacement(Map<String, ProjectThreadListState> next) {
  if (_closed) return;
  _dispatch(ProjectThreadStatesReplaced(next));
  _rebuildThreadMappings();
}

// 显式窗口外归属继续允许保留；不能用“只遍历 state.threads”代替。
void registerThreadMapping(String path, String threadId) {
  if (_closed) return;
  _projectPathByThreadId[threadId] = path;
}
~~~

本阶段保留 Store 现有通知时点和 reducer intent 顺序；不借收口变更微任务/帧合并策略。关闭检查只保证在途回流不再改变已关闭索引，外部新命令的既有 _ensureOpen 行为保持。

### 4.2 providerId + threadId 碰撞边界

当前项目并未在整个 Project Threads 模型中采用复合键：map 的 key、selectedThreadId、runningThreadIds、completedThreadIds、去重 helper 与 v4 selectedThreadIdsByProject 都是裸 threadId。仅把 Runner 的一张 map 改成 providerId+threadId，无法同时解决同项目下两个 Provider 同 id 的选择、去重、运行态和恢复歧义。

本章不把该问题变成第七项功能改造：

- 保留现有持久化 v4、字段名、String id、现有列表查找/去重口径，不添加键编码字符串、不改用户旧文件。
- 不把 activeProviderId 当作缺失 providerId 的推断依据；正常远端操作继续从摘要中读取已有 providerId。
- 不声称本章解决了跨 Provider raw id 碰撞；验证样本至少覆盖多个 Provider、不同 threadId 的隔离，但这不能证明任意同 id 输入也受支持。
- 若实施期间实际重现碰撞，记录脱敏输入和受影响入口，建立独立后续任务。完整修复必须成组涉及列表 key、Shell/Widget 参数、合并策略、运行标志和持久化恢复，不混入本章提交。
- 未来若引入复合 key，应使用明确的值对象/record；不得通过分隔符拼接然后再拆字符串。该项是后续设计约束，不是当前验收项。

## 5. Runner 执行伪代码与竞态边界

### 5.1 远端操作读 owner，提交 owner

~~~dart
Future<T?> _runForThread<T>({
  required String projectPath,
  required String threadId,
  required Future<T> Function(AgentProviderBundle bundle) operation,
}) async {
  await providerController.loadSettings();
  // 统一从 StateOwner 查询；语义与当前扫描列表一致。
  final summary = stateOwner.threadFor(projectPath, threadId);
  final ownerId = summary?.providerId;
  if (ownerId == null || !providerController.isProviderEnabled(ownerId)) {
    return null; // 本章保持现有结果；不顺手改 typed outcome。
  }
  final config = providerController.providerConfigById(ownerId);
  if (config == null) return null;
  return globalRuntime.run(config, (runtime) => operation(runtime.bundle));
}

void _removeThreadFromList({
  required String projectPath,
  required String threadId,
  required bool notifyCleared,
}) {
  if (_disposed) return;
  final cleared = stateOwner.applyThreadRemoval(
    projectPath: projectPath,
    threadId: threadId,
  );
  // 不再维护 _projectPathByThreadId：Store 已执行唯一的映射清理。
  if (cleared && notifyCleared) {
    onActiveThreadCleared?.call(projectPath, threadId);
  }
}
~~~

能力校验、归档/删除/分叉权限快照的既有实现平移保留；没有必要为消除重复同步 API 改动 Provider bundle 端口。WP-6 处理 sessionConfig 的明确能力结果，不与此处 _runForThread 的既有返回语义混为一项。

### 5.2 分页与恢复保留调度，只移除重复登记

~~~dart
void _restoreSession(RestoreProjectThreadsEffect effect) {
  final plan = buildProjectThreadsRestorePlan(
    projectPaths: effect.projectPaths,
    activeProjectPath: effect.activeProjectPath,
    snapshot: effect.snapshot,
  );
  stateOwner.applyStatesReplacement(plan.states);
  // 删除旧的 for(plan.states) _registerStateThreadMappings(...)
  for (final path in plan.projectsToLoad) {
    unawaited(_loadInitial(path));
  }
}

Future<void> _loadPage(/* 原参数不变 */) async {
  // 保留原加载中判断、token 分配与 loading state 提交。
  final token = /* 当前项目本轮 token */;
  try {
    final page = await _listThreadsAcrossProviders(/* 原查询参数 */);
    if (_disposed || _loadTokens[projectPath] != token) return;
    final latest = stateOwner.stateFor(projectPath);
    // 原全失败保缓存、append/replace、runtime 保留、展示字段合并逐字保持。
    final next = /* 使用现有 pure helpers 得到新的 ProjectThreadListState */;
    stateOwner.applyProjectState(projectPath, next);
    // 删除 _registerThreadSummaries(projectPath, page.threads)。
    // Store 的 applyProjectState 按最终提交态补齐同一份映射。
  } catch (error, stackTrace) {
    if (_disposed || _loadTokens[projectPath] != token) return;
    // 保留原脱敏日志、缓存与用户可见错误目录；原文不进入持久化。
    stateOwner.applyProjectState(projectPath, /* 原失败态 */);
  }
}
~~~

上述伪代码中的“原 helper”指现有 _appendUnique、_replaceWithPageKeepingRuntimeThreads、_preferLocalDisplayFields、_projectThreadsForZetaOwnedRuntime；四者均未在 Store 中另有一份相同实现，本章保留一份，不增加转发层。

### 5.3 关闭、retain 与迟到结果

- Runner.close 继续设置 _disposed、清 _loadTokens、取消全部搜索 Timer；不再清已删除的 Runner map。
- Store.dispose 继续关闭业务 owner、清 listeners/map/completers，并调用 effectRunner.close。当前未完成 void Future 完成、fork Future 完成 null 的语义保留，不能顺手改成取消异常。
- Store.operationSucceeded/Failed/forkSucceeded 继续按 OperationId 结算；重复结果按原 stale 计数规则处理。关闭后 typed ingress 不改 state、不更新 map、不再触发移除选中项的外部回调。
- retainProjects 由 Runner 清 removed project 的调度资源，由 Store 清该 project 的列表事实/反查映射；仍保留其他后台项目。
- 不删除 _loadTokens，也不把它换成“当前 Widget mounted”判断；Runner 是 provider 外的异步编排对象，这些 token 是必要的竞态防护。
- 原有同项目查询相互覆盖策略、search/archived 切换与在途请求策略保持；如重现 token 复用或遗漏重载问题，应单列缺陷，不通过本章偷偷重写分页状态机。

## 6. 开发步骤与文件清单

### T0 · 冻结生产入口与测试归属

- 记录 Shell 构造及 registerSession / syncRuntimeSnapshot 的真实接收者。
- 保存本章 §7 的 33 条旧测试映射表，逐条标注唯一目标位置。
- 当前工作区 release 相关未提交修改属于用户/其他任务。执行前记录其文件与 diff，后续不得格式化、覆盖、提交或回退这些文件。
- 先运行本章对应窄测试作基线；若失败，记录已存在失败并单独分析，不能调低断言来推动迁移。

### T1 · 让同步业务测试走 Store

- 使用现有 Store 构造 + recording effect runner；同步命令测试断言不变，只替换被测入口。
- 统一注入固定 _now，验证 registerSession / running 晋升时间；不再为了旧 Runner 的 DateTime.now() 写宽泛时间断言。
- 保留生产入口行为说明；测试原来的多个 Provider fixture 不得合并成单 Provider 以减少装配。

### T2 · 收口映射与查询端口

- 按 §4 复核 Store 对 initial/restore/page/register/remove/retain/close 的映射维护。
- 增加 StateOwner.threadFor，并让 Runner 的 _providerIdForThread 委托该查询或直接移除该私有扫描包装。
- 删除 Runner map 之前，先将 restore/page/retain/remove 四条路径连接到已经能维护 map 的 Store ingress；不能先删 map 再以编译通过猜测行为完整。
- 保留窗口外显式映射的回归；避免将 index “优化”为每页重建。

### T3 · 删除重复实现并收缩 Runner API

- 删除 §3.1 全部重复业务实现；Runner 内保留 §3.2 effect 执行实现与必要 pure helper。
- 可以将 loadInitial 等执行 helper 改为私有，但不改 effect 类型、OperationId 参数和完成顺序。
- ProjectThreadsOperations 继续由 Store 实现，Shell 无需换接收者。
- 现有 _DeferredProjectThreadsSliceRunner 与 presentation 镜像本章暂留，明确由 WP-3P 删除；不能在 WP-4 偷先迁 Notifier，也不能使 WP-4 依赖 WP-3P。

### T4 · 将 I/O 与状态共同验证到生产组合入口

- 旧跨 Provider 列表、rename/archive/fork 等测试改经 ProjectThreadsSliceComposition.create(...).store。
- 测试 harness 可以复用依赖，但不得暴露一套不经过 Store.run effect 的“测试专用业务 Controller”。
- 保留 fake Provider 与 wire/query 参数断言；并观察最终 Store state 和 Future 结算。

### T5 · 守卫、全量与交接

- 新增窄的结构守卫，确保 Runner 不再声明 §3.1 的同步业务方法及第二张归属 map；守卫使用 AST/类成员检查并带正反例，不只靠字符串计数。
- 更新工程文档中 Project Threads owner/runner 分工；把“Notifier 迁移待 WP-3P”登记进总索引，避免宣称手写镜像已清零。
- 全量收尾通过后再将 WP-4 标为完成，并交给 WP-3P；验收记录列实际命令、退出码、测试结果、断言迁移核对及用户文件未改证明。

| 操作 | 文件 | 具体内容 |
|---|---|---|
| 改 | lib/src/app/project_threads_slice/project_threads_slice_runner.dart | 删除重复同步方法/map；保留真实 effect 及 loader；远端归属查询只读 owner |
| 改 | lib/src/features/project_threads/application/project_threads_state_owner.dart | 新增 threadFor 查询；现有 typed ingress 保持 |
| 改 | lib/src/features/project_threads/application/project_threads_slice/project_threads_slice_store.dart | 实现唯一查询；复核 map 生命周期；同步业务仍留本文件 |
| 原则不改 | lib/src/features/project_threads/application/project_threads_operations.dart | 用户动作签名保持；若有调整必须给出真实必要性与全部调用闭包 |
| 原则不改 | project_threads_slice_intent.dart / project_threads_slice_effect.dart / project_threads_slice_reducer.dart | 不为删除重复 Runner API 重写 MVI 状态机 |
| 原则不改 | lib/src/app/project_threads_slice/project_threads_slice_composition.dart | 保留现有生产构造入口；测试统一调用它；Deferred 留给 WP-3P |
| 改 | test/src/features/project_threads/application/project_threads_slice_store_test.dart | 接收所有同步业务回归；保留原断言含义 |
| 改 | test/src/app/project_threads_slice/project_threads_slice_runner_test.dart | 通过真实 composition.store 验证查询与生命周期 effect |
| 删或收缩 | test/src/features/project_threads/application/project_threads_slice_runner_test.dart | 33 条测试逐一有去向后删除；若仅剩独立 pure helper 测试则重命名到对应 helper |
| 新增 | test/src/features/project_threads/application/project_threads_session_snapshot_codec_test.dart | 接收不依赖 Runner 的 snapshot/restore plan 纯测试 |
| 新增 | test/src/architecture/project_threads_state_owner_guard_test.dart | Runner 业务 API/map 的正反例结构守卫；保护面只针对本 feature |
| 按需改 | test/src/testing/ 下的 Project Threads harness | 共用真实 composition，不引入第二份业务实现 |
| 只核验 | test/src/app/ide_shell_controller_test.dart、test/src/features/project_threads/presentation/project_threads_widget_test.dart、test/src/features/ide_session/presentation/ide_session_restore_widget_test.dart | 真实入口、导航/恢复、关闭/选中等集成回归继续成立 |
| 不改 | lib/src/features/ide_session/domain/ide_session_state.dart 及 v4 codec | 本章不迁持久化结构 |

## 7. 旧测试迁移清单

以下名称和行号来自当前旧 Runner 测试文件。迁移只改接收者、装配和测试归档位置，不减少断言。如果某断言确实依赖旧 Runner 的非生产时间行为，应改为生产 Store 的固定注入时钟，并在开发记录逐条说明，不以“测试通过”掩盖替换。

目标缩写：S = Store 单元测试；I = 真实 composition.store 的 app 集成测试；C = session snapshot codec 纯函数测试。

| 旧行号 | 旧测试名称 | 目标 | 必留观察点 |
|---|---|---|---|
| 22 | restores expanded active project and loads first 5 threads | I | 恢复展开、真实 effect、首屏 5 条 |
| 47 | loads more with aggregate cursor and appends unique threads | I | 聚合 cursor、追加、去重 |
| 74 | keeps cached threads when reload fails | I | Provider 失败不清旧缓存 |
| 97 | keeps a current session when an earlier initial load omits it | I | 可控 Completer；先加载后新建的竞态 |
| 134 | keeps local provisional title when Grok list returns same id without title | I | 列表弱标题/preview 的合并 |
| 182 | tracks running thread ids from conversation runtime snapshots | S | 运行边沿、清状态 |
| 227 | syncRuntimeSnapshot updates thread preview beside title | S | title 和 preview 独立更新 |
| 271 | syncRuntimeSnapshot ignores placeholder New thread title for all providers | S | 多 Provider、占位与正式标题 |
| 327 | registerSession drops session placeholder title so list title stays empty | S | 占位 title 不成为正式名 |
| 350 | promotes an existing thread to the top when a turn starts | S | 原有晋升规则、固定时钟 |
| 406 | setThreadRunning promotes mapped thread on idle-to-running edge | S | 显式映射、运行边沿 |
| 447 | applies waiting flags from runtime snapshots to list state | S | waiting 标志与终态清理 |
| 498 | ignores duplicate loads while a project is already loading | I | single-flight/现有加载中判断 |
| 517 | sorts all provider threads by global recency | I | 多 Provider 及稳定排序 |
| 567 | builds snapshot from current list states | C | 先用普通 state 构建，字段断言不变 |
| 587 | builds restore plan from session snapshot | C | 恢复展开与 projectsToLoad |
| 609 | restore plan only keeps the first five cached threads | C | 历史缓存窗口收缩为 5 条 |
| 630 | restore plan keeps only one selected thread across projects | C | preferredProjectPath 与全局唯一选择 |
| 648 | selectThreadId clears selection in other projects | S | 多 project 选择互斥 |
| 663 | passes archived and searchTerm to listThreads | I | 保留真实 query 参数断言 |
| 685 | renames thread through global runtime and updates cached title | I | 正确 Provider、远端调用、Store title |
| 705 | removes archived thread and notifies active clear | I | 移除后回调且只一次 |
| 727 | caches provider ownership when a session is created | I | Store 登记后，异步远端操作读取正确摘要归属 |
| 754 | registerSession can optimistically mark the new thread running | S | markRunning、选择、摘要 |
| 774 | setThreadRunning toggles list busy indicator for mapped threads | S | 窗口外/显式映射不丢失 |
| 798 | background turn completion marks completed icon until dismissed or selected | S | 后台完成、dismiss、选择清理 |
| 852 | syncRuntimeSnapshot keeps multiple background thread states | S | 多后台任务互不覆盖 |
| 910 | selected thread turn completion clears list busy when status lags active | S | 终态与迟到 active |
| 972 | setThreadRunning false clears sticky active status on list summary | S | 只变 running 也清残留 active |
| 1010 | syncRuntimeSnapshot keeps waiting flags while turn still active | S | 等待语义保持 |
| 1045 | fork makes provider default source explicit when no pane is open | I | 明确 Provider fallback 来源 |
| 1081 | fork without Binding uses the persisted provider default | I | 真实 permission snapshot 参数 |
| 1134 | fork 优先使用已存在 Binding 的 thread 权限快照 | I | Binding 优先及 G5 不变 |

额外补齐的少量、有意义验收：

1. Store initialState 与 restore 后，不经 Runner 同步 API，setThreadRunning 仍找到正确 project。
2. 接收分页结果后，Store 的运行态查找生效；显式登记但暂不在当前分页窗口的映射不会被清掉。
3. retain project A 后，不再通过其映射改动 A；project B 的映射和后台状态保留。
4. 关闭后送回 page / operation / fork 结果，state 不变、map 不复活、Future 不二次结算、onActiveThreadCleared 不触发。
5. 同步业务不产生 Provider effect；远端操作必须通过 Store effect，测试不能通过 Runner 的另一套业务 API 达成同样结果。

不要专为“方法被删除了”写一排脆弱源码字符串测试；结构守卫负责 API 形状，行为回归负责用户语义。

## 8. 验收、测试门禁与回滚

### 8.1 完成条件

- [x] Shell 的 ProjectThreadsOperations 实现仍只有生产 Store，所有旧同步业务回归从同一入口调用。
- [x] §3.1 Runner 重复方法与重复 map 全部清除；Runner 的真实 effect 分支和 loader 保护保持。
- [x] Store 的 initial / restore / page / explicit mapping / remove / retain / close 维护全部核对。
- [x] 旧测试 33 条逐条有目标，关键断言不删除；新增回归覆盖异步结果与唯一映射的接合处。
- [x] sessionStateVersion=4、字段名、Provider id/type、分页 5/10/50、search 300 ms 保持。
- [x] G4/G5 能力与权限路径不放宽；没有 Provider wire 字段进入 application/domain。
- [x] 列表选中/完成提示/标题/预览/排序语义由真实 Store + 真实 effect 组合验证。
- [x] 总索引明确 WP-4 完成、WP-3P 待执行；不把尚存的 Deferred/镜像标成已移除。

### 8.2 必须执行的门禁

开发循环先定向运行真正相关的测试；以下路径以迁移后实际文件为准，删除旧文件必须同时更新命令记录。

~~~sh
flutter test test/src/features/project_threads/application/project_threads_slice_store_test.dart test/src/features/project_threads/application/project_threads_session_snapshot_codec_test.dart test/src/app/project_threads_slice/project_threads_slice_runner_test.dart
flutter test test/src/app/ide_shell_controller_test.dart test/src/features/project_threads/presentation/project_threads_widget_test.dart test/src/features/ide_session/presentation/ide_session_restore_widget_test.dart
flutter test test/src/architecture/project_threads_state_owner_guard_test.dart test/src/architecture/feature_layering_guard_test.dart
~~~

收尾按根 AGENTS.md 顺序：

~~~sh
dart format .
flutter analyze
bash tool/test_affected.sh
bash tool/test_full.sh
git diff --check
~~~

本章是重构，受影响测试不能代替全量门禁。当前 tool/test_full.sh 已包含根测试和内部 Package 测试，完成一次即可，不额外机械重复 test_packages.sh。若变更了测试基础设施/守卫选择器本身，也必须全量收尾。真实 CLI 非本章必要验收，因为未改协议；如实施过程中越界改了 adapter，则必须退出本章范围，按对应 Provider 规则单独立项与真实 CLI 验收。

设计编制阶段未执行上述门禁；实际实现与验收证据另记在 §10，不以设计要求代替测试结果。

### 8.3 可回滚单元

- 建议 WP-4 分为“测试迁移验证 + API/map 收口”一个可独立交付提交；若规模需拆成两个提交，第一个仅增加/迁移等价测试，第二个删除旧 API，二者各自必须可运行且全量通过。
- 回滚时回退整组代码与相应测试入口，不仅恢复 Runner 方法、却留下指向新 StateOwner 查询的半套组合。
- 若 WP-3P 尚未开始，可直接 revert WP-4 提交；若 WP-3P 已以本章为基线，应先回退 WP-3P 或为当前 Notifier 做前向修复，不能将旧 Store/Runner 双轨拼回新 owner。
- 不触及 Provider 协议及持久化格式，因此无需用户数据迁移或数据回滚；禁止删除用户 ~/.zeta 数据来“验证恢复”。
- 回滚范围必须排除开始任务时已存在的 release workflow、CHANGELOG、release guide、package_macos.sh 修改；不使用 reset --hard、checkout . 或宽泛 git add .。

## 9. 与六项整体计划的依赖

本节供总索引整合；不新增第七项任务。

| 工作项 | 必须前置 | 可先独立完成的范围 | 交接契约 |
|---|---|---|---|
| WP-6 sessionConfig 显式能力结果 | 无 | sessionConfig capability/typed outcome 与调用端错误行为 | WP-2 使用该明确结果，不再在 UI 猜“成功但没生效” |
| WP-1 多 Provider 管理运行状态聚合 | 无需等待 WP3 | 从当前 workspace entries 构造不可变的 per-provider 运行态快照 | WP-3C 只更换快照来源，WP-3M 保持同一消费端口 |
| WP-4 本章 | 无 | 现有 Store 收口；保留当前发布/装配 | WP-3P 搬迁已经唯一的业务 owner |
| WP-3M management owner | WP-1 的运行态快照契约先固定 | 迁移管理 Store/监听/Deferred | WP-5 复用管理单 owner |
| WP-3P Project Threads owner | WP-4 完成 | 将本章唯一 Store 迁 application Notifier | 保留本章生产测试入口和业务断言 |
| WP-3C conversation workspace owner | WP-1 的快照契约先固定 | composition/registry 迁移，保持 Binding/entry/runtime 身份 | WP-2 使用稳定命令入口；WP-1 聚合输出不变 |
| WP-2 Conversation UI 统一命令入口 | WP-6 + WP-3C | 真实 UI 改为同一 typed commands，不绕过 scope/能力结果 | 审批/问题/Plan 执行四种语义保持 |
| WP-5 首页探测单 owner | WP-3M | 首页与管理页复用同一探测事实/初始化 | 不另建 homepage 缓存/监听 owner |

建议串行落地顺序：WP-6 → WP-1 → WP-4 → WP-3M / WP-3P / WP-3C → WP-2 → WP-5。WP3 的三个分支逻辑上可独立，落地时会共同修改组合根与测试助手，建议先冻结公共 provider/override 契约再串行整合，不用“可并行”掩盖同文件冲突。

WP-1 不依赖 WP3 的理由：当前 workspace entries 已存在，WP-1 只需要一个只读聚合投影。先定义 provider 无关的快照端口，在现有 owner 上实现；WP3 迁移时保持端口值语义与测试不变即可。不应让 WP-1 先要求新 Notifier，再让 WP-3M 等 WP-1，形成循环。

全计划门禁建议：WP-1/WP-6 若为窄行为修复，开发与收尾至少 format/analyze/affected；若同时搬文件或调整测试基础设施，则升级 full。WP-4、WP3 各分支、WP-2、WP-5 都涉及职责/调用链收口，按重构收尾 full。每个工作项保存自己的测试入口与行为冻结清单，最终整组再对所有已落地变更执行一次全量 gate。代码不变的当前文档交付只做链接、文件存在、依赖 DAG 和内容一致性核验，不跑 Flutter 全量。

现有计划模板可以沿用：总索引列目标、现状证据、决策、WP 表、依赖和开发记录；每章列状态/依赖/性质、逐步任务、伪代码、风险、DoD、验证记录。2026-09-03 旧计划曾将某些镜像模式登记为迁移方案，不应复制其历史豁免作为新规则；当前根 AGENTS.md 优先。根 AGENTS.md 引用的 docs/prompts/refactoring.md 在当前目录不存在，实施时应在总索引记录此文档缺口，按当前 AGENTS.md 的明确全量重构约束执行，而不是猜测旧文件内容。


## 10. 2026-09-06 实施与验收

实现提交待登记；[完整验收记录](../../refactor/2026-09-06-project-threads/00-validation.md)。

Runner 同步业务与第二张索引已删除，Store 提供唯一 `threadFor` 查询并保护关闭后索引及移除回调。33 条旧测试按 §7 分配到 S 15 / I 14 / C 4，131 条原断言经 AST token 比对完整保留；新增 14 条行为回归和 4 条带正反例的结构守卫。定向 59 条及 Shell/Widget/分层 45 条通过；format / analyze / affected / full / diff check 全部通过，full 包含根 2007 条及内部包 1076 条（内部包分析全部通过）。收尾详情及首次遥测失败的处理见验收记录。

本次开始时工作区干净；设计中的历史 release 未提交变更已不适用。Provider 包、权限策略、操作签名、intent/effect/reducer、5/10/50 分页、300 ms 防抖、v4 与裸 threadId 均保持。当前 Deferred、Store listener、presentation 镜像留待 WP-3P；串行队列下一项为 WP-3M。

# Agent 桌面通知与任务栏未读提醒详细设计

最后更新：2026-08-04

## 1. 背景与目标

Agent turn 可能在用户切换项目、打开设置页或最小化 Zeta 后才结束；
权限审批、用户问题和计划交接又会阻塞当前工作流。本功能将这些 Provider
中立事件统一映射为用户注意力信号，并在目标会话不可见时提供：

- Windows、macOS 和 Linux 系统通知；
- Windows 任务栏闪烁、macOS Dock 未读角标、Linux urgency 提醒；
- 通知点击后恢复窗口并打开对应 Provider thread；
- 任务终态和需要确认两类通知的独立开关。

设计不改变 Provider 审批语义，不自动批准命令、文件或网络操作，也不把
Zeta 本地 Plan 执行交接视为 Provider 计划审批。

## 2. 范围

### 2.1 事件范围

| 业务场景 | `AgentAttentionKind` | 触发 | 解决 |
| --- | --- | --- | --- |
| turn 成功 | `turnCompleted` | 收到归一化成功终态 | 用户打开该 thread |
| turn 失败 | `turnFailed` | 收到归一化失败终态 | 用户打开该 thread |
| turn 中断 | `turnInterrupted` | 收到归一化中断终态 | 用户打开该 thread |
| 权限审批 | `permissionRequired` | permission requested | request resolved 或本地提交决策 |
| 用户问题 | `questionRequired` | question requested | request resolved 或本地提交答案 |
| Provider 计划审批 | `planApprovalRequired` | plan approval requested | request resolved 或本地提交决策 |
| Zeta 计划执行交接 | `planExecutionRequired` | 成功 Plan turn 产生非空计划 | 执行、继续修订或关闭交接 |

### 2.2 非目标

- 不在操作系统通知中展示 prompt、回复、命令、文件路径、问题原文、
  错误原文、凭证或 Provider raw payload。
- 不持久化未读列表；未读是当前应用进程的派生 UI 状态。
- 不在 domain 层引入任何 Flutter plugin 或平台 API。
- 不保证操作系统通知中心与 Zeta 内部未读在插件撤回失败时完全一致。

## 3. 用户体验规则

### 3.1 可见性抑制

仅当以下条件同时成立，才认为用户正在直接查看目标会话：

1. Zeta 窗口获得焦点；
2. Workbench Canvas 当前是 Agent 首页，而不是全局首页、设置或用量统计；
3. 当前常驻 entry 的 `providerId` 和 `threadId` 与信号相同。

满足时不发系统通知，并将该 thread 已有的进程内未读清除。只要有一个条件
不满足，即可以产生通知。

### 3.2 标题与正文

通知标题只表达类别，例如“任务已完成”或“需要确认权限”。正文固定为：

```text
<项目目录名> · Agent 会话
```

仅取 `projectPath` 最后一段；不展示完整路径或 thread 标题。

### 3.3 点击行为

1. 恢复已最小化窗口，执行 show/focus；
2. 按 `providerId + threadId` 在项目 thread 状态和常驻 workspace entry 中定位；
3. 必要时加载项目并选中 thread；
4. 切回 Agent 首页并关闭 Workbench overlay；
5. 定位成功后清除该 thread 全部未读；定位失败时清除该条陈旧信号并显示
   IDE 错误 Toast。

## 4. 总体架构

```text
Provider data adapter
  -> normalized AgentEvent
    -> AgentConversationReducer
      -> AgentTurnCompletedEffect / AgentAttentionEffect
        -> AgentConversationEffectRunner
          -> AgentConversationViewModel
            -> AgentThreadWorkspaceController（补 provider/project/thread 上下文）
              -> IdeShellController callback
                -> DesktopAttentionController
                   |-- GeneralSettingsController
                   |-- DesktopNotificationService
                   |     -> flutter_local_notifications
                   |-- DesktopAttentionIndicator
                   |     -> zeta/desktop_attention MethodChannel
                   `-- IdeHome visibility + target activator
```

依赖方向为 `presentation/application -> domain`、`data -> domain`、`app -> data`。
`DesktopAttentionController` 只依赖端口，既不依赖 Widget，也不识别 Codex/Grok 原始协议。

## 5. 核心模型

### 5.1 `AgentAttentionSignal`

| 字段 | 说明 |
| --- | --- |
| `kind` | 业务类别 |
| `phase` | `raised` 或 `resolved` |
| `sourceId` | turn ID 或 request ID，用于幂等去重和精确清除 |
| `threadId` | Provider thread 标识，可由 ViewModel 补齐 |
| `turnId` | 可选的关联 turn，用于 Plan 交接判定 |

幂等标识：

```text
<kind>:<providerId>:<threadId>:<sourceId>
```

不使用到达时间作为 identity，因为 Provider 重连、重放或 reducer 重复投递不应创建
第二条通知。

### 5.2 `AgentWorkspaceAttention`

Workspace 层在不改写 signal identity 的前提下补充 `providerId` 和 `projectPath`。
它不携带 thread 标题或对话内容，以避免 prompt 派生标题流入系统通知链路。

### 5.3 端口

```dart
abstract interface class DesktopNotificationService {
  Future<String?> initialize({required DesktopNotificationActivation onActivate});
  Future<bool?> requestPermissions();
  Future<void> show(DesktopNotificationRequest request);
  Future<void> cancel(int id);
  void dispose();
}

abstract interface class DesktopAttentionIndicator {
  Future<void> setUnreadCount(int count);
  Future<void> requestAttention();
}
```

Widget 测试和非原生窗口宿主使用 Noop 实现，避免 MethodChannel 或系统权限污染测试。

## 6. 事件处理与状态机

```text
                raised + enabled + not visible
Absent ----------------------------------------------> Unread
  ^                                                        |
  | resolved / visible thread / notification activation    |
  +--------------------------------------------------------+

Unread -- duplicate identity --> Unread（no-op）
Unread -- category disabled --> Absent + cancel system notification
```

`DesktopAttentionController` 以 `Map<String, _UnreadAttention>` 保存进程内未读：

1. `resolved` 优先处理，不受开关和可见性影响；
2. 关闭总开关或对应分类时不接受新信号；
3. 目标 thread 可见时抑制新通知；
4. identity 已存在时 no-op；
5. 首条未读使任务栏/Dock 请求用户注意，并在支持角标的平台同步未读数；
6. 系统通知失败只写脱敏日志，内部未读仍是权威状态。

本地 Plan 完成时，ViewModel 在 effect 执行前已建立
`AgentPlanExecutionRequest`。若成功 turn 与当前交接的 `turnId` 一致，则将普通
`turnCompleted` 替换为 `planExecutionRequired`，避免一个 Plan 终态产生两条通知。

## 7. 协议与 Provider 边界

通知功能不直接订阅 app-server/ACP，而是复用已有 data adapter 归一化的：

- `AgentTurnCompletedEvent`；
- `AgentPermissionRequestedEvent` / `AgentPermissionResolvedEvent`；
- `AgentQuestionRequestedEvent` / `AgentQuestionResolvedEvent`；
- `AgentPlanApprovalRequestedEvent` / `AgentPlanApprovalResolvedEvent`。

因此新 Provider 只要按现有领域契约映射事件，不需要修改未读 Store 或增加厂商分支。

Codex 方面以仓库 `0.144.5` stable schema pin 为审查基线，Plan/问题仍遵循现有
experimental 能力探测和宽容降级，见
[Codex app-server 协议版本锁定](./codex_app_server_protocol.md)。本功能未增加或猜测任何
app-server 原始 method。

## 8. 系统通知实现

`FlutterDesktopNotificationService` 基于 `flutter_local_notifications`：

- 初始化时注册 activation callback；
- macOS 在总开关开启时请求 alert/badge/sound 权限；
- Windows 使用固定 AppUserModelId 和 GUID；
- Linux 使用默认动作“打开 Zeta”和 normal urgency；
- 通知 payload 只包含版本、`providerId`、`threadId` 和 identity。

Payload 示例：

```json
{
  "version": 1,
  "providerId": "codex",
  "threadId": "thread-id",
  "identity": "permissionRequired:codex:thread-id:request-id"
}
```

解码采用白名单和类型校验，未知版本、空 payload 或损坏 JSON 直接忽略。

## 9. 任务栏、Dock 和窗口提醒

Dart 端通过 `zeta/desktop_attention` MethodChannel 调用：

| Method | 参数 | 语义 |
| --- | --- | --- |
| `setUnreadCount` | `{ "count": int }` | 同步进程内未读数，负数按 0 处理 |
| `requestAttention` | 无 | 在第一条未读出现时请求用户注意 |

### 9.1 Windows

- `FlashWindowEx(FLASHW_TRAY | FLASHW_TIMERNOFG)` 请求任务栏闪烁；
- 不使用 `ITaskbarList3::SetOverlayIcon`，任务栏图标不显示红点或未读数；
- `setUnreadCount` 在 Windows Runner 中仅返回成功，用于保持跨平台
  MethodChannel 契约。

### 9.2 macOS

- `NSApp.dockTile.badgeLabel` 展示数字，大于 99 显示 `99+`；
- `NSApp.requestUserAttention(.informationalRequest)` 请求 Dock 提醒；
- 未读为 0 时将 badgeLabel 设为 `nil`。

### 9.3 Linux

- GTK `gtk_window_set_urgency_hint` 表示有未读或需要注意；
- 未读为 0 时清除 urgency hint；
- 具体标记展示取决于桌面环境和窗口管理器。

## 10. 设置与持久化

设置页“常规”分区新增：

- 系统通知总开关，默认开启；
- 任务结束，默认开启；
- 需要确认，默认开启。

持久化文件为 `~/.zeta/config/general.json`，`GeneralSettings` 版本由 1 升为 2：

```json
{
  "version": 2,
  "sendMessageShortcut": "enter",
  "notifications": {
    "enabled": true,
    "turnTerminalEnabled": true,
    "actionRequiredEnabled": true
  }
}
```

读取 version 1 时保留原发送快捷键，通知字段使用默认值；字段缺失、类型损坏或
未知版本不阻塞应用启动。运行时关闭分类会同时清理已有同类未读；从关闭
切回开启时重新请求必要的系统权限。

## 11. 异常、竞态与生命周期

- 多个常驻 thread 共享同一协调器，但 identity 含 Provider/thread，不会串话。
- ViewModel 的 effect scope 继续校验 listener generation、runtime/epoch 和 thread；陈旧
  Provider 事件不能产生通知。
- 用户提交本地决策时先发 `resolved`，即使 Provider 回包迟到或丢失，也不留下
  无法操作的陈旧未读。Provider 后续的 resolved 为幂等 no-op。
- 通知 ID 在单进程内单调增加；不用它作业务 identity。
- Controller dispose 时移除设置监听并释放通知 service。应用进程退出后未读不恢复。
- 任务栏或通知插件错误不中断 Agent 事件 pipeline。

## 12. 性能与可观测性

- raised/resolved 去重和删除为平均 `O(1)`；按 thread 标记已读为 `O(n)`，`n` 仅是当前进程
  尚未处理的提醒数。
- 高频 delta、reasoning、tool progress 不产生 attention effect，不进入通知链路。
- 日志使用 `zeta.desktop_attention`，只记录操作名与异常，不记录通知正文和 payload。
- Windows 不创建 overlay icon 或 GDI 资源，仅处理任务栏闪烁请求。

## 13. 测试与验收

| 层级 | 用例 |
| --- | --- |
| domain/application | turn 终态映射正确；request raised/resolved 使用同一 identity |
| coordinator unit | 可见 thread 抑制；后台去重；resolved 撤回；点击定位并清除；分类开关生效 |
| settings unit | version 1 迁移；version 2 容错解码；三个开关持久化 |
| widget | 设置组可见；开关调用 controller；窄视口不溢出 |
| 静态检查 | `dart format .` 与 `flutter analyze` |
| 回归 | `flutter test` |
| 原生构建 | 当前宿主 `flutter build windows`；macOS/Linux 在对应 CI 或实机构建 |

手工验收至少覆盖：

1. 最小化 Zeta 后完成 turn，出现系统通知和平台提醒；
2. 停留在同一 thread 且窗口有焦点时不发通知；
3. 切到其他 thread 时，权限申请产生一条通知；
4. 点击通知恢复正确项目/thread，未读标记清除；
5. 关闭“需要确认”后，新权限/问题/计划事件不再通知；
6. 通知文案和系统日志不含工作区完整路径、命令、prompt 或回复。

## 14. 已知限制与后续扩展

- Windows 仅使用任务栏闪烁提醒，不显示红点或未读数；macOS Dock 继续显示数字角标。
- Linux urgency 的视觉效果依赖 GNOME/KDE 等桌面环境，系统通知依赖 D-Bus 通知服务。
- 进程退出后不恢复未读；如后续需要跨重启恢复，必须先定义通知过期时间、
  request 仍然 pending 的验证方式和不保存敏感内容的版本化结构。
- 若后续增加应用内通知中心，应复用 `AgentAttentionSignal` 和协调器的 identity，不得反向从
  操作系统通知中心推导业务状态。

# Phase 3 第 5 批：Desktop Attention 与 Conversation Workspace

最后更新：2026-08-24

状态：已关批（用户明确要求直接采用目标方案，不建立双路径）

## 1. 范围与不迁清单

迁移 desktop attention 未读状态、conversation workspace entry/选择/project home/
project→thread 映射、entry 同步管线，以及 composer 的 mode/model/skills owner；同时删除
Phase 2 conversation flag 与 ViewModel 直连 fallback。

不迁 Provider wire、event pipeline、TimelineStore、Binding/runtime identity、四种审批模型、
IDE Session v4 schema、页面视觉和插件 contribution。

## 2. Owner 与字段映射

| 现状 | 目标 owner |
| --- | --- |
| controller `_unread` / visibility / notification id | `DesktopAttentionSliceStore.state` |
| controller 系统端口调用与设置订阅 | `DesktopAttentionSliceRunner` |
| workspace controller entries / selected id | `AgentConversationWorkspaceStore.state` + runtime entry registry |
| Shell `_projectHomeActive` | workspace state `projectHomeActive` |
| Shell `_agentThreadIdsByProject` | workspace state `threadIdsByProject` |
| Shell entry listener/snapshot listener 表 | workspace store 的单一 entry ingress |
| 三个 composer ChangeNotifier | `AgentConversationComposerStateOwner` 内部纯 Dart state engine |
| `AgentRegionBuilder` legacy listenable | 永久 Riverpod region selector |

新增业务事实为 0；IDE Session 继续保存相同字段，未读继续不持久化。

## 3. Intent / Effect / Result

- attention intents：initialized、settings changed、visibility changed、attention received、
  thread read、identity removed；effects：request permission、show/cancel notification、
  sync indicator、activate target；异步 activation 只以 typed result intent 回写。
- workspace intents：entry registered/updated/removed、entry selected、project home entered、
  thread mapping set/removed/restored；Binding/ViewModel 构造与释放由 app
  composition 执行，state reducer 不接触 Provider 或 Flutter。
- conversation 原有 command/result intent 与 G5 四条链路不变；composer 目录和选择仍以
  既有 generation/revision 判迟到，只收敛 owner 和监听机制。

## 4. 操作身份与迟到结果

- attention 继续以 `<kind>:<provider>:<thread>:<source>` 幂等；activation payload 只经
  白名单 codec 解码。
- workspace entryId 与 BindingKey 保持稳定；draft 只能原子晋升为 thread。
- mode/model/skills 保留既有 provider/thread generation、selection revision 与 in-flight key。
- conversation command 继续使用 `OperationId + AgentConversationCommandScope` 两次校验。

## 5. 生命周期

| 对象 | 创建者 | 释放者 |
| --- | --- | --- |
| attention store/runner | `MainApp` locale runtime composition | `MainApp.dispose` |
| workspace store/runtime entries | `IdeShellController` app composition | `IdeShellController.dispose` |
| Binding lease/runtime | workspace store → Binding Manager/Registry | entry dispose / Manager / Registry |
| composer owner + conversation slice binding | 每个 workspace entry | entry dispose |
| Riverpod mirrors | 根 ProviderScope / family | 只摘监听，不释放 store/Binding |

## 6. §15 十问答卷

1. 唯一 owner：attention store、workspace store、composer owner；runtime 仍归 Registry。
2. Intent/State/Effect/Result：见 §2–3，副作用结果只经 typed intent 回写。
3. 稳定边界不含 raw Provider；Riverpod 只在 presentation/app，Flutter 不进入 feature application。
4. 创建与释放见 §5；Riverpod autoDispose 不决定 Binding/runtime 生命周期。
5. 迟到判定见 §4，不增加弱于现状的计数器。
6. 根快照只投影计数/identity 关系；正文和 live delta 不进入新 state/rebuild 路径。
7. 不新增缓存；模型/skills 继续使用既有 source/key/invalidation/budget。
8. 持久化白名单和 schema version 均不变；attention 仍为进程内状态。
9. 用户要求本批直接切换：无 flag、无双写、无旧路径；回滚为整体 revert。
10. 证据：既有 70 条基线、纯 reducer/store、selector、Shell/真实 IdeHome 保活、架构守卫、
    affected 与 full test。

## 7. 验收与删除清单

- [x] 删除 `DesktopAttentionController` 与其直接副作用入口；
- [x] 删除 `AgentThreadWorkspaceController` 的 feature application 路径；
- [x] 删除 Shell 的 project home/thread map/entry listener/selected snapshot owner；
- [x] 删除 `conversationSliceEnabled`、`agentConversationSliceEnabledProvider` 与所有
  `legacyListenable` fallback；
- [x] 清零 `feature_layering_guard_test` 中 workspace + mode/model/skills 四个本批条目；
- [x] 真实 `IdeHome` Widget 验证常驻骨架、AgentPane Element、当前 Thread、草稿、滚动、
  Pane 宽度与可见性不重置；
- [x] 完成 format、analyze、affected 与 full gate。

## 8. 回滚

本批无运行时开关。回滚使用版本控制整体 revert；IDE Session v4 与 Provider 数据格式未变，
无需数据迁移或降级写入。

## 9. 关批证据（2026-08-24）

- `dart format .`：819 个文件，0 个待格式化改动；
- `flutter analyze`：0 issue；
- Agent 会话完整 Widget 套件：38/38；`IdeHome` + 根本地化组合：41/41；
- `bash tool/test_affected.sh`：因删除 Dart 文件按规则升级为全量，根 Package 与全部内部
  Package 通过；
- `bash tool/test_full.sh`：根 Package 2370 passed / 0 failed / 0 skipped，聚合
  260.72s；5 个内部 Package 共 70 条测试全部通过；
- 新增纯 reducer、workspace store、根快照与旧路径删除架构守卫均通过。

本批未修改 Provider adapter、wire 或 pinned schema，因此 Codex 协议升级冒烟门禁不触发；
未用测试结果推断真实 CLI 验收。

# Phase 3 第 1 批关批记录：settings 切片

> ⚠️ **历史迁移证据（Phase 4 已完成）。**
> 本文记录的是当时的迁移过程与决策，**不描述当前架构**——其中提到的过渡层、
> 燃尽清单与中间态符号多数已在 Phase 4 删除。
> 当前架构以 [`AGENTS.md`](../../AGENTS.md) 与 [`overview.md`](overview.md) 为准；
> Phase 4 的删除边界见 [`phase4_transition_cleanup.md`](phase4_transition_cleanup.md)。

> 对应 [Phase 3 开工文档 §3](phase3_slice_expansion.md)（设计）与 §9 模板（本文件）。
> §3 是设计意图；本文件是开工清单——补齐依赖图、消费方切换顺序与四步节奏锚点。
> 字段映射、Intent / Effect 语义、§15 答卷在 §3 已答完的，这里只引用不复制。
>
> 规则优先级：`AGENTS.md` > `engineering_standards.md` > Phase 3 开工文档 > 本文件。

---

## 1. 范围与不迁清单

**迁**：`AppearanceSettingsController` / `GeneralSettingsController` 持有的状态与
操作 → 两个 MVI 切片（`AppearanceSettingsSlice` / `GeneralSettingsSlice`，
决策点 B 见 §3.2）；两个切片各一个 NotifierProvider + selector。

**不迁**（本批结束时原样保留）：

| 不动 | 理由 |
| --- | --- |
| `SystemFontCatalogService` 与字体目录加载 | 切片只投影（§3.2 缓存四元组） |
| `GeneralSettingsCodec`（v3）/ `AppearanceSettings.tryDecode`（v1） | codec 与宽容解码零变化（§2.5） |
| `AppearanceSettingsStore` / `GeneralSettingsStore` 端口与实现 | data 层不动；构造参数已是注入形态 |
| 设置页视觉与控件结构 | Phase 3 禁区：不改 UI 视觉 |
| 语言"下次启动生效"语义 | `app.dart` 冻结 locale 的行为不变 |
| 两条持久化语义的统一化 | §3.1：行为零变化是关批条件，统一化另立任务 |

切片文件落位（沿用 Phase 2 的目录形态）：
`lib/src/features/settings/application/settings_slice/`（纯 Dart：state / intent /
effect / reducer / store）与 `presentation/settings_slice/`（Riverpod provider、
订阅接缝）。**application 侧禁止 import Flutter / Riverpod**（§12.5，
`feature_layering_guard_test` 会红）。

## 2. 字段映射与 Intent / Effect

见 [Phase 3 开工文档 §3.2–3.4](phase3_slice_expansion.md)。要点重申：

- 新增业务事实 = **0**；
- `ThemeMode` → `ZetaThemeModePreference` 纯枚举（决策点 A，presentation/app
  层映射回 `ThemeMode`）；
- 语义 A（appearance 乐观）/ 语义 B（general persist-first）如实保留，effect
  与 result intent 的对应关系按 §3.4 表格实现；
- `OperationId` scope：`settings.appearance.persist` / `settings.general.persist`；
  general 的单写者串行语义（现 `_enqueue`）搬到 effect runner。

> **实现勘误（2026-08-23，步骤 1 落地时核对 controller 原文）**：
> 字体选择**不是**乐观语义——`setUiFontChoice` / `setCodeFontChoice` 要先经
> 字体目录异步解析（代码字体要求等宽、界面槽位拒绝 bundled、代码槽位拒绝
> systemDefault），解析失败既不应用也不落盘。切片建模为先解析后应用：
> 登记槽位在途身份（界面/代码两个槽位独立，串行队列语义）→ runner 解析 →
> `Resolved` 回流后才应用+持久化。§3.4 表格已同步修正。
> 另：general 的 persist-first 用「在途值链」复刻串行队列——后续修改基于
> 在途值 `copyWith`，避免丢掉尚未应用的修改。

## 3. 消费方依赖图与切换顺序

> **关批覆盖（2026-08-24）**：下方保留的双路径记录只是迁移历史。
> 当前 `MainApp → IdeHome → SettingsPage` 以及 Desktop Attention 只消费
> slice store；controller、ingress、flag 和 false-path 均已删除。

> **步骤 4 实施记录（2026-08-23 已完成）**：
>
> 1. **单一 body + 写操作集**：两个 pane 各提取一个共享 body 函数（外观以
>    `AppearanceSettingsSlice` 为值类型，旧路径经 `appearanceSliceFromSettings`
>    转换；general 两侧同为 `GeneralSettings`），写操作收进 facade 记录，
>    新旧路径各提供一份实现，杜绝 body 复制。
> 2. **facade 必须按 store 实例缓存**（pane 转 `ConsumerStatefulWidget`）：
>    `_FontChoiceSettingRow.didUpdateWidget` 按 loader 闭包身份重置
>    `_choicesFuture`，闭包每次 build 变身份会导致目录反复重载。
> 3. **字体选择 facade 的 `Future<bool>`**：dispatch 后一次性订阅等 pending
>    槽位清空，成功 = 值发生变化（行级 `_updating` 已保证单飞；被拒绝 →
>    值不变 → false → 行弹错误 toast，对齐现状）。`choicesLoader`：已加载
>    直接返回，否则 `requestFontCatalog` + 等回流。
> 4. **语言失败 toast 保真**：失败回执已带 `operation`（general 切片新增
>    `GeneralSettingsPersistOperation` 维度，2026-08-23 落地）；pane 用
>    `ref.listen` 观察 `lastPersistFailure`，**仅 `operation == language`
>    弹 toast**（其余失败静默 = 现状），随后 `acknowledgeFailure()`。
> 5. **通知源切换**：组合层提供切片版 `AgentNotificationSettingsSource`
>    （`load` 直读 data store 保持可等待语义；`notifications` 读切片状态；
>    订阅接切片 store），`MainApp → IdeHome` 新可选参数注入，null = 旧桥。
> 6. **ide_home general builder**：`Consumer` 分支 `generalSettingsSliceValueProvider`
>    vs 旧 `ValueListenableBuilder`。

当前消费方（迁移源 = 两个 controller；★ = 本批要改造的订阅点）：

```
MainApp (app.dart)
 ├─ 构造两个 controller + 注入 store + 启动 load          ★ 改为构造切片 store（flag 决定）
 ├─ 全局主题构建：ValueListenableBuilder<AppearanceSettings> ★ 改 selector（枚举→ThemeMode 映射）
 └─ → IdeHome (ide_home.dart)
     ├─ 持有并向下传两个 controller；再次触发 load          ★
     ├─ GeneralSettings ValueListenableBuilder（:593 附近）  ★
     └─ → SettingsPage (settings_page.dart)
         ├─ _GeneralSettingsPane（:251 ValueListenableBuilder）★ IdeSelect/IdeTabs/IdeSwitch → Intent
         └─ _AppearanceSettingsPane（:479 ValueListenableBuilder）★ 同上
DesktopAttentionController (desktop_notifications/application)
 └─ addListener 订阅 GeneralSettingsController（:48 附近）   ★ 改注入纯 Dart 回调订阅
```

**切换顺序**（每步独立提交、独立可回退，先易后难）：

1. 切片骨架 + reducer / store 单测（无 UI 接线，零风险）；
2. `DesktopAttentionController` 订阅改造（消费面最小、最隔离）；
3. `app.dart` 主题构建切 selector（顺带落地 `ZetaThemeModePreference` 映射与
   domain 纯化——`knownDomainImpurities` 的 settings ×3 在此步清零）；
4. `ide_home` / `SettingsPage` 两个 pane 切换（`settings_page.dart` 的 controller
   传参换成切片接缝）；
5. 关批删除（§7）。

## 4. 生命周期与 dispose 归属

见 [§3.5](phase3_slice_expansion.md) 表格：两个切片 store 由 app 组合层 provider
创建（app session 寿命，**非 autoDispose**——设置不随页面关闭消失）；store 文件
实现仍由 `MainApp` 注入；`SystemFontCatalogService` 由组合层持有。

## 5. §15 门禁答卷

见 [§3.6](phase3_slice_expansion.md)，十条已逐条作答。本批无追加豁免；若实现中
出现任何一条答不上来，停批回到本文档补答。

## 6. 验收测试

见 [§3.7](phase3_slice_expansion.md) 七条。补充两条批内执行口径：

- **关批后单路径**：`SettingsPage` / 主题 / 通知投影只消费 slice store；
  provider 未注入时 fail closed，不存在 controller fallback；
- **守卫基线变化**：关批时 `feature_layering_guard_test` 的
  `knownApplicationFlutterImports` **−2**（两个 settings controller 删除）、
  `knownDomainImpurities` **−3**（settings domain 纯化），同步删清单条目——
  守卫的"清单不允许有过期条目"断言会强制这件事。

## 7. 删除清单（已执行）

- `appearance_settings_controller.dart`、`general_settings_controller.dart`；
- `settings_page.dart` / `ide_home.dart` / `app.dart` 的 controller 传参与
  `listenable` 消费点；
- domain 的 `ThemeMode` 引用；
- `settingsSliceEnabled` flag 本身。

## 8. 回滚方式

- 2026-08-24 关批后不再保留运行时 flag 或旧 controller 回退；
- 回滚只允许 revert 关批提交，从 git 历史恢复整个旧路径；
- 持久化 schema 未变，不建立双写或兼容 facade。

## 9. 四步节奏锚点

1. **挂 flag**：✅ 步骤 1–4 已在 flag 默认 false 下落地（2026-08-23）；
2. **对照验证**：✅ §6 双路径对照、`flutter analyze` 与 `test_affected` 已通过
   （2026-08-23）；
3. **翻 flag**：✅ 2026-08-23 生产启用；2026-08-24 用户明确接受不等待原定日期，
   缩短本批独立观察余量；
4. **关批**：✅ 2026-08-24 已执行 §7：两个 controller、ingress、flag 与 false-path
   删除，settings 固定为 slice 单一路径，对应 application Flutter 燃尽项清零。

## 10. 关批证据（2026-08-24）

- `AppearanceSettingsController|GeneralSettingsController|SettingsSliceIngress|settingsSliceEnabled`
  在 `lib/` 与 `test/` 的 Dart 源码中零命中；
- controller 测试的载入归一化、字体解析、persist-first、串行写入和
  失败回执已迁入 slice reducer / store / runner 测试；
- `ide_settings_widget_test.dart`、settings slice 定向测试和 Desktop Attention
  组合测试通过；全量门禁由 Phase 3 收尾统一执行。

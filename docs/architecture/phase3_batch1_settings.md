# Phase 3 第 1 批开工文档：settings 切片

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

> **步骤 4 实施要点（2026-08-23 已定设计，待实施）**：
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

- **对照测试双路径**：第 2–4 步的每步都要在 `settingsSliceEnabled` 开/关下
  各跑一遍 settings 相关 Widget 测试，两条路径渲染等价；
- **守卫基线变化**：关批时 `feature_layering_guard_test` 的
  `knownApplicationFlutterImports` **−2**（两个 settings controller 删除）、
  `knownDomainImpurities` **−3**（settings domain 纯化），同步删清单条目——
  守卫的"清单不允许有过期条目"断言会强制这件事。

## 7. 删除清单（关批时）

- `appearance_settings_controller.dart`、`general_settings_controller.dart`；
- `settings_page.dart` / `ide_home.dart` / `app.dart` 的 controller 传参与
  `listenable` 消费点；
- domain 的 `ThemeMode` 引用；
- `settingsSliceEnabled` flag 本身。

## 8. 回滚方式

- 批内：`settingsSliceEnabled` 全局 bool，默认 false，生产行为不变；
- 翻 flag 后发现问题：一行拨回 false，回到旧 controller 直连路径；
- 关批后：revert 关批提交（旧 controller 在 git 历史里完整可恢复）。

## 9. 四步节奏锚点

1. **挂 flag**：步骤 1–4 全部在 flag 默认 false 下落地；
2. **对照验证**：§6 双路径对照全绿 + `flutter analyze` + `test_affected`；
3. **翻 flag**：`main.dart` 传 `settingsSliceEnabled: true`，观察窗口 ≥ 3 天
   （本批风险为低，取下限）；
4. **关批**：执行 §7 删除，更新守卫基线与燃尽表，Phase 3 开工文档 §2.11
   的 settings 行标记清零。

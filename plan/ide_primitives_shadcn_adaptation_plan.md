# Zeta IDE 原语对 `shadcn_flutter` 的底层适配改造方案

> 版本：v1.0  
> 日期：2026-07-28  
> 状态：P0/P1 已完成；P2 已实施并通过门禁；P3 未启动
> 适用基线：`flutter` 分支；UI 库已切换为 `shadcn_flutter: 0.0.52`  
> 相关历史文档：  
> - `plan/shadcn_flutter_replacement_plan.md`（库切换落地计划，已完成路径）  
> - `plan/shadcn_migration_plan.md` / `plan/ui_modernization_blueprint.md`（历史背景）  
> - `plan/统一设计系统与工作台重构实施文档.md`（Graphite / Workbench 基线）  
> - `plan/输入框模型配置功能详细设计文档.md`（模型配置行为边界）

---

## 1. 文档定位

本文回答在 **库切换完成后**，哪些 **自定义 `Ide*` / Composer 控件** 的实现层仍可（或不可）进一步委托给 `shadcn_flutter`，并给出分阶段、可测试、可回滚的改造路径。

本文 **不是**：

- 再次从 `shadcn_ui` 迁到 `shadcn_flutter` 的迁移计划（该工作已完成）。
- 重做 Graphite token 或 Workbench 三栏架构。
- 用 Navigation Menu / Menubar 重写 Composer 工具栏的方案（已明确否决）。

本文 **是**：

1. 现状盘点：已适配 / 可适配 / 不可适配。
2. 改造原则与禁止项。
3. 分阶段任务、验收标准与测试要点。
4. 风险与回滚策略。

---

## 2. 执行摘要

### 2.1 核心结论

```text
可替换 = 「通用交互原语」在 shadcn 有等价实现
不可替换 = 「IDE 布局 / 密度 / token / 性能 / 领域面板」
正确姿势 = 保留 Ide* 门面，底层委托 shadcn，禁止 feature 散落 sf.*
```

| 类别 | 结论 |
|---|---|
| 已完成的适配层 | Dialog / Toast / Popover / Chip / Tabs / Tooltip / Menubar / Loading Progress 等应 **维持门面**，禁止回退为 feature 直连 |
| 值得继续做的 | BusySpinner 去 Material；Composer 简单选择器内容层 → SelectPopup；可选 ContextMenu → DropdownMenu |
| 明确不做 | Navigation Menu / Menubar 替换 Composer 选择器；Select 整换模型配置面板；Collapsible 换掉带动画的折叠卡；拆掉 Graphite token |

### 2.2 目标改造路径（建议顺序）

```text
P0  清理与对齐
    ├── IdeBusySpinner 改用 shadcn Spinner / CircularProgressIndicator
    └── 固化「已适配清单」：feature 禁止绕过 Ide* 门面

P1  Composer 简单选择器收口
    ├── 抽 Composer 弹层 helper（定位 / 时长 / handle 生命周期）
    ├── 模式 / 权限 / session 枚举 内容层 → SelectPopup
    └── trigger 继续 _ComposerSelectorTrigger（IDE 密度）

P2  菜单一致性（可选）
    └── IdeContextMenu 底层 → DropdownMenu 族（保留 Graphite 表面）

P3  低优先级视觉对齐（按需）
    ├── IdeStatusCard 可选基于 Alert 实现
    ├── StateLabel 可选基于 Badge
    └── Settings 等表单控件逐步 Select / Switch 包装

明确不做
    ├── 模型配置富面板 → 保持 Popover + 自定义内容
    ├── Workbench / 虚拟列表 / WindowFrame 壳
    └── PaneInteractiveSurface / IdeCollapsibleCard 整换
```

### 2.3 成功标准（总体）

1. **对外 API 稳定**：feature 继续消费 `Ide*` / Composer 既有参数，不扩散 `sf.*`。
2. **视觉不回归**：Graphite token、28px 工具栏密度、底部向上弹层行为保持。
3. **行为不回归**：选中、Esc 关闭、回焦 trigger、reduce-motion、loading/error 状态完整。
4. **测试可维护**：既有 widget 测试 Key 与 `IdeMotion` pump 路径可继续使用或等价更新。
5. **`dart format` + `flutter analyze` + 相关 `flutter test` 通过**。

---

## 3. 改造原则

### 3.1 门面优先（Facade）

| 层 | 职责 |
|---|---|
| Feature / 业务 | 只调 `Ide*`、`showIde*`、Composer 公开控件 |
| `lib/src/ui/core` | IDE 语义、token、密度、可访问性、测试 Key |
| `shadcn_flutter` | Overlay、选择列表、菜单键盘行为、基础交互机 |

禁止在 `features/**` 中新增大量裸 `sf.Select` / `sf.showPopover` 拼装（session 配置等既有用法在 P1 收口时一并迁入门面）。

### 3.2 视觉真源

- Graphite：`IdeThemeScope` / `IdeColors` / `IdeTextStyles` / `IdeSpacing` / `IdeMotion` / `IdeEffects`。
- `sf.ThemeData` 仅作第三方 Widget 投影，不得在 feature 中当业务色板使用。
- 导入约定：`import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;`。

### 3.3 交互真源（Composer）

| 需求 | 必须保留 |
|---|---|
| 触发方式 | **点击 toggle**，禁止 hover 打开配置 |
| 弹层方向 | Composer 在底部时 **优先向上** |
| Trigger | 高度 28、与 `_ComposerSelectorTrigger` 一致 |
| 动画 | `IdeMotion` + `MediaQuery.disableAnimationsOf` |
| 关闭 | 选中 / 点 trigger / 点外部 / Esc；关闭后回焦 |

### 3.4 禁止项（否决清单）

| 禁止动作 | 原因 |
|---|---|
| 用 `NavigationMenu` 重写 Composer 工具栏 | 站点导航 mega menu；hover 打开；共享 popover；默认向下弹 |
| 用 `Menubar` 承载模型/权限/模式 | 菜单栏语义，非配置芯片 |
| 用完整默认 `Select` 触发器替换 28px 芯片 | form field 密度与 Graphite 不一致 |
| 用 `Select` / `Command` / `ItemPicker` 整换模型配置面板 | 异步保存、行内展开、冲突/重试，不是单值列表 |
| 用 shadcn `Collapsible` 整换 `IdeCollapsibleCard` | 对方内容多为 Offstage，无高度展开动画 |
| 用 `Button` 整换 `PaneInteractiveSurface` | hover 退出瞬时清空等列表性能策略不匹配 |
| 删除 `Ide*` 门面让 feature 直连 `sf.*` | 违反工程约定，增加换库成本 |

---

## 4. 现状盘点

### 4.1 已委托 shadcn（维持，不回退）

| IDE API | 底层 shadcn | 路径 |
|---|---|---|
| `showIdeDialog` / `IdeDialog` | `showDialog` + `AlertDialog` | `ide_dialog.dart` |
| `showIdeToast` | `showToast` | `ide_toast.dart` |
| `showIdePopover` / `IdePopoverHandle` | `showPopover` | `ide_popover.dart` |
| `IdeChip` | `Chip` / `ChipButton` | `ide_chip.dart` |
| `IdeTabs` / `IdeTab` | `Tabs` + theme 定制 | `ide_tabs.dart` |
| `IdeTooltip` | Overlay tooltip + `TooltipContainer` | `pane_widgets.dart` |
| `IdeLoadingIndicator` | `Progress` | `pane_widgets.dart` |
| 窗口菜单 `_WindowMenuBar` | `Menubar` + `MenuButton` | `window_frame.dart` |

### 4.2 可适配（本计划范围）

| 组件 / 区域 | 候选底层 | 优先级 |
|---|---|---|
| `IdeBusySpinner` | shadcn `Spinner` 或 circular progress | P0 |
| Composer 模式 / 权限 / session 枚举内容 | `SelectPopup` + `SelectItemButton` | P1 |
| Composer 弹层定位重复代码 | 基于 `showIdePopover` 的 helper | P1 |
| `IdeContextMenu` | `DropdownMenu` / `MenuButton` | P2（可选） |
| 更多操作菜单 | 同上或继续 IdeContextMenu | P2 |
| `IdeStatusCard` | `Alert`（实现替换） | P3 |
| `StateLabel` | `Badge` | P3 |
| Settings 表单控件 | `Select` / `Switch` 包装 | P3 |

### 4.3 不可适配 / 保持自研

| 组件 / 区域 | 原因 |
|---|---|
| Graphite token 全家桶 | 设计系统真源 |
| `IdeWorkbenchScaffold` / 页面骨架 | 三栏 + 断点 + overlay |
| `IdeRetainedPageView` | 页面切换保活 Agent 状态 |
| 虚拟列表 / 滚动协调 / 虚拟滚动条 | 时间线性能基础设施 |
| `WindowFrame` 壳与窗口按钮 | 原生窗口集成 |
| `PaneInteractiveSurface` | IDE 列表 hover/press 策略 |
| `PanelCard` / `Pane` / `IdeSurface` | 表面语义分层 |
| `IdeCollapsibleCard` | 高度动画 + 摘要区 |
| `IdeActivityRail` | 桌面 activity bar |
| `IdeResizeHandle` | workbench 宽度状态在业务层 |
| `_AgentModelConfig` 富面板 | 领域配置工作流 |
| Composer 扫光 / Footer 位移 / 提问卡入场 | 产品动效 |

---

## 5. 阶段设计

### 阶段 P0：清理与对齐

#### 目标

1. 去掉 `IdeBusySpinner` 对 Material `CircularProgressIndicator` 的依赖，与 `IdeLoadingIndicator` 技术栈对齐。
2. 在文档 / 代码注释层明确「已适配清单」，避免后续 feature 重复造门面。

#### 代码落点

| 文件 | 改动 |
|---|---|
| `lib/src/ui/core/pane_widgets.dart` | `IdeBusySpinner` 改用 `sf` 圆形进度 / Spinner |
| 相关 widget 测试 | 断言类型或 Key 更新（若有） |

#### 验收

- [ ] `IdeBusySpinner` 在 dark/light 下尺寸、描边与现网视觉一致（允许 ±1px）。
- [ ] 标题栏 / thread 列表 running 态无障碍 label 不变。
- [ ] `flutter analyze` 无新增告警；相关 test 通过。

#### 预估工作量

0.5～1 人日。

---

### 阶段 P1：Composer 简单选择器收口（核心）

#### 目标

将 **模式 / 权限 / session 枚举** 的「列表内容 + 选中关闭」委托给 `SelectPopup`，同时：

- **不改变** `_ComposerSelectorTrigger` 外观与点击语义。
- **不改变** 底部优先向上的定位策略。
- **不纳入** 模型配置富面板（仍走专用 popover）。

#### 5.1 抽公共 helper（建议）

在 `lib/src/ui/core/` 或 `agent` presentation 内聚位置新增（命名示例）：

```dart
/// Composer 选择器弹层公共参数与生命周期。
/// - 视口上下空间 → openAbove
/// - IdeMotion / reduce-motion 时长
/// - IdePopoverHandle 赋值与关闭回焦
IdePopoverHandle<void> showComposerSelectorPopover({...});
```

合并当前重复逻辑来源（至少）：

- `agent_mode_selector.dart`
- `agent_model_config.dart`（仅定位/时长部分可复用；内容不换 Select）
- `agent_pane_composer.dart` 中 `_PermissionPolicyButton` / `_SelectorSelect` / more actions

**模型配置** 可只复用 helper 的定位与时长，内容仍为 `_ModelConfigPopover`。

#### 5.2 内容层：SelectPopup

| 选择器 | 值类型 | Select 用法要点 |
|---|---|---|
| 对话模式 | `AgentConversationModeId` | 禁用不可选项；loading/error 仍在 trigger 侧表达 |
| 权限策略 | `AgentPermissionPreset` id 或 preset | item 可含 title + muted 描述 |
| Session 枚举 | `Object` / option value id | 对齐现有 `_SelectorSelect`，去掉 feature 内临时 `SelectData` 拼装 |

推荐结构：

```text
_ComposerSelectorTrigger (保持)
    └── showComposerSelectorPopover / showIdePopover
            └── ConstrainedBox(maxWidth/maxHeight)
                    └── SelectPopup.noVirtualization 或 SelectPopup
                            └── SelectItemList / SelectItemButton
```

触发器 **不要** 直接使用默认 `sf.Select` 整控件（避免 form 密度）。

若需要打开后键盘导航 / autoClose，通过 `sf.SelectData`（或 Select 官方推荐的 inherit 方式）注入，与现 session 配置路径一致，但封装进 helper。

#### 5.3 明确不迁入本阶段

| 控件 | 处理 |
|---|---|
| `_AgentModelConfig` | 仅可复用弹层 helper；面板内容不动 |
| Session 布尔项 | 保持 chip toggle；不改成 Switch（工具栏密度） |
| More actions | P2 再议 |

#### 验收

- [ ] 模式 / 权限 / session 枚举：打开、选中、关闭、Esc、回焦均通过既有或新增 widget 测试。
- [ ] Composer 靠近窗口底边时弹层 **向上** 展开，不裁切关键选项。
- [ ] reduce-motion 下进出时长缩短或为 0，无异常卡住。
- [ ] Provider 切换 / contextId 变化时旧弹层关闭（模式选择器既有行为）。
- [ ] 工具栏仍为单行 28px 高度；空间不足时裁切策略不变。
- [ ] 模型配置：选中展开、reasoning/Fast、saveError/retry、next-turn banner 行为无回归。

#### 测试落点（参考）

- `test/src/features/agent/presentation/agent_pane_pr3_test.dart`
- `test/src/features/agent/presentation/agent_conversation_widget_test.dart`
- 模式 / 权限相关专用测试（若已有则更新 finder；若无则补最小交互用例）

#### 预估工作量

3～5 人日（含 helper 抽取与测试更新）。

---

### 阶段 P2：菜单一致性（可选）

#### 目标

`IdeContextMenu` 在 **保持对外 API**（`IdeContextMenuAction`、divider、destructive、semanticLabel）的前提下，底层改为 shadcn 菜单原语，统一键盘与焦点行为。

#### 方案

```text
IdeContextMenu
  └── IdeSurface.popover / PanelCard（Graphite 表面）
        └── sf.DropdownMenu 或 MenuPopup + MenuButton/MenuDivider
```

更多操作（`_ComposerMoreActions`）可改为：

- 继续 `showIdePopover` + 新 `IdeContextMenu` 实现；或
- `sf.showDropdown`（需验证底部向上定位与现网一致后再选）。

#### 验收

- [ ] Plan / Mention file / Attach image 行为与 Key 不回归。
- [ ] 禁用项、分割线、关闭后回焦正确。
- [ ] 视觉仍符合 Graphite，无默认 shadcn 厚卡片感。

#### 预估工作量

1.5～3 人日。若 P1 后菜单无痛点，可 **延期或取消**。

---

### 阶段 P3：低优先级视觉对齐（按需）

| 项 | 做法 | 触发条件 |
|---|---|---|
| `IdeStatusCard` | 内部用 `sf.Alert` 布局，外层 token 着色 | 需要与 shadcn Alert 动效/无障碍对齐时 |
| `StateLabel` | 内部用 `sf.Badge` | 全局状态胶囊样式统一时 |
| Settings 开关/下拉 | thin wrapper 到 `Switch`/`Select` | 设置页表单改造专项时 |
| `IdeChoiceCard` | 保持布局；交互可继续 `PaneInteractiveSurface` | 无强需求不迁 |

P3 **不设硬性工期**；不得阻塞 P0/P1。

---

## 6. 组件级决策矩阵（速查）

| 自定义组件 | 决策 | 备注 |
|---|---|---|
| IdeDialog / Toast / Popover / Chip / Tabs / Tooltip | **维持** | 已适配 |
| IdeLoadingIndicator | **维持** | 已 Progress |
| IdeBusySpinner | **P0 替换底层** | 去 Material |
| IdeContextMenu | **P2 可选** | DropdownMenu |
| Composer 模式/权限/session 列表 | **P1 内容层 Select** | trigger 自研 |
| 模型配置面板 | **保持自研** | 仅 Popover 壳 |
| IdeCollapsibleCard | **保持** | 不用 Collapsible 整换 |
| PaneInteractiveSurface | **保持** | 不用 Button 整换 |
| PanelCard / Pane / IdeSurface | **保持** | 表面语义 |
| IdeListRow / DataRow / SettingsRow | **保持** | 密度行 |
| IdeActivityRail | **保持** | |
| IdeWorkbench* / 虚拟滚动 | **保持** | |
| WindowFrame 壳 | **保持** | 菜单已 Menubar |
| NavigationMenu 用于 Composer | **禁止** | |

---

## 7. 实施约束与工程纪律

### 7.1 与 Agents.md 对齐

- 改 Dart 后：`dart format .`
- 结束前：`flutter analyze`
- 有行为变更：跑相关 `flutter test`
- 公共 API 补充中文 `///`；避免空注释
- 不引入新状态管理库；不破坏 feature-sliced 依赖方向

### 7.2 依赖

- **不新增** runtime 依赖；仅使用现有 `shadcn_flutter: 0.0.52`（及其 re-export 的 `animation_kit` 若确有需要）。
- 禁止为了 Select 再引入第三套下拉库。

### 7.3 API 兼容

优先 **行为兼容、签名兼容**。若必须改 public 构造参数：

1. 同 PR 更新全部调用方与测试。
2. 在 PR 描述中列出 breaking 点（尽量避免）。

### 7.4 测试策略

| 层级 | 内容 |
|---|---|
| 单元 / Widget | trigger 文案、选中回调、Esc、context 切换关层 |
| 回归 | 模型配置展开与保存错误路径 |
| 手动 | 窄窗口、底部贴边、light/dark、reduce-motion |

---

## 8. 风险与回滚

| 风险 | 影响 | 缓解 |
|---|---|---|
| SelectPopup 默认样式偏 form | 工具栏视觉变「厚」 | 只用内容层；trigger 自研；Panel/表面继续 Graphite |
| Select 默认向下弹 | 底部被裁切 | 继续 `showIdePopover` 自算 openAbove，不交给默认 Select 整控件定位 |
| autoClose 与「点同一项展开」冲突 | 模型配置误关 | 模型配置 **不** 走 Select |
| DropdownMenu 定位与现 popover 不一致 | 更多操作菜单位置回归 | P2 先做对照原型；不通过则取消 |
| 测试 finder 绑 Material/旧类型 | CI 红 | 优先 `ValueKey`；少用 `find.byType(AnimatedContainer)` 绑实现细节 |
| 范围蔓延到 Workbench | 工期失控 | 严格按 P0→P1→P2 闸门，P3 不默认开工 |

**回滚：**

- 各阶段独立 PR / commit。
- P1 helper 与 Select 内容可 feature-flag 或快速 revert 单 commit。
- 门面 API 不变时，回滚只影响 `ui/core` 与 composer part 文件。

---

## 9. 建议 PR 拆分

| PR | 内容 | 依赖 |
|---|---|---|
| PR-1 | P0 BusySpinner | 无 |
| PR-2 | `showComposerSelectorPopover` helper + 一处调用方试点（建议权限或 session） | PR-1 可并行 |
| PR-3 | 模式 + 权限 + session 全面切 Select 内容层 | PR-2 |
| PR-4 | 测试补强与硬编码 Duration 收口到 IdeMotion | PR-3 |
| PR-5（可选） | IdeContextMenu → DropdownMenu | PR-3 稳定后 |

每个 PR 合并前：`dart format` + `flutter analyze` + 相关 test。

---

## 10. 任务清单（Checklist）

### P0

- [ ] `IdeBusySpinner` 底层改为 shadcn
- [ ] 更新/确认 spinner 相关测试
- [ ] analyze + format

### P1

- [ ] 设计并实现 `showComposerSelectorPopover`（或等价 helper）
- [ ] 权限策略 popover 内容 → SelectPopup
- [ ] 对话模式 popover 内容 → SelectPopup
- [ ] Session 枚举收口到同一 helper
- [ ] 模型配置仅复用定位 helper（可选同 PR 或跟随）
- [ ] 回归模型配置全路径
- [ ] 更新 agent presentation 测试

### P2（可选）

- [x] `IdeContextMenu` 底层评估原型
- [x] 通过后替换实现并回归 more actions

### P3（按需）

- [ ] StatusCard / Badge / Settings 表单专项单独立项

### 文档

- [ ] 本方案状态栏更新为「实施中 / 已完成」
- [ ] 若公开 API 或约定变化，同步 `docs/developer_guide.md` / `docs/engineering_standards.md` 中 UI 组件使用说明（仅在有实质变化时）

---

## 11. 附录

### A. 与历史 shadcn 文档的关系

| 文档 | 关系 |
|---|---|
| `shadcn_flutter_replacement_plan.md` | 库级一次性替换；**前置已完成** |
| `shadcn_migration_plan.md` | Material → shadcn_ui 历史 |
| 本文 | **替换完成后的** Ide 原语 / Composer 底层适配 |

### B. 参考代码锚点

| 主题 | 路径 |
|---|---|
| Composer 组装选择器 | `lib/src/features/agent/presentation/widgets/agent_pane_composer.dart` |
| 模型配置 | `lib/src/features/agent/presentation/widgets/agent_model_config.dart` |
| 模式选择 | `lib/src/features/agent/presentation/widgets/agent_mode_selector.dart` |
| 弹层门面 | `lib/src/ui/core/ide_popover.dart` |
| 动效 token | `lib/src/ui/core/ide_motion.dart` |
| 已适配 Chip/Tabs/Dialog/Toast | `ide_chip.dart` / `ide_tabs.dart` / `ide_dialog.dart` / `ide_toast.dart` |

### C. shadcn 组件选用速查

| 场景 | 选用 | 不用 |
|---|---|---|
| 简单单选列表 | `SelectPopup` + `SelectItemButton` | NavigationMenu |
| 任意富内容浮层 | `showIdePopover`（已是 showPopover） | — |
| 命令菜单 | DropdownMenu / IdeContextMenu | Select |
| 通知 | showIdeToast | 自研 Overlay |
| 对话框 | showIdeDialog | Material showDialog |
| 模型配置 | 自定义面板 + Popover | Select / Command / ItemPicker |

---

## 12. 变更记录

| 版本 | 日期 | 说明 |
|---|---|---|
| v1.0 | 2026-07-28 | 初版：基于现状盘点与 Composer/原语适配建议整理可执行改造方案 |

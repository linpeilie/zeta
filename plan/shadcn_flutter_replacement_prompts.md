# Zeta `shadcn_ui` -> `shadcn_flutter` 分阶段执行 Prompt

## 使用说明

- 这些 prompt 设计给编码代理使用，默认目标是直接在仓库里落地代码，不是只做分析。
- 每次开新会话时，先给对应阶段 prompt，不要把所有阶段一次性塞进同一个会话。
- 每个 prompt 都默认代理需要先读：
  - `AGENTS.md`
  - `.agents/skills/shadcn-flutter`
  - `plan/shadcn_flutter_replacement_plan.md`
- 每个 prompt 都默认：
  - 使用 CodeGraph 先理解代码
  - 遵守“无兼容层、一次性切换、Windows 验收”的策略
  - 修改 Dart 文件后运行 `dart format .`
  - 在阶段结束前至少跑 `flutter analyze`

---

## Prompt 0：阶段 0 预切换准备与原型验证

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是为“将 shadcn_ui 替换为 shadcn_flutter”做迁移前验证，而不是正式全量改造。

开始前先完整阅读以下文件：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md

严格遵守这些约束：
- 本次迁移不允许过渡期兼容层
- 不要保留旧 Shad* API 的 adapter
- Graphite token 必须继续存在，并且后续要成为项目自己的主题真源
- 目标平台本轮只验收 Windows
- 优先使用 CodeGraph 理解代码

本阶段只做 4 类工作：
1. 盘点当前 shadcn_ui 的实际使用面，并确认高风险文件
2. 为以下 4 个问题做最小原型验证，不做全量迁移：
   - `ShadApp` -> `shadcn_flutter` 的 `ShadcnApp`
   - `showShadDialog` / `ShadDialog` -> `showDialog` + `sf.AlertDialog`
   - `ShadPopoverController` / `ShadPopover` -> `sf.showPopover` 或 `MenuPopup`
   - `ShadTextarea` / `ShadSelect` / `ShadOption` -> `sf.TextArea` / `sf.Select` / `sf.SelectPopup`
3. 给出每个原型是否可行、风险点、建议实现方式
4. 如有必要，把原型结论写回 plan 文档或单独补充到 plan/ 下的新文档

执行要求：
- 可以建立最小验证代码，但不要开始正式批量替换业务文件
- 如果需要新增 scratch 文件，放到 plan/ 或临时文件里，避免污染正式结构
- 如你发现 `shadcn_flutter` API 与计划假设不一致，要明确指出并修正计划

最终输出必须包含：
- 当前高风险迁移点列表
- 4 个原型的验证结论
- 建议的正式迁移顺序
- 是否可以进入阶段 1
```

---

## Prompt 1：阶段 1 依赖切换与根入口重建

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 1：依赖切换与根入口重建。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

本阶段目标：
- 从依赖层移除 `shadcn_ui`
- 引入并固定 `shadcn_flutter: 0.0.52`
- 把应用根入口从 `ShadApp` 切到 `sf.ShadcnApp`
- 让测试 harness 重新可启动

严格约束：
- 不要建立兼容层去模拟旧 `Shad*`
- `import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;` 必须作为统一规范
- 还不要大规模改 feature 页面
- 如果某些旧 token 仍依赖旧 theme，可以临时让编译恢复，但不要把这种状态当作最终结构

本阶段要修改的重点文件：
- pubspec.yaml
- lib/src/app/app.dart
- lib/src/ui/core/app_theme.dart
- test/src/app/ide_settings_widget_test.dart
- test/src/features/agent/presentation/agent_pane_pr3_test.dart

执行要求：
1. 先完成依赖替换
2. 再重建根入口与 theme builder
3. 再修测试 harness 的 app 包装
4. 跑 `dart format .`
5. 跑 `flutter analyze`

如果 analyze 失败：
- 优先修复阶段 1 自己引入的问题
- 不要顺手扩散到阶段 3/4 的大改

最终输出必须包含：
- 实际修改了哪些入口文件
- 当前还剩哪些编译或主题结构问题未处理
- 是否可以进入阶段 2
```

---

## Prompt 2：阶段 2 设计 token 与主题解耦

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 2：让 Graphite token 脱离旧库 theme，成为项目自己的主题真源。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

核心目标：
- `IdeColors` 不再从 `ShadTheme` 回读
- `IdeTextStyles` 不再依赖 `ShadThemeData` / `ShadTextTheme`
- 建立项目自有的 `IdeThemeScope` / `IdeThemeData`（命名可调整，但职责必须明确）
- Graphite token 继续作为唯一语义真源
- `shadcn_flutter` 的 `sf.ThemeData` 只是 token 投影层，不是反向数据源

重点处理文件：
- lib/src/ui/core/app_theme.dart
- lib/src/ui/core/ide_colors.dart
- lib/src/ui/core/ide_text_styles.dart
- 如有必要新增 lib/src/ui/core/ide_theme.dart

严格约束：
- 不要保留 `shadColorSchemeFromIdeColors` 这一类“借第三方 theme 透传自定义 token”的旧模式
- 不要再让 `IdeColors.of(context)` 回退到旧 `ShadTheme`
- 保留当前 UI 字体与代码字体分离策略
- Graphite 的固定圆角、间距、阴影语义必须保留，不允许直接被第三方默认值替代

执行步骤建议：
1. 先定义项目自有 theme scope 数据结构
2. 再让 `IdeColors.of(context)`、`IdeTextStyles.of(context)` 改走新 scope
3. 再把 `app_theme.dart` 里的第三方 theme builder 改为“由项目 token 投影到 sf.ThemeData”
4. 跑 `dart format .`
5. 跑 `flutter analyze`

最终输出必须包含：
- 新的主题真源结构说明
- 哪些旧的 Shad 主题映射函数已删除
- 当前 `ui/core` 还有哪些组件依赖旧库 theme
- 是否可以进入阶段 3
```

---

## Prompt 3：阶段 3 重写 `ui/core` 基础组件层

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 3：优先重写 ui/core 基础组件层，为后续 feature 页面迁移提供稳定底座。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

本阶段必须完成的事情：
- `lib/src/ui/core/` 中直接耦合 `shadcn_ui` 的文件全部切到新实现
- 优先改 wrapper / primitives，不先改业务层
- 删除 `ui/core` 对 `package:shadcn_ui/shadcn_ui.dart` 的直接依赖

重点文件：
- lib/src/ui/core/pane_widgets.dart
- lib/src/ui/core/ide_chip.dart
- lib/src/ui/core/ide_context_menu.dart
- lib/src/ui/core/window_frame.dart
- 以及任何仍直接依赖旧库的 ui/core 文件

设计要求：
- `PaneInteractiveSurface` 继续保留项目自绘交互语义
- `IdeTooltip` 改为基于 `sf.Tooltip`
- `IdeLoadingIndicator` 改为基于 `sf.Progress`
- `WindowFrame` 里的菜单/弹层去掉 `ShadPopoverController`
- 如果 `sf.Chip` 不能准确匹配当前 Graphite 紧凑视觉，就保留 `IdeChip` 自绘，而不是为了“全用库组件”牺牲设计一致性

执行要求：
1. 先梳理 ui/core 当前依赖结构
2. 按从通用到底层的顺序改
3. 每改完一个核心文件，检查是否影响其他 ui/core primitives
4. 跑 `dart format .`
5. 跑 `flutter analyze`

成功标准：
- `lib/src/ui/core/` 内不再出现 `package:shadcn_ui/shadcn_ui.dart`
- ui/core 提供的 primitives 能继续给 feature 页面复用

最终输出必须包含：
- 已迁移的 ui/core 文件列表
- 是否保留了某些项目自绘组件，以及原因
- 还剩哪些 feature 页面依赖旧库
- 是否可以进入阶段 4
```

---

## Prompt 4A：阶段 4A 项目列表与文件树迁移

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 4A：迁移项目列表与文件树相关页面。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

本阶段只处理：
- lib/src/ui/features/ide/views/project_list_pane.dart
- lib/src/features/workspace/presentation/file_tree_pane.dart

目标：
- 移除这两个文件对旧 `shadcn_ui` API 的依赖
- 所有按钮、输入框、弹窗、更多菜单都切到 `shadcn_flutter` 或 ui/core primitives
- 保留现有交互行为与 key 语义

关键改造点：
- `showShadDialog` -> `showDialog` + `sf.AlertDialog`
- `ShadInput` -> `sf.TextField`
- `ShadButton*` -> `sf.PrimaryButton` / `sf.OutlineButton` / `sf.GhostButton` / `sf.DestructiveButton`
- `ShadIconButton.ghost` -> `sf.IconButton.ghost`
- 文件树不改数据结构，只改渲染层

严格约束：
- 不要顺手重写文件树状态管理
- 不要把 thread 菜单逻辑散落回业务层，优先复用 `IdeContextMenu`
- 保持已有 `ValueKey` 与 hover/selected 行为

执行要求：
1. 先迁移 project_list_pane.dart
2. 再迁移 file_tree_pane.dart
3. 跑 `dart format .`
4. 跑 `flutter analyze`
5. 如有对应 widget test，更新测试

最终输出必须包含：
- project list 和 file tree 各自的迁移点
- 是否存在交互行为变化
- 是否可以进入阶段 4B
```

---

## Prompt 4B：阶段 4B 设置页迁移

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 4B：迁移设置页。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

本阶段只处理：
- lib/src/features/settings/presentation/settings_page.dart
- 如需要，一并修 test/src/app/ide_settings_widget_test.dart

目标：
- 移除 settings_page 对旧 `Shad*` API 的依赖
- 保持字体搜索、字体选择弹窗、提示反馈行为不变

关键改造点：
- `showShadDialog` -> `showDialog` + `sf.AlertDialog`
- `ShadInput` -> `sf.TextField`
- `ShadButton.ghost` / `ShadIconButton.ghost` -> 对应 `sf` 按钮
- `ShadToast` / `ShadSonner` 相关调用 -> `sf.showToast` 或项目统一 helper

执行要求：
1. 先读 settings_page 的实际交互链路
2. 再改弹窗、输入、反馈
3. 检查 light/dark 主题下的文本对比度与 hover/focus 行为
4. 跑 `dart format .`
5. 跑 `flutter analyze`
6. 跑与设置页相关的测试

最终输出必须包含：
- 设置页迁移完成情况
- 是否有 toast/helper 还需统一到后续阶段
- 是否可以进入阶段 4C
```

---

## Prompt 4C：阶段 4C Agent Pane 迁移

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 4C：迁移 Agent Pane 及其 part 文件。这是本次改造中风险最高的阶段。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

本阶段处理文件：
- lib/src/features/agent/presentation/agent_pane.dart
- lib/src/features/agent/presentation/widgets/agent_pane_composer.dart
- lib/src/features/agent/presentation/widgets/agent_pane_messages.dart
- lib/src/features/agent/presentation/widgets/agent_pane_cards.dart
- lib/src/features/agent/presentation/widgets/agent_pane_sections.dart
- lib/src/features/agent/presentation/widgets/agent_pane_header.dart

核心目标：
- 彻底移除 Agent Pane 对旧 `Shad*` API 的依赖
- 保持 timeline、composer、selector、dialog、button、separator 行为不回归
- 继续复用 Graphite token 与 ui/core primitives

重点要求：
- `agent_pane.dart` 顶层 import 统一切为 `shadcn_flutter as sf`
- composer 是重点：
  - `ShadTextarea` -> `sf.TextArea`
  - `ShadSelect` / `ShadOption` -> `sf.Select` / `sf.SelectPopup` / `sf.SelectItemButton`
  - `showShadDialog` -> `showDialog` + `sf.AlertDialog`
  - `ShadIconButton.ghost` -> `sf.IconButton.ghost`
- messages / cards / sections / header 中的 `ShadButton*`、`ShadSeparator` 等全部切掉

严格约束：
- 不要顺手重构业务状态管理
- 不要重写 timeline 数据结构
- 不要为了迁移方便而删除现有 key、语义标签、hover/selected/focus 行为
- 若 `sf.Select` API 不足以直接承载 `_SelectorSelect<T>`，允许重写 `_SelectorSelect<T>`，但不要退回兼容层

执行建议：
1. 先只迁移 import 与类型命名冲突最重的文件结构
2. 再单独攻克 `_SelectorSelect<T>`
3. 再处理 dialog / button / separator
4. 再跑相关测试
5. 跑 `dart format .`
6. 跑 `flutter analyze`
7. 跑 `flutter test`

最终输出必须包含：
- Agent Pane 哪些部分已迁移
- selector / composer 是否行为等价
- 是否还有任何旧 `Shad*` 残留
- 是否可以进入阶段 4D
```

---

## Prompt 4D：阶段 4D IDE Home 与通知迁移

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 4D：迁移 IDE Home 中的旧 toast/通知入口，并完成 feature 层最后收口。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

本阶段重点文件：
- lib/src/ui/features/ide/views/ide_home.dart
- 以及如有必要的通知 helper 文件

目标：
- 删除 `ShadSonner.maybeOf(context)` / `ShadToast` 的旧调用
- 建立基于 `shadcn_flutter` 的统一 toast 触发方式
- 确保通知样式仍遵守 Graphite token

执行要求：
1. 先梳理 IDE Home 里所有通知触发点
2. 抽出统一 helper（如果合理）
3. 改成 `sf.showToast` + 自定义 builder
4. 跑 `dart format .`
5. 跑 `flutter analyze`

最终输出必须包含：
- 新的 toast 使用方式
- 还剩哪些旧库痕迹
- 是否可以进入阶段 5
```

---

## Prompt 5：阶段 5 测试、文档、清理

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 5：清理残留、补齐测试、同步文档。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

本阶段目标：
- 清零旧库残留
- 修复或补充关键 widget test
- 更新设计系统与工程文档

必须完成的检查：
- 运行：
  - `rg -n "package:shadcn_ui/shadcn_ui.dart|showShadDialog|\\bShad[A-Z]" lib test`
- 目标：结果为 0

重点文档：
- AGENTS.md
- .agents/skills/shadcn-flutter
- docs/engineering_standards.md
- docs/developer_guide.md
- docs/design_document.md

执行要求：
1. 先清理代码残留
2. 再修测试
3. 再同步文档
4. 跑 `dart format .`
5. 跑 `flutter analyze`
6. 跑 `flutter test`

如补测试，优先覆盖：
- thread 更多菜单
- settings 字体弹窗
- agent composer selector
- toast 触发

最终输出必须包含：
- 旧 API grep 是否清零
- 更新了哪些测试
- 更新了哪些文档
- 是否可以进入阶段 6
```

---

## Prompt 6：阶段 6 最终验收与交付

```text
你现在在 D:\Development\Workspace\zeta 仓库中工作，目标是执行“shadcn_ui -> shadcn_flutter”迁移的阶段 6：最终验收与交付确认。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md

本阶段不再做大重构，只做：
- 最终命令验证
- Windows 冒烟检查
- 收敛剩余小问题
- 输出交付报告

必须执行：
1. `dart format .`
2. `flutter analyze`
3. `flutter test`
4. 如环境允许：`flutter build windows --debug`
5. 如环境允许：`flutter build windows --release`

必须核对的 Windows 冒烟项：
- 冷启动
- 深浅主题切换
- 文件树
- 项目列表
- thread rename/archive/unarchive/fork/delete
- 设置页字体搜索与弹窗
- Agent composer 输入/发送/取消/mention/attach/selectors
- toast 展示
- Windows 标题栏菜单与窗口按钮

如果发现问题：
- 只修最后一轮阻塞问题
- 不再扩大改动范围

最终输出必须包含：
- analyze/test/build 结果
- Windows 冒烟结果
- 仍存在的已知问题（如果有）
- 是否达到可合并状态
```

---

## Prompt 7：跨会话续接 Prompt

```text
你现在接手的是 D:\Development\Workspace\zeta 仓库中一项正在进行的 `shadcn_ui` -> `shadcn_flutter` 迁移任务。请不要重复从零规划，先恢复上下文，再继续执行当前阶段。

开始前先完整阅读：
1. AGENTS.md
2. .agents/skills/shadcn-flutter
3. plan/shadcn_flutter_replacement_plan.md
4. plan/shadcn_flutter_replacement_prompts.md
5. git diff
6. 当前阶段相关文件

执行要求：
- 先总结当前迁移已经完成到哪个阶段
- 识别未完成项、阻塞项、残留旧 API
- 继续推进，不要重新设计迁移策略
- 保持无兼容层、统一 `sf` alias、Graphite token 为真源

最终输出必须包含：
- 当前所处阶段
- 已完成项
- 待完成项
- 你接下来会继续做什么
```


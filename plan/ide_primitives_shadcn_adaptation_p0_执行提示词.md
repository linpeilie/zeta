# IDE 原语 shadcn 适配：阶段 P0 执行提示词

> 对应方案：`plan/ide_primitives_shadcn_adaptation_plan.md`  
> 阶段目标：清理 `IdeBusySpinner` 对 Material 圆形进度的直接依赖，并与已适配门面清单对齐  
> 使用方式：将下方「可直接使用的提示词」完整交给一个新的编码 Agent 执行  
> 下一阶段：P1（Composer 简单选择器收口）— **P0 完成后由执行 Agent 在回复末尾输出 P1 执行提示词全文**

---

## 可直接使用的提示词

````text
你现在在 Zeta 仓库中工作（工作区根目录以当前环境为准，通常为含 `AGENTS.md` 与 `lib/` 的仓库根）。

本次任务是执行：

  plan/ide_primitives_shadcn_adaptation_plan.md

中的 **阶段 P0：清理与对齐**。

P0 是小而聚焦的改动，不是大重构。完成后你必须在同一回复中输出 **阶段 P1 的完整执行提示词**（格式与本任务提示词同级），以便下一 Agent 直接开工。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
一、开始前必须完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. 阅读并遵守：
   - `AGENTS.md`（或 `Agents.md`）中的 Flutter / 架构 / 测试 / 提交说明约定
   - `plan/ide_primitives_shadcn_adaptation_plan.md` 全文，重点：
     - §2 执行摘要与改造路径
     - §3 改造原则与禁止项
     - §4.1 已委托 shadcn 清单
     - §5 阶段 P0
     - §7 实施约束
   - 本提示词全文

2. 只读检查：
   - `git status --short`
   - `git branch --show-current`
   - `git rev-parse --short HEAD`

3. 核对现状代码（至少打开并理解）：
   - `lib/src/ui/core/pane_widgets.dart`
     - `IdeLoadingIndicator`（已用 `sf.Progress`，作为门面委托范本）
     - `IdeBusySpinner`（当前直接使用 Material `CircularProgressIndicator`）
   - `IdeBusySpinner` 调用方（勿改业务语义，仅确认 API）：
     - `lib/src/features/agent/presentation/widgets/agent_pane_header.dart`
     - `lib/src/features/agent/presentation/widgets/agent_pane_messages.dart`
     - `lib/src/features/agent/presentation/widgets/agent_pane_cards.dart`
     - 以及其他 `grep IdeBusySpinner` 命中处
   - shadcn 包内圆形进度 API（pub-cache 中 `shadcn_flutter-0.0.52`）：
     - `CircularProgressIndicator`（支持 `size` / `strokeWidth` / `color` / `value`；`value == null` 为不定进度）
     - 注意：0.0.52 中 `Spinner` 抽象基类 **没有** 可用的具体 `CircularSpinner` 实现；**P0 应使用 `sf.CircularProgressIndicator`**，不要空等不存在的具体 Spinner 子类

4. 工作区纪律：
   - 不执行 `git reset --hard`、不丢弃无关用户改动
   - 不擅自 `git commit` / `git push`（除非用户另行要求）
   - 不扩大范围到 P1/P2/P3

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
二、阶段 P0 唯一目标
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

完成以下工作，且仅限这些工作：

1. **改造 `IdeBusySpinner` 实现**
   - 对外 API 保持不变：
     - `size`（默认 14）
     - `strokeWidth`（默认 2）
     - `color`（可选；默认 `IdeColors.of(context).accent`）
     - `semanticsLabel`（默认 `'Running'`）
   - 构建时不再 **直接** 使用 Material 的 `CircularProgressIndicator`（即不再依赖 `package:flutter/material.dart` 上的该类型作为实现主体）。
   - 改为通过 `import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;` 使用：
     - `sf.CircularProgressIndicator`
   - 必须正确映射：
     - `size` → 直径
     - `strokeWidth` → 描边宽度
     - `color` → 指示色（未传时仍用 `IdeColors.accent`）
     - 不定进度：`value` 保持 `null`（busy / running）
   - 继续保留外层 `Semantics(label: semanticsLabel)` 与 `SizedBox(width: size, height: size)` 约束，避免布局膨胀。
   - 更新类文档注释：说明与 `IdeLoadingIndicator` 一样走 shadcn 门面；用于标题栏 / thread 列表等窄位 running 态。

2. **固化「已适配清单」的代码侧锚点（轻量）**
   - 在 `pane_widgets.dart` 中，于 `IdeLoadingIndicator` / `IdeBusySpinner` 附近用简短中文 `///` 标明：
     - 线性 loading → `IdeLoadingIndicator`（`sf.Progress`）
     - 圆形 busy → `IdeBusySpinner`（`sf.CircularProgressIndicator`）
     - feature 应使用上述门面，不要直接拼 Material / 裸 `sf` 进度条（与项目「Ide* 门面」约定一致）
   - **不要** 为了「清单」去改 `docs/` 大段文档，除非你发现现有 developer 文档有明显错误且改动 ≤ 几行；默认只改 `pane_widgets.dart` + 必要测试。
   - 可选：在 `plan/ide_primitives_shadcn_adaptation_plan.md` 的阶段 P0 checklist 将对应项勾为完成，并在文首状态改为「P0 已完成 / P1 待实施」（若你改 plan 文档，保持格式一致）。

3. **测试与静态检查**
   - 若有直接断言 Material `CircularProgressIndicator` 且语义上绑定 `IdeBusySpinner` 的测试，改为断言 `IdeBusySpinner` 或 `sf.CircularProgressIndicator`（优先稳定 Key / 门面类型，避免绑实现细节）。
   - 注意：仓库中大量 `find.byType(CircularProgressIndicator)` 用于 **Composer token 环、模型配置 loading 等非 IdeBusySpinner 场景**——**P0 不要改这些业务实现**，也不要为「去 Material」而扫射全仓替换。
   - 运行：
     - `dart format` 触及的文件（或 `dart format lib/src/ui/core/pane_widgets.dart` 及改动测试）
     - `flutter analyze`（至少无新增 error）
     - 与 running / spinner / header / thread 相关的测试；若无专门测试，至少跑：
       - 涉及 `agent_pane_header` / busy / running 的既有 widget 测试子集
       - 或 `flutter test test/src/ui/` 中与 core 相关的部分
     - 若改动极小且无现成测试，新增一个 **最小** widget 测试：泵入带 `IdeThemeScope`（或项目既有 test harness）的 `IdeBusySpinner`，断言 semantics label 与尺寸约束，并确认树中出现 shadcn 圆形进度而非直接 Material 类型（按你最终选型断言 `sf.CircularProgressIndicator`）。

4. **完成汇报 + 输出 P1 执行提示词**
   - 见本文「五、完成后必须输出」。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
三、严格范围
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 允许

- 修改 `lib/src/ui/core/pane_widgets.dart` 中 `IdeBusySpinner`（及紧邻文档注释）
- 为适配断言更新或新增 **最小** 测试
- 可选勾选/更新 `plan/ide_primitives_shadcn_adaptation_plan.md` 中 P0 状态
- 查阅 shadcn_flutter 源码以确认构造参数

### 禁止

- 不进入 P1：不抽 Composer popover helper、不改 SelectPopup、不改模式/权限/session/模型配置弹层
- 不进入 P2/P3：不改 IdeContextMenu、StatusCard、Badge、Settings 表单
- 不批量把全仓 `CircularProgressIndicator` 换成 shadcn（例如 composer token 环、模型列表 loading 等 **不在 P0**）
- 不改 Graphite token、Workbench、虚拟列表、WindowFrame
- 不新增 pub 依赖
- 不删除 `IdeBusySpinner` 门面让调用方直连 `sf.*`
- 不改变 `IdeBusySpinner` 的公开参数默认值语义（size/strokeWidth/color/label）
- 不为「彻底零 Material」而手写一套全新 CustomPainter spinner（除非 `sf.CircularProgressIndicator` 无法满足 size/stroke；优先用 shadcn API。接受 shadcn 内部仍可能委托 Material 绘制——与库自身实现一致；P0 目标是 **Ide 门面不再直接 import/使用 Material CPI**）
- 不提交 git commit（除非用户明确要求）

如果发现必须大改测试 harness 或主题注入才能泵 `IdeBusySpinner`，优先复用现有 widget 测试里的 app/theme 包装；不要新建平行主题系统。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
四、实现提示（推荐做法）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

推荐实现草图（可按项目风格微调，但语义等价）：

```dart
@override
Widget build(BuildContext context) {
  final colors = IdeColors.of(context);
  final indicatorColor = color ?? colors.accent;
  return Semantics(
    label: semanticsLabel,
    child: SizedBox(
      width: size,
      height: size,
      child: sf.CircularProgressIndicator(
        size: size,
        strokeWidth: strokeWidth,
        color: indicatorColor,
        // value: null → indeterminate
      ),
    ),
  );
}
```

注意：

- `pane_widgets.dart` 已 `import ... as sf;`，保持别名一致。
- 若 `sf.CircularProgressIndicator` 在 `value == null` 时仍带明显 track 背景，可用 `backgroundColor: Colors.transparent` 或主题色低 alpha，使窄位 14px 视觉接近现状（以不喧宾夺主为准）；改动后对比 header/thread running 观感。
- 不要引入 `print`；诊断用 `dart:developer` 仅在确有必要时。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
五、完成后必须输出
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### A. 完成汇报（中文）

1. 改了哪些文件、关键 diff 意图  
2. `IdeBusySpinner` 最终采用的 shadcn 类型与参数映射  
3. 测试与 analyze 命令及结果  
4. 是否有意留的后续项（应为空或仅文档）  
5. 若按 `AGENTS.md` 需要，附【Git 提交信息】模块（Conventional Commits，可复制）——**仅建议文案，不要自动 commit**

### B. 门禁结论

明确写一句：

- `P0 通过，可以进入 P1`  
  或  
- `P0 未通过：<阻塞原因>`（若未通过则 **不要** 输出可执行的 P1 提示词，只列阻塞项）

### C. 输出「阶段 P1 执行提示词」全文（P0 通过时强制）

在汇报之后，另起章节，使用与本提示词相同的结构，输出一份 **可直接复制给下一 Agent** 的 P1 提示词。

P1 提示词必须覆盖（内容依据 `plan/ide_primitives_shadcn_adaptation_plan.md` §阶段 P1，写全可执行细节，不要只写「见 plan」）：

1. **背景与必读文档**  
   - 同上 plan；强调 P0 已完成、本阶段只做 Composer 简单选择器收口

2. **P1 目标**  
   - 抽 `showComposerSelectorPopover`（或等价 helper）：视口上下空间 → openAbove、IdeMotion/reduce-motion、IdePopoverHandle 生命周期与关闭回焦  
   - 对话模式 / 权限策略 / session 枚举：**内容层** → `sf.SelectPopup` + `SelectItemButton`（或 noVirtualization）  
   - **保持** `_ComposerSelectorTrigger`；禁止默认 `sf.Select` 整控件当 28px 芯片  
   - 模型配置：**仅可复用定位 helper**，面板内容 `_ModelConfigPopover` 不换 Select  
   - Session 布尔仍 chip toggle；More actions 留给 P2

3. **严格范围 / 禁止项**  
   - 禁止 NavigationMenu / Menubar 重写工具栏  
   - 禁止 hover 打开配置  
   - 禁止破坏底部优先向上弹层  
   - 禁止改模型配置异步保存/展开/冲突逻辑  
   - 禁止 feature 散落新的裸 `sf.showPopover`（应收口到 helper / showIdePopover）

4. **代码落点清单**  
   - `agent_mode_selector.dart`  
   - `agent_pane_composer.dart`（`_PermissionPolicyButton`、`_SelectorSelect`、可选 more actions 仅定位复用）  
   - `agent_model_config.dart`（可选：只换定位 helper）  
   - `ide_popover.dart` / 新建 core helper 的建议路径  
   - 相关 test：`agent_pane_pr3_test.dart`、`agent_conversation_widget_test.dart` 等

5. **验收 checklist**（从 plan P1 验收复制并可勾选化）

6. **验证命令**  
   - `dart format`、`flutter analyze`、相关 `flutter test`

7. **完成后要求**  
   - 同样：汇报 + 门禁  
   - 若 P1 通过，在回复末尾再输出 **P2 执行提示词**（可选阶段；说明可延期/取消条件）  
   - 若用户只要 P1，也仍应给出 P2 提示词草稿以便衔接

把 P1 提示词放在独立的 Markdown 代码块或清晰分隔的章节中，标题为：

  `## 阶段 P1 执行提示词（下一 Agent 可直接使用）`

确保下一 Agent **不依赖**再打开本 P0 文件也能执行 P1（允许要求阅读 plan 主文档）。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
六、验收标准（P0 门禁）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- [ ] `IdeBusySpinner` 公开 API 未破坏  
- [ ] 实现不再直接使用 Material `CircularProgressIndicator` 类型  
- [ ] 使用 `sf.CircularProgressIndicator`（或方案明确允许的 shadcn 等价物），size/stroke/color/semantics 正确  
- [ ] 调用方无需修改或仅因 format 无关变更  
- [ ] 门面注释标明 feature 应走 IdeLoadingIndicator / IdeBusySpinner  
- [ ] `dart format` 已处理改动文件  
- [ ] `flutter analyze` 无新增 error  
- [ ] 相关测试通过；若新增测试则稳定非 flaky  
- [ ] 未越界进入 P1+  
- [ ] 回复中已输出完整 P1 执行提示词  

现在开始执行 P0。
````

---

## 维护说明

| 项 | 内容 |
|---|---|
| 方案正文 | `plan/ide_primitives_shadcn_adaptation_plan.md` |
| 本文件 | 仅 P0 执行提示词；P1 提示词由 **完成 P0 的 Agent 生成** 并写在其回复中 |
| 可选沉淀 | P0 合并后可将 Agent 生成的 P1 提示词另存为 `plan/ide_primitives_shadcn_adaptation_p1_执行提示词.md` |

### 变更记录

| 版本 | 日期 | 说明 |
|---|---|---|
| v1.0 | 2026-07-28 | 初版：P0 执行提示词，并强制完成后输出 P1 提示词 |

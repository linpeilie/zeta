# WP-2 · part-of 单体 library 拆分

| 项 | 值 |
|----|----|
| 状态 | 未开始 |
| 规模 | 2–3 人天，1–2 个 PR |
| 依赖 | 无；**是 WP-3 / WP-4 的地基** |
| 门禁焦点 | G6 |
| 性质 | **纯重构**（零行为变化）：收尾 `bash tool/test_full.sh`；测试断言零修改是唯一正确性证据 |

---

## 0. 背景与机制说明

`agent_pane.dart:43-57` 把 `widgets/` 下 15 个文件声明为 `part of`。**part 的语义**：15 个文件共享同一 library 命名空间，所有 `_` 私有符号跨文件互相可见。后果：

- 改任何一个 `_` 符号，编译器无法告诉你爆炸半径（全 library 都能访问）；
- IDE「查找引用」、codegraph 调用图、review diff 的精度全部被拉低到 1.3 万行粒度；
- 文件看似拆分了，封装实际不存在。

**拆分原理**：把 part 文件变成独立 library = 每个文件自带 `import`，跨文件共享的符号必须**去下划线公开**。所以拆分的核心工作量是 T1 的符号盘点——确定哪些符号真的被跨文件用。

**参照样板**：`agent_file_change_evidence_card.dart` / `agent_provider_icon.dart` 已是独立 library（`agent_pane.dart:40-41` 正常 import），照它们的写法来。

## 1. 目标与非目标

- **目标**：15 个 part 文件全部独立；`agent_pane.dart` 收缩为 <400 行的壳；共享符号集中归属；零行为变化。
- **非目标**：不做视觉/逻辑调整（WP-4）、不做分发插件化（WP-3）、不动 ViewModel（WP-1）、不做 l10n 收编（WP-7）。**本 WP 只搬不改**——任何「顺手优化」都会污染 diff，让「零行为变化」无法自证。

## 2. 任务拆分

### T1 · 共享符号盘点（0.5 人天）

**目的**：产出每个 `_` 符号的去向表，这是整个 WP 的施工图纸。

**步骤**：

1. 对每个 part 文件，列出它**定义**的顶层 `_` 符号：

```powershell
# PowerShell，在仓库根目录跑；对每个 part 文件执行
Select-String -Path "lib/src/features/agent/presentation/widgets/agent_pane_cards.dart" `
  -Pattern "^(class|enum|typedef|mixin|[A-Za-z_<].*?)\s+_[A-Za-z]" | ForEach-Object { $_.Line }
```

2. 对每个符号，grep 它是否被**其他** part 文件引用：

```powershell
grep -rn "_AgentMarkdownBody" lib/src/features/agent/presentation --include=*.dart
# 命中 > 1 个文件 → 跨文件共享，去下划线；只命中定义文件 → 保持私有
```

3. 填表（贴进 PR 描述）：

| 符号 | 定义处 | 引用处 | 去向（styles 原地转换 / 独立文件公开 / 保持私有） |
|---|---|---|---|
| `_AgentMarkdownBody` | messages:603 | sections、cards | 独立文件 `agent_markdown_body.dart` 公开（T3） |
| `_agentItemTextStyle` | styles:13 | cards、messages、plan_panel… | styles 原地转换（T2） |
| … | … | … | … |

**已知归属预判**（盘点时验证补全）：

- **留在 `agent_pane_styles.dart` 原地转换**（T2）：`_agentSummaryTextStyle` / `_agentItemTextStyle` / `_agentMetaTextStyle` / `_agentHoverBackground` / `_operationGroupOuterPadding` / `_commandGroupSummary` / `_planPreviewText` / `_fileEditGroupSummarySpan` / `_toolKindLabel` / `_toolElapsedLabel` / `_agentMarkdownTheme` / `_agentUserBubbleMarkdownTheme` / `_agentHighlightTheme` / 5 个文案函数（WP-7 T1 之后再改它们，本次原样保留逻辑）。
- **独立成文件公开**：`_AgentMarkdownBody` / `_AgentRawMarkdownBody`（T3）。
- **保持私有**：只在定义文件内使用的卡片与 State 类。

**验收**：表格覆盖 15 个文件；每个符号有去向；无「待定」。

### T2 · `agent_pane_styles.dart` 原地转为独立 library（0.5 人天）

**做法**（2026-09-03 review 修正：不新建「kit」文件——原地转换保留 git blame/history，不发明新概念）：

1. 删掉第 1 行 `part of '../agent_pane.dart';`，补齐 import（`flutter/material.dart`、`zeta_ui`、`zeta_agent_core`、`app_localizations_x.dart`、`mixin_markdown_widget`（WP-6 后换 `zeta_markdown`，见 06 文档 §0.3）等，analyze 驱动补全）。
2. 被外部引用的符号去 `_` 前缀（T1 表已列明）；仅本文件使用的保持私有。
3. **可选二分**（推荐但不强制）：纯文案/摘要推导（`_commandGroupSummary` / `_planPreviewText` / `_fileEditGroupSummarySpan` / `_toolKindLabel` / `_toolElapsedLabel` / 5 个文案函数）移到同目录 `agent_pane_text.dart`——样式与文案推导职责分开，且 WP-7 T1/T2 只动文案文件，diff 更干净。做二分则两个文件各自独立转换。

**注意**：

- 这些函数大量引用 `context.l10n`、`IdeColors.of(context)`——import 照抄。
- 转换后该文件 import markdown 包；WP-6 T2 换包时只改这一处。

**验收**：`agent_pane_styles.dart`（+ 可选 `agent_pane_text.dart`）为独立 library，analyze 无 unresolved；符号与 T1 表一一对应。

### T3 · markdown 组件独立（0.5 人天，与 WP-6 协同）

**做法**：新文件 `widgets/agent_markdown_body.dart`：

```dart
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart'; // WP-6 后换 zeta_markdown
import 'package:zeta_ui/zeta_ui.dart';
import '../agent_markdown_cache.dart';
import 'agent_pane_styles.dart';

/// 会话正文 Markdown：经 [AgentMarkdownCache] 复用控制器，支持流式增量。
class AgentMarkdownBody extends StatefulWidget {
  const AgentMarkdownBody({
    required this.messageId,
    required this.data,
    required this.cache,
    this.useStreaming = false,
    this.themeBuilder = agentMarkdownTheme, // 来自 styles（原 _agentMarkdownTheme）
    super.key,
  });
  // ... 字段与现状 _AgentMarkdownBody（agent_pane_messages.dart:603-703）一一平移
}

/// 轻量一次性 Markdown（Plan 文档等无缓存场景）。
class AgentRawMarkdownBody extends StatelessWidget { /* 平移 :706-727 */ }
```

- 右键菜单抑制（`:698,729-737`）与 MouseRegion 光标补丁（`:686-689`）**原样保留**（WP-6 T9/T10 才删）。
- 引用点（messages / cards / sections）改为 import 本文件。

**验收**：`grep -rn "_AgentMarkdownBody\|_AgentRawMarkdownBody" lib` 零命中；widget 测试绿。

### T4 · 转换 L2–L3 文件（1 人天）

**每个文件的固定动作序列**（以 `agent_pane_cards.dart` 为完整示例）：

```dart
// 改前（第 1 行）
part of '../agent_pane.dart';

// 改后（按实际使用符号补齐；以下为 cards 的典型集合）
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_region_builder.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_styles.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
```

然后：

1. 该文件定义、被外部引用的符号去下划线（如 `_AgentCommandGroupCard` 若被 sections 引用 → `AgentCommandGroupCard`；T1 表已列明）。
2. `dart format . && flutter analyze`——analyze 会报「未定义」的漏 import 和「未使用」的多余 import，**靠 analyze 驱动补全**，不要手工猜。
3. 文件内 `_neverNotifies`（cards.dart:5）这类文件级私有 helper 保持私有不动。

**转换顺序**（依赖叶序，每步 analyze 驱动收敛）：`cards` → `messages` → `sections` → `header` → `plan_panel` → `navigation_rail` → `context_panel`。

**验收**：7 个文件全部无 `part of`；analyze 零新增告警；`test_affected.sh` 绿。

### T5 · 转换 L4 文件（0.5–1 人天）

同 T4 动作序列。顺序：`composer` → `composer_selector_popover` → `agent_model_config` → `agent_mode_selector` → 三个 picker（skill / slash_command / mention_file）。

**注意**：`agent_model_config.dart`（1921 行）本次**不再细分**——内部拆分留给 WP-4 控件收敛时顺手做，避免双重 diff。

### T6 · 壳收缩与全量门禁（0.5 人天）

1. `agent_pane.dart` 删 15 行 `part`，改为 import 各独立文件；确认壳只留：页面组合（`AgentPane` / `_AgentPaneState`）、`IdeConstraintBucketBuilder`、滚动协作、context panel 显隐接线、图片粘贴接线（WP-1 T4 之前保持 `dart:io` 现状）。
2. 自检 diff 纯度：

```powershell
git diff --stat                       # 应只有 import/part/符号重命名
git diff -U0 | grep -E "^[+-]" | grep -vE "^[+-]{3}|import |part |^[-+]\s*$" | less
# 上一条过滤后若还有大量逻辑行变化，说明夹带了行为修改，必须剔出
```

3. `bash tool/test_full.sh` 全绿；登记 `00-index.md` §6「开发记录」。

## 3. 风险与回滚

| 风险 | 缓解 |
|------|------|
| 中间态编译报错期长 | 严格叶序；analyze 驱动；单 PR 一次做完或按 L0–L3 / L4–L5 分两个 PR |
| 公开符号被 feature 外 import | 不建 barrel；review 检查 import 方均在 `lib/src/features/agent/` 内 |
| 夹带行为修改 | T6 的 diff 纯度自检是硬门槛 |

## 4. 完成定义（DoD）

- [ ] `grep -rnE "^(part |part of )" lib/src/features/agent/presentation` 零命中（注意必须带 `-E`，BRE 下 `|` 是字面量）。
- [ ] `agent_pane.dart` < 400 行。
- [ ] `tool/test_full.sh` 绿且测试断言零修改；CHANGELOG 无条目。

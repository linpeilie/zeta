# WP-6 · Markdown 渲染包本地 vendor 与深度改造

| 项 | 值 |
|----|----|
| 状态 | 进行中（T1 / T2 已完成） |
| 规模 | 11–16 人天（T1–T10 + T14–T15）；P2 可选项另计 |
| 依赖 | 无硬依赖；T2 换包与 WP-2 T3 协同；T7 与 WP-3 协同 |
| 门禁焦点 | G6（新 Package 论证）、G7（外链处理）、G8（主题 token） |

> **本文档所有「包内现状」代码均逐字摘自 pub 缓存 `mixin_markdown_widget-0.3.1`**（`%LOCALAPPDATA%\Pub\Cache\hosted\pub.flutter-io.cn\mixin_markdown_widget-0.3.1`），行号以该版本为准。

---

## 0. 背景

### 0.1 为什么必须改源码

| 需求 | 公开 API 能否满足 | 证据 |
|---|---|---|
| 外链用系统浏览器打开 | ✅ 能（`onTapLink` 参数） | `markdown_widget.dart:25`；inline builder `:111` 在 `onTapLink == null` 时把 recognizer 置 null |
| 代码块 Graphite 高亮 | ❌ 不能 | `_tokenStyle`（`code_syntax_highlighter.dart:230-296`）从 `linkStyle.color` **推导** 5 个语义色，无注入点 |
| 代码块工具栏（语言标签/行数/复制反馈） | ❌ 不能 | 工具栏硬编码在 `MarkdownCodeBlockView`（`markdown_block_widgets.dart:586-604`）；`codeBlockBuilder` 只换内容区 |
| 右键菜单收敛 + 中文 | ⚠️ 半能 | `contextMenuBuilder` 可完全替换 UI，但默认菜单仍先构建（`markdown_shortcuts_scope.dart:124-155`，`'Copy all'`/`'Clear selection'` 硬编码英文），且无法整体禁用 |
| 普通文本 I-Beam 光标 | ❌ 不能 | 光标解析在 `pretext_text_block.dart`（`:30,2405,2436`），无注入点；Zeta 现状是 MouseRegion 补丁（`agent_pane_messages.dart:686-689`） |
| 增删语法（`==mark==` 等） | ❌ 不能 | 语法列表是包私有常量（`markdown_syntaxes.dart:5-36`），`md.Document` 在包内两处构造（`markdown_document_parser.dart:239-244`、`markdown_syntaxes.dart:186-191`） |

### 0.2 上游基线

- 包：`mixin_markdown_widget 0.3.1`，MIT（可 fork 再发布），仓库 `MixinNetwork/flutter-plugins`（monorepo 子目录）。
- 依赖（全部保留）：`markdown ^7.3.3`、`re_highlight ^0.0.6`、`flutter_highlight ^0.7.0`、`html ^0.15.7`、`meta ^1.16.0`。
- 包内测试 12 个文件（`markdown_document_parser_test.dart` 等），**全部随迁**作为回归基线。
- 包内既有性能资产（**不得回退**）：`MarkdownController.appendChunk` 增量解析（`markdown_controller.dart:52-59` → `parseAppendingChunk`）、流式 draft/committed 分层（`_syncStreamingState` :148-167）、高亮 segment LRU 缓存（`code_syntax_highlighter.dart:16-21`，128 条）、`codeHighlightMaxLines` 降级（`:37-46`）、pretext 布局缓存。

### 0.3 Zeta 侧使用点（换包时的完整清单）

| 位置 | 用法 |
|---|---|
| `pubspec.yaml:24` | `mixin_markdown_widget: 0.3.1` |
| `agent_pane_messages.dart:7` | import |
| `agent_pane_styles.dart:6` | import（`_agentMarkdownTheme` / `_agentUserBubbleMarkdownTheme` / `_agentHighlightTheme`） |
| `agent_markdown_cache.dart:5` | import（`MarkdownController`） |
| `agent_markdown_render_descriptor.dart:5` | import（`MarkdownRenderDescriptor`） |
| `agent_pane_messages.dart:603-727` | `_AgentMarkdownBody`（缓存 + 流式 + 右键抑制 + 光标补丁）、`_AgentRawMarkdownBody` |
| `agent_pane_plan_panel.dart:17` | import（`MarkdownController`，Plan 文档） |
| 测试 | `agent_markdown_render_descriptor_test.dart`、`agent_conversation_widget_test.dart` 等 |

## 1. 目标与非目标

- **目标**：`packages/zeta_markdown` 成为 Zeta 的 markdown 渲染包；T4–T10 的产品化改造落地；包内测试基线全绿；建立上游同步机制。
- **非目标**：不重写解析器/选择引擎/pretext 布局；不追求与上游 API 兼容（允许破坏性改动）；不做 diff 高亮（WP-3 卡片职责）。

## 2. 总体设计

### 2.1 包结构

```
packages/zeta_markdown/
├── pubspec.yaml            # publish_to: 'none'；version 0.1.0 起独立语义化
├── README.md               # 定位、与上游关系、改造清单索引
├── UPSTREAM.md             # 基线版本/commit/日期、同步流程、本地改动清单
├── lib/
│   ├── zeta_markdown.dart  # barrel（保持原导出面 + 新增类型）
│   └── src/                # 原包 7 个目录原样迁入（clipboard/core/parser/render/selection/streaming/widgets）
│                           # + debug.dart 单文件
└── test/                   # 原包 12 个测试文件 + 新增改造测试
```

### 2.2 依赖方向（G6 论证）

```
zeta_markdown → {flutter, markdown, re_highlight, flutter_highlight, html, meta}
根应用      → zeta_markdown
```

- 不依赖 zeta_foundation / zeta_ui / 任何业务包——**它是通用 UI 包，Graphite 映射发生在根应用侧**（`agent_pane_styles.dart`），与 `mixin_markdown_widget` 今天的位置完全同构。
- 新 Package 论证（工程规范 §1 判据）：独立演进节奏（跟上游同步）+ 独立测试基线 + 明确单一职责（markdown 渲染）。不拆进 zeta_ui 的原因：zeta_ui 是 Graphite 设计系统，markdown 包是带自有主题系统的渲染引擎，二者主题模型不同；混入会让 zeta_ui 的「无业务依赖」纯度名义上保留、实际上被 markdown 的主题体系稀释。

### 2.3 改造分层原则

包内改动分两层，**所有 Zeta 定制都走「注入点」，不改默认行为**：

1. **机制层**（包内）：新增注入点（语法集、调色板、工具栏 builder、菜单开关与文案、光标）——默认值与上游 0.3.1 完全一致。
2. **映射层**（根应用）：把 Graphite token 映射为注入值（`agent_pane_styles.dart`）。

这样上游同步时冲突面最小：我们改的都是「新增参数 + 默认值不变」，上游改默认实现时 diff 清晰。

## 3. 任务拆分

### 阶段一：落地与接线（T1–T3）

#### T1 · fork 落地（0.5 人天）

**步骤**：

```powershell
# 1. 复制源码（pub 缓存即 0.3.1 发布内容）
$src = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.flutter-io.cn\mixin_markdown_widget-0.3.1"
New-Item -ItemType Directory -Force packages/zeta_markdown
Copy-Item -Recurse "$src\lib" packages/zeta_markdown/
Copy-Item -Recurse "$src\test" packages/zeta_markdown/   # 若缓存含 test；不含则从 GitHub tag 拉取
Copy-Item "$src\LICENSE" packages/zeta_markdown/       # MIT 义务：保留版权声明
```

2. `packages/zeta_markdown/pubspec.yaml`：

```yaml
name: zeta_markdown
description: Zeta 的 Markdown 渲染包（fork 自 mixin_markdown_widget 0.3.1，MIT）。
publish_to: 'none'
version: 0.1.0

environment:
  sdk: ^3.12.2          # 与 packages/zeta_ui 对齐（不写额外 flutter 下限）

dependencies:
  flutter:
    sdk: flutter
  markdown: ^7.3.3
  re_highlight: ^0.0.6
  flutter_highlight: ^0.7.0
  html: ^0.15.7
  meta: ^1.16.0

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  # 包内用 Material Icons（复制按钮等），缺这行独立跑包测试会有字体缺失警告
  # （与 packages/zeta_ui 同款处理）。
  uses-material-design: true
```

不新建 `analysis_options.yaml`——workspace 内包沿目录向上继承根分析配置（`packages/zeta_ui` 等现有包均无独立配置）。

3. 根 `pubspec.yaml` 的 `workspace:` 列表加 `packages/zeta_markdown`。
4. 全局重命名包标识：`mixin_markdown_widget` → `zeta_markdown`。清单（review 补全）：barrel 文件名与 `library` 声明；debug 日志前缀 `debugPrint('[mixin_markdown_widget] ...')`（`markdown_controller.dart:118,137`）→ `'[zeta_markdown]'`；`debug.dart` 的全局开关变量 `mixinMarkdownDebugLogging` → `zetaMarkdownDebugLogging`；**删除拼写别名 `typedef MarkownWidget = MarkdownWidget;`**（`markdown_widget.dart:57`，上游笔误的兼容别名，fork 不必继承）。`local_image_provider_io.dart`（dart:io）保留不删——删了会扩大上游同步 diff 面。
5. `UPSTREAM.md` 模板：

```markdown
## 基线
- 上游: MixinNetwork/flutter-plugins · packages/mixin_markdown_widget
- 版本: 0.3.1 · pub 发布日期 2026-01-28 · 同步日期 2026-09-03
## 同步流程
1. 上游发新版 → diff 其 lib/ 与本包 lib/
2. 逐文件评估合入；本包改动集中在「注入点新增」，冲突预期低
3. 合入后跑 bash tool/test_packages.sh
## 本地改动清单（每次改造追加）
- （初始）包标识重命名
```

**验收**：`flutter pub get` 成功；`dart analyze packages/zeta_markdown` 零错误（警告可留待 T3）。 ✅

**施工记录（2026-09-03）**：`packages/zeta_markdown` 落地，lib/ 31 个文件 + test/ 1 个 + LICENSE + README + UPSTREAM.md + pubspec；根 `workspace:` 已登记；`flutter pub get` 成功且 `pubspec.lock` 零改动（新包的依赖上游本来就在 lock 里）；包内 `flutter analyze` 零 issue。

**对照发布产物修正文档 4 处**（以 pub 缓存里的 0.3.1 为准）：

| # | 文档写的 | 实际 | 影响 |
|---|---|---|---|
| 1 | 依赖为 `markdown ^7.3.3` / `re_highlight ^0.0.6` / `flutter_highlight ^0.7.0` / `html ^0.15.7` / `meta ^1.16.0` | 上游 pubspec 是 `markdown ^7.3.0` / `re_highlight ^0.0.3` / `html ^0.15.6` / **`pretext ^0.1.0`** / **`flutter_math_fork ^0.7.4`**；**没有** `flutter_highlight`，**没有** `meta` | pubspec 按实际写。`pretext` 是包内预排文本布局（`pretext_text_block.dart`）的来源，`flutter_math_fork` 是数学公式渲染——两个都是文档漏掉的硬依赖。`flutter_highlight` 是**根应用**的依赖（Graphite 代码高亮），不是这个包的 |
| 2 | 包内测试 12 个文件全部随迁 | 发布产物只有 1 个测试文件（`mixin_markdown_widget_test.dart`，8256 行集成式套件） | 分文件测试没随 pub 发布。已迁入并改名 `zeta_markdown_test.dart`；缺口与补齐路径（上游 GitHub tag）记进 `UPSTREAM.md` |
| 3 | 不新建 `analysis_options.yaml` | **新建了** | 上游源码在本仓库的 lint 集下有 9 条 info（`prefer_initializing_formals` ×5、`use_null_aware_elements`、`unnecessary_underscores` ×2），而 `flutter analyze` 对 info 也返回非零 → `tool/test_packages.sh` 会红。为满足风格 lint 重写上游构造函数会让同步 diff 全面失配，与本 WP「冲突面最小」的原则冲突。改为包级 `analysis_options.yaml` 继承根配置、只关这三条风格规则（语义规则一条不关），与根配置整体排除 `third_party/**` 是同一取舍 |
| 4 | 目录结构里没提 `example/`、`benchmark/`、上游 `AGENTS.md` | 发布产物都带 | 三者均不迁入（各带独立 pubspec 与平台目录会污染 workspace 解析；第二份 AGENTS.md 会与仓库规则源冲突），取舍写进 `UPSTREAM.md` |
| 5 | `environment: sdk: ^3.12.2`（与 zeta_ui 对齐） | 改为 **`^3.5.0`**（跟上游 pubspec 一致） | 语言版本决定 `dart format` 用短风格还是 tall 风格。写 `^3.12.2` 时 `dart format .` 会重排 32 个文件里的 27 个，与上游 0.3.1 逐行失配，此后每次同步都要先把上游源码格式化成同一风格才能 diff——与 §2.3「上游同步时冲突面最小」直接冲突。改回 `^3.5.0` 后，vendor 文件与上游**逐字节相同**，实测 31 个 lib 文件只有 7 个有差异，且每个都对应 `UPSTREAM.md` 里登记的改动。代价：包内（含 T4–T10 新增的注入点）只能用 3.5 的语言特性。**用户决策** |

**顺带修掉一个上游 Windows 缺陷**（T3「失败分类处理」提前到这里，因为它让 `tool/test_packages.sh` 直接红）：`local_image_provider_io.dart` 用 `Uri.tryParse(path).scheme.isNotEmpty` 拒绝带 scheme 的输入，而 Windows 盘符会被解析成单字母 scheme（`C:` → `c`），导致**Windows 上本地图片一律返回 null**。改为只拒绝长度 > 1 的 scheme；上游同款测试 `default image renderer falls back to local files` 随之转绿（包内 180 条全绿）。已登记 `UPSTREAM.md`。

**重命名清单执行情况**：barrel 文件名 + import 路径 + `zetaMarkdownDebugLogging` + `[zeta_markdown]` 日志前缀 4 处 + `selection_host.dart` 的 focus debugLabel + 删除 `typedef MarkownWidget`。`MixinSelectionArea` 及其文件名**保留未改**——那里的 "Mixin" 是上游组织名而非包标识，改名会让选择区相关文件的同步 diff 全量失配（已在 `UPSTREAM.md` 记明）。

#### T2 · 根应用接线（0.5 人天）

1. 根 `pubspec.yaml`：删 `mixin_markdown_widget: 0.3.1`，加 `zeta_markdown: {workspace: true}`（参照 zeta_ui 的既有写法）。
2. 替换 §0.3 清单的 5 处 import（messages / styles / cache / descriptor / plan_panel）：

```powershell
grep -rl "package:mixin_markdown_widget" lib test packages | ForEach-Object {
  (Get-Content $_) -replace 'package:mixin_markdown_widget/mixin_markdown_widget.dart', 'package:zeta_markdown/zeta_markdown.dart' `
                   -replace 'package:mixin_markdown_widget/src/', 'package:zeta_markdown/src/' | Set-Content $_
}
# 第二条 replace 是防御性的：G6 要求只 import barrel，但换包时先确认没有 src 深路径遗漏
```

3. `flutter pub get && flutter analyze` 零错误；`bash tool/test_affected.sh` 绿。
4. **验收**：`grep -rn "mixin_markdown" lib test packages --include=*.dart` 零命中（UPSTREAM.md 除外）。 ✅

**施工记录（2026-09-03）**：根 `pubspec.yaml` 删 `mixin_markdown_widget: 0.3.1`、加 `zeta_markdown: ^0.1.0`（按仓库既有 workspace 包写法用版本约束，不用 `{workspace: true}`）。`pubspec.lock` 只少了 mixin 那一个 hosted 条目，镜像 url 未动。`flutter analyze` 零 issue；`test_affected.sh` 根包 2479 条 + 各内部包（含 zeta_markdown 180 条）全绿。

**§0.3 的使用点清单已过期，实际是 3 个 lib + 2 个测试**（WP-2/WP-3 重构后的落点）：

| 文档写的 | 实际 |
|---|---|
| `agent_pane_messages.dart:7` | 已被 WP-2 T3 抽成 `widgets/agent_markdown_body.dart:2` |
| `agent_markdown_render_descriptor.dart:5` | **文件不存在**（presentation 下只剩 `agent_timeline_extent_descriptor.dart`） |
| `agent_pane_plan_panel.dart:17` | **已无该 import** |
| `agent_pane_styles.dart:6`、`agent_markdown_cache.dart:5` | 仍在 |
| 「测试」 | 具体是 `agent_conversation_widget_test.dart:13` 与 `harness/agent_pane_test_harness.dart:9` |

另外换掉了两处提到旧包名的注释（`agent_markdown_body.dart` 的光标 workaround 与右键菜单抑制说明）。

#### T3 · 测试基线（0.5–1 人天）

1. 随迁测试逐个跑通：`flutter test packages/zeta_markdown/test`。
2. 失败分类处理：依赖漂移（`markdown` 包小版本行为差异）→ 固定依赖版本或适配断言；环境差异（字体/Skia）→ golden 测试标记或剔除并记录 UPSTREAM.md。
3. 把 `packages/zeta_markdown` 纳入 `tool/test_packages.sh` 覆盖（该脚本按 workspace 自动发现则无需改动，验证即可）。
4. **验收**：包内测试全绿或每条剔除有记录；CI 的 packages 分片覆盖新包。

### 阶段二：公开 API 可解（T4）

#### T4 · 外链系统浏览器打开（0.5 人天）

**现状**：`_AgentMarkdownBody` 未传 `onTapLink` → 链接不可点（recognizer 为 null，`markdown_inline_builder.dart:111`）。

**设计**：新增宿主侧工具（参照 `lib/src/ui/core/system_file_manager.dart` 的 `Process.start` 模式）：

```dart
// lib/src/ui/core/system_url_opener.dart（新文件）
/// 用系统默认浏览器打开 http/https 链接。
/// G7：url 不进日志与指标；非 http(s) 一律拒绝（fail-closed）。
abstract interface class SystemUrlOpener {
  Future<bool> openUrl(String url);
}

final class ProcessSystemUrlOpener implements SystemUrlOpener {
  const ProcessSystemUrlOpener();
  @override
  Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    // 三平台分发，模式照抄 system_file_manager.dart:
    //   linux: Process.start('xdg-open', [url], mode: detached)
    //   macos: Process.start('open', [url], ...)
    //   windows: Process.start('explorer.exe', [url], ...)（或 cmd /c start 的引号陷阱见该文件注释）
    // ...
  }
}
```

**接线**（`_AgentMarkdownBody.build`，`agent_pane_messages.dart:660-703` 区域）。注意 `MarkdownTapLinkCallback` 的真实签名是**三参数**（`markdown_types.dart:7-11`，review 修正）：

```dart
MarkdownWidget(
  controller: lease.controller,
  // ... 现有参数 ...
  // typedef MarkdownTapLinkCallback = void Function(String destination, String? title, String label)
  onTapLink: (destination, title, label) =>
      unawaited(_urlOpener.openUrl(destination)),  // 经组合根注入，测试装 fake
)
```

- 注入路径：`SystemUrlOpener` provider（fail-closed 声明 + 组合根装生产实现 + `zetaTestComposition` 装记录型 fake）。`_AgentRawMarkdownBody` 同样接线。
- **验收**：点击 agent 消息中的链接 → 系统浏览器打开；非 http(s) 链接点击无反应；单测覆盖 scheme 白名单（`javascript:`、`file:`、`ftp:` 拒绝）。

### 阶段三：P0 深改（T5–T7）

#### T5 · 语法集注入（1 人天）

**包内现状**：语法列表是私有常量，`md.Document` 在两处构造时引用：

```dart
// markdown_syntaxes.dart:5-36（现状，顺序敏感勿重排）
final List<md.BlockSyntax> _markdownBlockSyntaxes = List.unmodifiable([
  const md.FencedCodeBlockSyntax(), const MarkdownMathBlockSyntax(), ... ]);
final List<md.InlineSyntax> _markdownInlineSyntaxes = List.unmodifiable([
  MarkdownDollarMathSyntax(), ..., md.InlineHtmlSyntax()]);

// markdown_document_parser.dart:239-244（现状）
final document = md.Document(
  extensionSet: md.ExtensionSet.none,
  blockSyntaxes: buildMarkdownBlockSyntaxes(),
  inlineSyntaxes: buildMarkdownInlineSyntaxes(),
  encodeHtml: false,
);
```

**设计**：

```dart
// markdown_syntaxes.dart 新增（包内公开类型）
/// 可注入的语法集。默认值与上游 0.3.1 完全一致。
final class MarkdownSyntaxSet {
  const MarkdownSyntaxSet({required this.blockSyntaxes, required this.inlineSyntaxes});
  final List<md.BlockSyntax> blockSyntaxes;
  final List<md.InlineSyntax> inlineSyntaxes;

  /// 上游默认集（原两个私有列表原样搬入）。
  static final MarkdownSyntaxSet standard = MarkdownSyntaxSet(
    blockSyntaxes: _markdownBlockSyntaxes,
    inlineSyntaxes: _markdownInlineSyntaxes,
  );
}
```

**注入链**（三处改动）：

```dart
// 1. parser（markdown_document_parser.dart:30-33）
class MarkdownDocumentParser {
  const MarkdownDocumentParser({this.onTiming, this.syntaxSet});
  final MarkdownSyntaxSet? syntaxSet;
  // :239 处改为：final set = syntaxSet ?? MarkdownSyntaxSet.standard;
  //              md.Document(blockSyntaxes: set.blockSyntaxes, inlineSyntaxes: set.inlineSyntaxes, ...)
}

// 2. controller（markdown_controller.dart:14-22）
MarkdownController({
  String data = '',
  MarkdownDocumentParser? parser,
  MarkdownSyntaxSet? syntaxSet,          // 新增：parser 为空时用它构造 parser
  MarkdownCopySerializer? plainTextSerializer,
}) : _parser = parser ?? MarkdownDocumentParser(syntaxSet: syntaxSet), ...
// 注意：原 parser 默认是 const MarkdownDocumentParser()，带 syntaxSet 后不能 const——
// 在 initializer 里处理（如上），构造函数本身不需要 const。

// 3. markdown_syntaxes.dart:186-191 的第二处 md.Document（details/summary 内嵌解析）：
//    该函数是顶层工具函数，增加可选参数 MarkdownSyntaxSet? syntaxSet 并透传；
//    parser 调用它时把自身 syntaxSet 传下去。
```

**Zeta 侧**（`agent_markdown_cache.dart:99-104` 的 `MarkdownController(data: ...)` 创建点）：

```dart
MarkdownController(
  data: preferIncrementalUpdate ? '' : data,
  syntaxSet: ZetaMarkdownSyntaxSets.conversation,  // 根应用侧定义：standard 去掉不需要的语法
)
```

- **验收**：默认行为零变化（包内 parser 测试全绿）；Zeta 侧可注入裁剪集；新增单测：自定义语法集生效（如禁用 `TableSyntax` 后表格按段落渲染）。

#### T6 · 代码高亮 Graphite 调色板（1–2 人天）

**包内现状**：`_tokenStyle`（`code_syntax_highlighter.dart:230-296`）从 `theme.linkStyle.color` 推导 5 色，token 类别全集为：`comment/quote/doctag`、`keyword/selector-tag/literal/operator`、`string/regexp/subst`、`number/symbol/bullet`、`type/built_in/built_in-name/attr/attribute/variable/template-variable`、`title/title.function_/title.class_/function/section`、`meta/meta-keyword`、`emphasis`、`strong`、`link`、`punctuation`。

**设计**：

```dart
// 包内新文件 src/render/markdown_code_highlight_palette.dart
/// 代码高亮语义调色板。null 字段 = 回退到现状的 linkStyle 推导（上游默认行为不变）。
final class MarkdownCodeHighlightPalette {
  const MarkdownCodeHighlightPalette({
    this.comment, this.keyword, this.string, this.number,
    this.type, this.title, this.meta, this.link, this.punctuation,
  });
  final Color? comment;    // comment/quote/doctag（现状：mutedColor + italic）
  final Color? keyword;    // keyword/selector-tag/literal/operator（现状：accent + w700）
  final Color? string;     // string/regexp/subst
  final Color? number;     // number/symbol/bullet
  final Color? type;       // type/built_in/attr/variable...
  final Color? title;      // title/function/section（现状：+ w700）
  final Color? meta;       // meta/meta-keyword（现状：+ w600）
  final Color? link;       // link（现状：theme.linkStyle 全套）
  final Color? punctuation;
}
```

**改动点**：

1. `MarkdownThemeData` 加字段 `final MarkdownCodeHighlightPalette? codeHighlightPalette;`（`markdown_theme.dart` 字段区 `:475-509` 附近），并加入 `copyWith` 参数列表（该文件 copyWith 是逐字段的，**漏加编译器不报错**，必须人工核对）。
2. `_tokenStyle` 改造（`code_syntax_highlighter.dart:230`）：

```dart
TextStyle _tokenStyle(String token, {required TextStyle baseStyle, required MarkdownThemeData theme}) {
  final palette = theme.codeHighlightPalette;
  // 现状推导逻辑保留为 fallback：
  final accent = palette?.keyword ?? theme.linkStyle.color ?? const Color(0xFF0F6CBD);
  final stringColor = palette?.string ?? Color.lerp(accent, const Color(0xFF1F7A52), 0.6)!;
  // ... 每个语义色：palette?.x ?? 现状推导 ...
  // switch 的 token → 语义槽映射保持不变
}
```

**Zeta 侧映射**（`agent_pane_styles.dart` 的 `_agentHighlightTheme` 区域，WP-2 后为公开符号）：

```dart
MarkdownCodeHighlightPalette _agentCodeHighlightPalette(IdeColors colors) =>
  MarkdownCodeHighlightPalette(
    keyword: colors.info,            // 按 Graphite 语义选 token，设计走查定稿
    string: colors.success,
    number: colors.warning,
    comment: colors.textTertiary,
    type: colors.info,               // 待定稿
    title: colors.textPrimary,
    meta: colors.textSecondary,
    punctuation: colors.textSecondary,
  );
// 注入：_agentMarkdownTheme 构造 MarkdownThemeData 时传 codeHighlightPalette
```

- **验收**：默认（palette == null）渲染与上游逐像素一致（包内既有测试绿）；Zeta 侧明暗主题下代码块颜色全部来自 token；`flutter_highlight` 的 theme map 依赖（`_agentHighlightTheme` 现状）同步替换或保留兜底。

#### T7 · descriptor 守卫（0.5 人天，与 WP-3 协同）

**目的**：`MarkdownRenderDescriptor`（`agent_markdown_render_descriptor.dart`）是 extent 估算与真实渲染的契约——包改了布局行为时必须有测试拦住「descriptor 没跟上」。

**设计**（`test/src/features/agent/presentation/agent_markdown_descriptor_guard_test.dart`）：

```dart
testWidgets('descriptor 估算与真实渲染高度偏差在容差内', (tester) async {
  // 固定宽度 + 固定 markdown fixture（含代码块/表格/标题各一）
  // 1. 用 MarkdownRenderDescriptor 估算高度
  // 2. 真实 pump MarkdownWidget，取 RenderObject 高度
  // 3. 断言偏差 < 20%（虚拟化估算允许误差，但不能数量级失真）
});
```

- **验收**：T8（工具栏加高）落地时该测试**必须红**→ 更新 descriptor 后转绿——这就是它存在的意义。

### 阶段四：P1 深改（T8–T10）

#### T8 · 代码块工具栏 builder（1.5–2 人天）

**包内现状**：工具栏硬编码在 `MarkdownCodeBlockView.build`（`markdown_block_widgets.dart:586-604`）：一个 `Tooltip('Copy code') + IconButton(28×28, copy 图标)`，与内容区 `Row` 并排。调用链：`MarkdownWidget.codeBlockBuilder` → `MarkdownDocumentView`（`:467`）→ `MarkdownBlockBuilder._buildCodeBlock`（`markdown_block_builder.dart`，`onCopyCode` 在 `:1669`）→ `MarkdownCodeBlockView`。

**设计**：

```dart
// 包内 markdown_types.dart 新增 typedef
/// 代码块工具栏。context 提供语言、行数、复制回调与主题；
/// 返回 null = 不渲染工具栏。
typedef MarkdownCodeBlockToolbarBuilder = Widget? Function(
  BuildContext context,
  MarkdownCodeBlockToolbarData data,
);

final class MarkdownCodeBlockToolbarData {
  const MarkdownCodeBlockToolbarData({
    required this.language,      // fence info string，可能为空
    required this.lineCount,
    required this.onCopy,        // 现状的复制回调（写剪贴板）
    required this.theme,
  });
  final String? language;
  final int lineCount;
  final VoidCallback onCopy;
  final MarkdownThemeData theme;
}
```

**注入链**（与 `codeBlockBuilder` 同路径逐层透传）：

1. `MarkdownWidget` 加参数 `this.codeBlockToolbarBuilder`（`markdown_widget.dart:27` 附近）→ 传 `MarkdownDocumentView`（`:152` 区域）。
2. `MarkdownDocumentView` 加字段 → 传 `MarkdownBlockBuilder`（`:467` 区域）。
3. `MarkdownBlockBuilder._buildCodeBlock`（`markdown_block_builder.dart:1629-1652`）传 `MarkdownCodeBlockView`。**review 补充一个容易漏的透传**：`MarkdownCodeBlockView` 现状**收不到**语言与行数（`_buildDecoratedCodeBlock` `:1654-1673` 只传 theme/codeSpan/keys/onCopyCode）——必须给 view 新增两个构造参数，在 `_buildCodeBlock`/`_buildDecoratedCodeBlock` 处从 `block.language` 与 `block.code` 取得：

```dart
// MarkdownCodeBlockView 新增字段
final String? language;          // block.language（fence info string，可为空）
final int lineCount;             // lineCountOf(block.code)，highlighter 已有同款工具函数
```

4. `MarkdownCodeBlockView` 改造：

```dart
// markdown_block_widgets.dart:531 起
final MarkdownCodeBlockToolbarBuilder? toolbarBuilder;  // 新增字段

@override
Widget build(BuildContext context) {
  final toolbar = toolbarBuilder?.call(context, MarkdownCodeBlockToolbarData(
    language: language, lineCount: lineCount, onCopy: onCopyCode, theme: theme,
  ));
  // toolbar == null → 现状默认 Tooltip+IconButton（上游行为不变）
  // 否则用调用方 toolbar 替换 :586-604 的 Row 尾部
}
```

**Zeta 侧 Graphite 工具栏**（`_AgentMarkdownBody` 或 `agent_pane_styles.dart`）。**终审补充**：builder 每次 build 都被调用，「已复制」对勾是有态的——工具栏本体要做成一个私有 StatefulWidget（如 `_AgentCodeBlockToolbar`），builder 里返回该 Widget，`_copied` 状态由它自持（不要在 builder 闭包里捕获状态）：

```dart
Widget _agentCodeBlockToolbar(BuildContext context, MarkdownCodeBlockToolbarData data) {
  final colors = IdeColors.of(context);
  return Row(mainAxisSize: MainAxisSize.min, children: [
    if (data.language != null)
      Text(data.language!, style: IdeTextStyles.of(context).meta),   // 语言标签
    Text('${data.lineCount} lines', style: IdeTextStyles.of(context).meta),
    IdeButton.ghost(                                                  // 复制 + 已复制反馈
      icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
      onPressed: () { data.onCopy(); /* setState 显示 1.5s 对勾 */ },
    ),
  ]);
}
```

- **验收**：默认 builder 为 null 时包内测试全绿；Zeta 侧代码块出现语言标签 + 行数 + 复制反馈；**T7 的守卫测试先红后绿**（工具栏加高 → descriptor 更新）。

#### T9 · 右键菜单开关 + 文案注入（1 人天）

**包内现状**：`_showToolbar`（`markdown_document_view.dart:277-291`）→ `MarkdownContextMenu.show`（`markdown_shortcuts_scope.dart:113-178`）。菜单项：copy（`ContextMenuButtonType.copy`，平台本地化）、selectAll（同）、`'Copy all'`（`:145` 硬编码）、`'Clear selection'`（`:153` 硬编码）。

**设计**：

```dart
// markdown_types.dart 新增
/// 右键菜单的可注入文案。两个 ContextMenuButtonType 项由平台本地化，无需注入。
final class MarkdownContextMenuLabels {
  const MarkdownContextMenuLabels({this.copyAll = 'Copy all', this.clearSelection = 'Clear selection'});
  final String copyAll;
  final String clearSelection;
}
```

**改动点**：

1. `MarkdownWidget` 加两个参数：`this.enableContextMenu = true`、`this.contextMenuLabels = const MarkdownContextMenuLabels()`（`markdown_widget.dart:22` 附近）→ 透传 `MarkdownDocumentView`。
2. `_showToolbar` 开头加早退：

```dart
void _showToolbar(Offset globalPosition) {
  if (!widget.enableContextMenu || widget.selectionController == null) return;
  // ...
}
```

3. `MarkdownContextMenu.show` 加 `MarkdownContextMenuLabels labels` 参数，`:145` / `:153` 改用 `labels.copyAll` / `labels.clearSelection`。

**Zeta 侧**（`_AgentMarkdownBody`）：

```dart
MarkdownWidget(
  // ...
  enableContextMenu: true,   // 恢复菜单（现状是 ContextMenuRegion 抑制，:698,729-737 可删）
  contextMenuLabels: MarkdownContextMenuLabels(
    copyAll: context.l10n.agentMarkdownCopyAll,
    clearSelection: context.l10n.agentMarkdownClearSelection,
  ),
  contextMenuBuilder: _agentMarkdownContextMenu,   // 收敛项：Copy / Copy all / Clear selection（去 Select all）
)
```

- ARB 两 key 同步 `app_en.arb` / `app_zh.arb`（WP-7 T1 同批做）。
- `contextMenuBuilder` 的真实 typedef（`markdown_types.dart:34-39`，review 确认）：`Widget Function(BuildContext, MarkdownSelectionController, List<ContextMenuButtonItem>, TextSelectionToolbarAnchors)`——Zeta 的收敛菜单直接**过滤/重排传入的 buttonItems**（去掉 selectAll 项）再交给 `AdaptiveTextSelectionToolbar.buttonItems` 渲染即可，不必自绘菜单 UI。
- **验收**：右键出现收敛后的中文菜单；`enableContextMenu: false` 时无任何菜单；包内默认行为不变。

#### T10 · 文本光标修复（0.5 人天）

**包内现状**：`pretext_text_block.dart` 的 `mouseCursor` 字段（`:30`）为 null 时回落到 `MouseCursor.defer`（渲染处 `:2405,2436`）；链接处的 defer 是合理的（`markdown_inline_builder.dart:128-131,308-311`，无 recognizer 时让下层决定）——**只改普通文本的缺省**。

**改动**：

```dart
// pretext_text_block.dart：普通文本缺省光标
// 改前：mouseCursor ?? MouseCursor.defer
// 改后：mouseCursor ?? (selectable ? SystemMouseCursors.text : MouseCursor.defer)
```

（实现时先读 `:2405-2450` 确认 defer 的确切回落点；若该字段同时服务非文本块，则在 `MarkdownBlockBuilder` 构造文本块时显式传 `SystemMouseCursors.text`，不动渲染层缺省。）

**Zeta 侧**：删 `_AgentMarkdownBody` 的 MouseRegion 补丁（`agent_pane_messages.dart:686-689`）。

- **验收**：正文 hover 显示 I-Beam；链接 hover 显示手型；非文本块（图片等）光标不变。

### 阶段五：P2 可选（T11–T13，独立评估立项）

| 任务 | 规模 | 内容 |
|---|---|---|
| T11 · `==mark==` / `++ins++` 语法 | 1–2 人天 | 新 `md.InlineSyntax` 子类（参照 `MarkdownHighlightSyntax` 写法）+ 渲染映射（`mark` → 背景色 span）+ Zeta 语法集注册（T5 的注入点）。**先确认产品需要** |
| T12 · 高亮增量失效 | 2–3 人天 | 现状 segment 缓存 key = 全文（`code_syntax_highlighter.dart:113-116`），流式代码块每 chunk 全量重算。改为按「未闭合 fence 起点」分段缓存。**先 Profile 证实开销再动** |
| T13 · 选择引擎跨块复制保真 | 3–5 人天 | 复制时恢复 markdown 源格式（`MarkdownCopySerializer` 已留扩展点，`markdown_controller.dart:85-87`）。投入大，单独立项 |

### 阶段六：治理（T14–T15）

#### T14 · 上游同步机制（0.5 人天，持续）

- `UPSTREAM.md` 完整填写（T1 已建模板）；每季度或有安全修复时评估同步。
- 同步 SOP：`diff -r upstream/lib packages/zeta_markdown/lib` → 逐文件评估 → 合入后 `tool/test_packages.sh`。

#### T15 · 文档（0.5 人天）

- `packages/zeta_markdown/README.md`：定位、与上游关系、改造清单（T5/T6/T8/T9/T10 各一段 + 注入点示例）。
- `docs/guides/developer_guide.md` 加「Markdown 渲染」小节（如何改语法/高亮/工具栏，指向本包）。
- `AGENTS.md` §4 依赖清单加 `zeta_markdown`；`00-index.md` §6「开发记录」登记。

## 4. 风险与回滚

| 风险 | 缓解 |
|------|------|
| fork 后上游修复拿不到 | T14 同步机制；改造全部走注入点（§2.3），冲突面最小 |
| 包内测试基线失真 | T3 的剔除必须逐条记录原因；解析/增量/流式核心测试不允许剔除 |
| 高亮调色板破坏暗色主题 | T6 的 Zeta 映射走明暗双主题走查；默认 fallback 保持上游行为 |
| 工具栏加高引发布局抖动 | T7 守卫测试兜底；descriptor 同步更新 |
| 回滚 | T2 之前任何时刻可放弃；T2 之后回滚 = 恢复 pubspec + import（git revert 即可） |

## 5. 完成定义（DoD）

- [ ] `packages/zeta_markdown` 落地，根应用全量换包，`grep mixin_markdown` 零命中。
- [ ] T4–T10 全部落地；包内测试 + `tool/test_packages.sh` + `tool/test_full.sh` 绿。
- [ ] UPSTREAM.md / README / developer_guide 同步完成。
- [ ] CHANGELOG `[未发布]` 记录：链接可点击打开、代码块工具栏、右键菜单中文化、文本光标修复。

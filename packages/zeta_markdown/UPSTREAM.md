# 上游基线与同步

## 基线

- 上游：`MixinNetwork/flutter-plugins` · `packages/mixin_markdown_widget`
- 版本：`0.3.1`（源码取自 pub 缓存 `pub.flutter-io.cn/mixin_markdown_widget-0.3.1`，即发布产物）
- 同步日期：2026-09-03
- 许可证：MIT（`LICENSE` 原样保留，含上游版权声明）

## 与发布产物的差异（vendor 时的取舍）

| 上游文件 | 处理 | 原因 |
|---|---|---|
| `lib/` | 全量迁入 | 本包主体 |
| `test/mixin_markdown_widget_test.dart` | 迁入并改名 `test/zeta_markdown_test.dart` | 唯一的回归基线 |
| `LICENSE` | 原样保留 | MIT 义务 |
| `pubspec.yaml` | 重写 | 改包名 / `publish_to: none` / workspace 解析 / SDK 下限对齐仓库 |
| `README.md` | 重写 | 定位换成「Zeta 的 fork」 |
| `analysis_options.yaml` | **不迁入** | workspace 内包沿目录向上继承仓库根配置 |
| `AGENTS.md` | **不迁入** | 仓库的 `AGENTS.md` 是唯一规则源，第二份会造成路由歧义 |
| `example/`、`benchmark/` | **不迁入** | 各带独立 pubspec 与平台目录，会污染 workspace 解析；需要时回上游仓库看 |

**测试基线是完整的**（2026-09-03 核实）：稀疏 clone 上游 tag `mixin_markdown_widget-v0.3.1` 比对后确认——上游 `test/` 下**本来就只有这一个文件**（8256 行的集成式套件），发布产物没有裁剪；`lib/` 与 tag 逐字节一致（仅行尾差异）。所以不存在「分文件测试待回补」这回事。

## 本地新增测试的放置约定

Zeta 自己加的测试放**独立文件**（`test/zeta_*.dart`），不要写进 `test/zeta_markdown_test.dart`。那个文件除了改名之外与上游逐字节相同，同步时直接整文件比对即可；混入本地用例会让它每次都冲突。

## 同步流程

1. 上游发新版 → diff 其 `lib/` 与本包 `lib/`。
2. 逐文件评估合入；本包改动集中在「注入点新增 + 默认值不变」，冲突预期低。
3. 合入后跑 `bash tool/test_packages.sh`。
4. 更新本文件的基线版本与下方改动清单。

## 本地改动清单

每次改造往下追加，**不要删除历史条目**——它就是同步时的冲突预警清单。

### 2026-09-03 · WP-6 T1 · 包标识重命名

- barrel `lib/mixin_markdown_widget.dart` → `lib/zeta_markdown.dart`
- 全部 `package:mixin_markdown_widget/...` import → `package:zeta_markdown/...`
- 调试开关 `mixinMarkdownDebugLogging` → `zetaMarkdownDebugLogging`（`lib/src/debug.dart`）
- 调试日志前缀 `[mixin_markdown_widget]` → `[zeta_markdown]`（block builder / document view / controller 共 4 处）
- 焦点 debugLabel `mixin_markdown_widget.selection` → `zeta_markdown.selection`（`selection_host.dart`）
- 删除拼写别名 `typedef MarkownWidget = MarkdownWidget;`（`markdown_widget.dart`，上游笔误的兼容别名，fork 不继承）
- 测试临时文件名 `mixin_markdown_widget_test_image.png` → `zeta_markdown_test_image.png`

### 2026-09-03 · WP-6 T1 · 修 Windows 本地图片解析

`lib/src/render/local_image_provider_io.dart`：Windows 盘符会被 `Uri.tryParse`
解析成单字母 scheme（盘符路径 `C:` 开头 → scheme `c`），上游按 `scheme.isNotEmpty`
拒绝，导致 Windows 上本地图片全部返回 null。改为只拒绝长度 > 1 的 scheme。

上游同款测试 `default image renderer falls back to local files` 在 Windows
上因此失败；这是上游缺陷而非 vendor 引入。若上游后续自行修复，同步时以上游
实现为准并删除本条。

守卫测试：`test/zeta_local_image_provider_test.dart`（Zeta 新增）。上游同款测试
`default image renderer falls back to local files` 在 Windows 上原本失败，修复后
转绿。

### 2026-09-03 · WP-6 T5 · 语法集注入点

默认行为零变化，新增的都是「多一个可选参数」：

- `lib/src/parser/markdown_syntaxes.dart`：新增公开的 `MarkdownSyntaxSet`
  （`standard` 就是原来那两份私有列表）；`MarkdownHtmlBlockSyntax` 增加可选的
  `nestedSyntaxSet` 惰性引用，`<details>` 内部的嵌套解析改用它，缺省仍是标准集。
- `lib/src/parser/markdown_document_parser.dart`：构造增加 `syntaxSet`，
  `md.Document` 改用 `set.documentBlockSyntaxes` / `set.inlineSyntaxes`。
- `lib/src/widgets/markdown_controller.dart`：构造增加 `syntaxSet`（与 `parser`
  互斥，同时给会断言失败）。
- `lib/zeta_markdown.dart`：barrel 增加 `export 'src/parser/markdown_syntaxes.dart'`
  ——宿主要组合裁剪集就得拿到这些语法类型，而 G6 要求只 import barrel。

`documentBlockSyntaxes` 会把集合里的 `MarkdownHtmlBlockSyntax` 重新绑定到本
集合上（惰性，避免成环），并按集合缓存结果；否则外层裁剪了语法而 `<details>`
内部仍按默认集解析，同一份文档里会出现两套语法。

测试：`test/zeta_syntax_set_test.dart`（默认集与上游列表逐条一致、裁剪生效、
嵌套片段跟随裁剪、controller 接线与互斥断言）。

### 2026-09-03 · WP-6 T6 · 代码高亮调色板注入点

默认行为零变化（调色板为空 = 逐色沿用上游从 `linkStyle.color` 的推导）：

- 新文件 `lib/src/render/markdown_code_highlight_palette.dart`：
  `MarkdownCodeHighlightPalette`，9 个可空槽位（comment / keyword / string /
  number / type / title / meta / link / punctuation），带 `lerp` 与**值语义**
  `==`/`hashCode`。
- `lib/src/widgets/markdown_theme.dart`：新增**可选**字段
  `codeHighlightPalette`（可选是为了不动任何既有构造点），并同步补进
  `copyWith` / `lerp` / `debugFillProperties` / `hashCode` / `operator ==`
  ——这五处都是逐字段写的，漏一处编译器不会报错。
- `lib/src/render/code_syntax_highlighter.dart`：`_tokenStyle` 的每个语义色改成
  「槽位 ?? 上游推导」。上游把 `type` 与 `meta` 共用一个推导色，这里拆成两槽，
  都不传时仍是同一个值。
- `lib/zeta_markdown.dart`：barrel 导出调色板文件。

**值语义是硬要求**：宿主通常在 build 里现算主题，而 `MarkdownDocumentView`
按 `theme !=` 决定要不要清空整份 block 行缓存——引用相等会让每帧都清，并连带
撞上布局断言（同 T4 那个坑）。

测试：`test/zeta_code_highlight_palette_test.dart`（默认推导不变 / 逐槽位生效且
未给的槽位仍走推导 / 主题值相等与不等 / lerp / isEmpty）。

### 2026-09-03 · WP-6 T8 · 代码块工具栏注入点

默认行为零变化（不注入 builder = 上游那颗复制按钮）：

- `lib/src/widgets/markdown_types.dart`：新增 `MarkdownCodeBlockToolbarData`
  （language / lineCount / onCopy / theme）与 `MarkdownCodeBlockToolbarBuilder`。
- `lib/src/render/markdown_block_widgets.dart`：`MarkdownCodeBlockView` 增加
  `language` / `lineCount` / `toolbarBuilder` 三个字段。**三态语义**：不注入
  builder → 默认复制按钮；builder 返回 widget → 用它替换；builder 返回 null →
  不渲染任何工具栏。
- `lib/src/render/builder/markdown_block_builder.dart`：新增
  `codeBlockToolbarBuilder` 字段，并在构造 view 时补上 `language`（`block.language`）
  与 `lineCount`（复用 highlighter 的 `lineCountOf`）——上游这两项本来没往下传。
- `lib/src/render/markdown_document_view.dart` / `lib/src/widgets/markdown_widget.dart`：
  逐层透传。

**没有**把 `codeBlockToolbarBuilder` 加进 `didUpdateWidget` 的比较列表：与
`codeBlockBuilder` 保持一致，也避免宿主传闭包时每帧清空 block 行缓存（见 T4）。
文档注释里写明要传稳定引用。

测试：`test/zeta_code_block_toolbar_test.dart`（默认按钮 / 自绘替换并拿到语言与
行数 / 返回 null 不渲染 / onCopy 复用写剪贴板 / 无语言时 language 为 null）。

### 2026-09-03 · WP-6 T9 · 右键菜单开关与文案注入

默认行为零变化（不传参 = 菜单照常弹、自造项仍是英文原文）：

- `lib/src/widgets/markdown_types.dart`：新增 `MarkdownContextMenuLabels`
  （`copyAll` / `clearSelection`，默认值就是上游硬编码的英文，带值语义 `==`）。
  `copy` / `selectAll` 两项用的是 `ContextMenuButtonType`，由平台本地化，**不**
  纳入注入面。
- `lib/src/render/shortcuts/markdown_shortcuts_scope.dart`：`MarkdownContextMenu.show`
  增加 `labels` 参数，两处硬编码字符串改用它。
- `lib/src/render/markdown_document_view.dart`：新增 `enableContextMenu`（默认
  true）与 `contextMenuLabels`；`_showToolbar` 开头按开关早退。
- `lib/src/widgets/markdown_widget.dart`：两个参数逐层透传。

`MixinSelectionArea` 里的另一处 `MarkdownContextMenu.show` **未接线**：那是独立
的跨组件选区入口，Zeta 没有用到；接了反而扩大同步面。它继续使用默认英文文案。

测试：`test/zeta_context_menu_test.dart`（默认英文 / 注入生效 / 关掉开关后右键
无任何菜单 / 文案值语义）。

**测试要点**：右键要点在**首行文字**上。`useColumn: true` 时组件盒可能比内容高，
`getCenter` 会落到空白处，菜单不会弹——这跟开关无关，别误判成回归。

### 2026-09-03 · WP-6 T10 · 正文缺省鼠标光标

默认行为零变化（不传 `mouseCursor` = 上游的 `MouseCursor.defer`）：

- `lib/src/render/pretext_text_block.dart`：`MarkdownPretextTextBlock` 两个构造
  各加可选 `mouseCursor`；原 `build` 更名 `_buildContent`，非空时在**块级**包一层
  `MouseRegion`。
- `lib/src/render/builder/markdown_block_builder.dart`：5 处 `.rich(` 构造统一传
  `_defaultTextCursor`——可选中时 `SystemMouseCursors.text`，否则 null。

**为什么包在块级而不是改 span 缺省**：span 侧有 9 处构造点，逐处改动大且容易漏；
块级 `MouseRegion` 只声明「缺省」，run 自带的光标（链接的 click）在更内层、命中
时优先生效，语义与逐 span 改一致。非文本块（图片、表格、代码块）不经这个路径，
光标不受影响——这正是宿主外层套 `MouseRegion` 那种补丁做不到的。

测试：`test/zeta_text_cursor_test.dart`（可选中为 I-Beam / 不可选中保持 defer /
挂 onTapLink 后链接 span 是 click）。

**未改**（有意保留，减小同步 diff 面）：

- `lib/src/selection/mixin_selection_area.dart` 与其中的 `MixinSelectionArea` —— 这里的 "Mixin" 是上游组织名而非包标识；改名会让选择区相关文件的同步 diff 全量失配。
- `lib/src/render/local_image_provider_io.dart`（含 `dart:io`）—— 删除会扩大同步 diff 面；本包不进 `zeta_ui`，不受其纯度约束。

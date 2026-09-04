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

**未改**（有意保留，减小同步 diff 面）：

- `lib/src/selection/mixin_selection_area.dart` 与其中的 `MixinSelectionArea` —— 这里的 "Mixin" 是上游组织名而非包标识；改名会让选择区相关文件的同步 diff 全量失配。
- `lib/src/render/local_image_provider_io.dart`（含 `dart:io`）—— 删除会扩大同步 diff 面；本包不进 `zeta_ui`，不受其纯度约束。

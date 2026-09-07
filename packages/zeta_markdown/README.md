# zeta_markdown

Zeta 的 Markdown 渲染包：fork 自 [`mixin_markdown_widget`](https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/mixin_markdown_widget) `0.3.1`（MIT）。

## 为什么是 fork 而不是依赖

上游的设计意图是「可换主题的阅读器」，扩展点止于 code / image / bullet 三件套。Zeta 需要的几件事都没有注入点，只能改源码：

- 代码块用 Graphite token 上色（上游从 `linkStyle.color` 推导语义色）
- 代码块工具栏（语言标签 / 行数 / 复制反馈）
- 右键菜单收敛与中文化
- 普通文本的 I-Beam 光标
- 增删语法集（`==mark==` 等）

上游基线、定制记录和同步步骤见 [UPSTREAM.md](UPSTREAM.md)。

## 定位与依赖方向

```
zeta_markdown → {flutter, markdown, re_highlight, pretext, flutter_math_fork, html}
根应用        → zeta_markdown
```

它是**通用 UI 包**，不依赖 `zeta_foundation` / `zeta_ui` / 任何业务包。Graphite token 的映射发生在根应用侧（`lib/src/features/agent/presentation/widgets/agent_pane_styles.dart`），与上游包今天在依赖图里的位置完全同构。

不并入 `zeta_ui` 的原因：`zeta_ui` 是 Graphite 设计系统，本包是带自有主题系统的渲染引擎，两套主题模型混在一起会让 `zeta_ui` 的「无业务依赖」纯度名义上保留、实际被稀释。

## 改造原则

所有 Zeta 定制都走**注入点**，不改默认行为：

1. **机制层**（包内）：新增注入点，默认值与上游 0.3.1 完全一致。
2. **映射层**（根应用）：把 Graphite token 映射成注入值。

这样上游同步时冲突面最小——我们改的都是「新增参数 + 默认值不变」。

## 注入点清单

每个都遵守「默认值 = 上游行为」，不传参时渲染结果与 `mixin_markdown_widget 0.3.1`
一致。各项定制的源码位置和测试记录见 [UPSTREAM.md](UPSTREAM.md#本地改动清单)。

| 注入点 | 类型 | 解决什么 |
|---|---|---|
| `MarkdownSyntaxSet` | `MarkdownDocumentParser` / `MarkdownController` 的 `syntaxSet` | 语法集原先是包私有常量，宿主既不能裁剪也不能增补 |
| `MarkdownCodeHighlightPalette` | `MarkdownThemeData.codeHighlightPalette` | 代码高亮原先从 `linkStyle.color` 推导 5 色，没有注入口 |
| `MarkdownCodeBlockToolbarBuilder` | `MarkdownWidget.codeBlockToolbarBuilder` | 工具栏原先硬编码成一颗复制按钮 |
| `enableContextMenu` / `MarkdownContextMenuLabels` | `MarkdownWidget` 同名参数 | 右键菜单原先无法关闭，两项文案硬编码英文 |
| `mouseCursor`（文本块级） | 由 `MarkdownBlockBuilder` 按可选中态自动传入 | 正文原先是 `MouseCursor.defer`，桌面端表现为箭头 |

### 用法

```dart
MarkdownWidget(
  controller: controller,                       // 语法集在 controller 上注入
  theme: theme,                                 // 调色板挂在 theme 上
  onTapLink: _handleTapLink,                    // 稳定引用，见下方警告
  codeBlockToolbarBuilder: myCodeBlockToolbar,  // 顶层函数
  contextMenuLabels: MarkdownContextMenuLabels(
    copyAll: l10n.copyAll,
    clearSelection: l10n.clearSelection,
  ),
  contextMenuBuilder: myContextMenu,            // 过滤/重排 buttonItems 即可
);

final controller = MarkdownController(
  data: text,
  syntaxSet: MarkdownSyntaxSet(                 // 只删不重排：block 语法先到先匹配
    blockSyntaxes: MarkdownSyntaxSet.standard.blockSyntaxes
        .where((s) => s is! md.TableSyntax)
        .toList(growable: false),
    inlineSyntaxes: MarkdownSyntaxSet.standard.inlineSyntaxes,
  ),
);

final theme = base.copyWith(
  codeHighlightPalette: const MarkdownCodeHighlightPalette(
    keyword: Color(0xFF...), string: Color(0xFF...),  // 不给的槽位回退上游推导
  ),
);
```

### ⚠️ 回调与主题必须是稳定引用

`MarkdownDocumentView.didUpdateWidget` 按**引用**比较 `theme` 与 `onTapLink`，
不相等就清空整份 block 行缓存，而 block 的 GlobalKey 仍被复用——渲染对象会在同一
帧里被拆装，直接撞上 Flutter 的布局断言。

所以：

- 回调传 State 的绑定方法或顶层函数，**不要在 build 里现写闭包**；
- 自定义主题字段（如调色板）必须有值语义 `==`，宿主在 build 里现算主题才不会每帧
  失配。本包新增的 `MarkdownCodeHighlightPalette` / `MarkdownContextMenuLabels`
  都实现了值相等。

## 上游同步

基线版本、与发布产物的差异、逐次改动清单、同步流程都在 [`UPSTREAM.md`](UPSTREAM.md)。**每次改包内代码都要往那份清单追加一条。**

## 测试

```sh
cd packages/zeta_markdown && flutter test    # 或仓库根：bash tool/test_packages.sh
```

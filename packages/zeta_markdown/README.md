# zeta_markdown

Zeta 的 Markdown 渲染包：fork 自 [`mixin_markdown_widget`](https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/mixin_markdown_widget) `0.3.1`（MIT）。

## 为什么是 fork 而不是依赖

上游的设计意图是「可换主题的阅读器」，扩展点止于 code / image / bullet 三件套。Zeta 需要的几件事都没有注入点，只能改源码：

- 代码块用 Graphite token 上色（上游从 `linkStyle.color` 推导语义色）
- 代码块工具栏（语言标签 / 行数 / 复制反馈）
- 右键菜单收敛与中文化
- 普通文本的 I-Beam 光标
- 增删语法集（`==mark==` 等）

决策记录见 `.workflow/plan/2026-09-03-agent-conversation-ui-rendering/00-index.md` 的 DR-001；改造任务拆解见同目录 `06-wp6-markdown-vendor.md`。

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

## 上游同步

基线版本、与发布产物的差异、逐次改动清单、同步流程都在 [`UPSTREAM.md`](UPSTREAM.md)。**每次改包内代码都要往那份清单追加一条。**

## 测试

```sh
cd packages/zeta_markdown && flutter test    # 或仓库根：bash tool/test_packages.sh
```

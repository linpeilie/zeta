# 会话 UI 渲染优化 · 总索引与开发记录

> 任务类型：plan（方案文档集）
> 创建日期：2026-09-03
> 基准分支：`dev`
> 适用范围：`lib/src/features/agent/`、`packages/zeta_agent_core`、`packages/zeta_ui`、新增 `packages/zeta_markdown`

---

## 1. 这份文档集是什么

2026-09-03 对会话 UI 渲染实现做了一轮完整摸底（主链路、markdown 渲染、表现层组织质量三路分析），结论拆成 **7 个工作包（WP-1 ~ WP-7）**。本文档是索引与开发记录；每个 WP 一份独立文档，任务级拆解，可直接用于开发。

**使用方式**：

1. 动手前读 [`AGENTS.md`](../../../AGENTS.md) §2 路由表对应行 + 本 WP 文档的「门禁对照」节。
2. 每完成一个任务：在 WP 文档对应任务前的 checkbox 打勾，并在本文档 §6「开发记录」追加一行（日期 / WP-任务 / PR 或 commit / 备注）。
3. 任务状态用语：**未开始 / 进行中 / 已完成 / 已放弃（注明原因）**。
4. 方案级偏差（改目标、改链路、改拆分）必须先回本文件登记决策记录（§3），再改 WP 文档。

**任务粒度约定**（2026-09-03 二次修订起生效）：每个任务按「目的 → 现状（真实代码锚点，含路径行号）→ 设计说明（含为什么）→ 实施步骤（伪代码/代码骨架）→ 验收 → 测试」展开。开发者按文档直接实现，**不需要重新设计方案**；发现现状代码与文档摘录不一致（行号漂移、符号改名）时以仓库代码为准，并回写修正对应 WP 文档。

## 2. 现状结论摘要（2026-09-03 分析）

**机制层健康**：core 的事件管线 / reducer / TimelineStore / 虚拟化 / 投影缓存方向正确，性能手段齐备（双修订号、帧合并调度、block 级虚拟化、markdown LRU、宽度档位缓存）。

**债务集中在三处**：

| # | 债务 | 证据 |
|---|------|------|
| D1 | 同一事实四道转手（迁移中间态） | TimelineStore → `AgentConversationUiStateStore`（presentation，5 个 ValueNotifier）→ `AgentConversationSliceComposition`（app 攒批）→ `AgentConversationSliceStore`（application）→ `AgentConversationSliceNotifier`（Riverpod 镜像）→ selector |
| D2 | 越层 god object | `lib/src/features/agent/presentation/agent_conversation_view_model.dart` 4344 行，持有 core runtime、直调 bundle 端口、内含 `dart:io` 与纯数据推导 |
| D3 | part-of 单体 library | `agent_pane.dart:43-57` 挂 15 个 part 文件，会话 UI 共 ~13,400 行单一 library，文件边界无封装效力 |

**Markdown 专项**：`mixin_markdown_widget 0.3.1`（hosted，精确锁定）。当前真实缺陷与妥协：链接全部不可点（全仓库 `onTapLink` 零调用）；右键菜单只能整体禁用（空组件 hack，`agent_pane_messages.dart:698,729-737`）；文本光标 workaround（`:686-689`）；代码高亮双体系并存（包内 `re_highlight` 魔法色 vs 项目 `flutter_highlight` + Graphite）；语法集 / token 配色 / 代码块工具栏 / 块级 builder 均无公开扩展点。

## 3. 决策记录（ADR 简表）

| 编号 | 日期 | 决策 | 理由 | 状态 |
|------|------|------|------|------|
| DR-001 | 2026-09-03 | **`mixin_markdown_widget` vendor 到本地深度改造**，落点为 `packages/zeta_markdown`（改名 fork） | 包设计意图是「可换主题的阅读器」而非「可深度定制的 IDE 组件」；扩展点止于 code/image/bullet 三件套；语法集、token 配色、代码块工具栏、右键菜单本地化均须改源码；MIT 许可证允许；版本本就精确锁定，vendor 不损失自动升级；选区描述符与渲染器在包内强耦合（`markdown_descriptor_extractor.dart:332-343`），包外自绘代码块会让选区几何错位 | 已拍板（用户决策） |
| DR-002 | 2026-09-03 | fork 放 `packages/zeta_markdown` 而非 `third_party/` 或 `zeta_ui` | 包含 `dart:io`（`local_image_provider_io.dart`），违反 zeta_ui 约束（G6）；`third_party/` 目前只放协议 schema，不开代码包先例；packages/ 可被 `tool/test_packages.sh` 自动发现 | 已拍板 |
| DR-003 | 2026-09-03 | WP 执行顺序建议：WP-7 → WP-6 阶段一/二（T1–T4）→ WP-2 → WP-4/WP-3 穿插 → WP-1 → WP-5 按需 | WP-2 是 WP-3/WP-4 的地基；WP-1 与其他包正交；WP-5 等真实长会话压力 | 建议，待确认 |

## 4. WP 总览

| WP | 标题 | 规模（人天） | 依赖 | 门禁焦点 | 状态 | 文档 |
|----|------|------------|------|---------|------|------|
| WP-1 | 切片 owner 归位 + ViewModel 拆分 | 10–14 | 独立，建议 WP-2 之后降低冲突 | G3 G6，一份状态一个 owner | 进行中 | [01-wp1-slice-ownership.md](01-wp1-slice-ownership.md) |
| WP-2 | part-of 单体 library 拆分 | 2–3 | 无（WP-3/WP-4 的地基） | G6 | 未开始 | [02-wp2-part-of-split.md](02-wp2-part-of-split.md) |
| WP-3 | 渲染分发插件化（renderer 注册表） | 3–4 | WP-2 | G1 G4（registry 保持中立） | 未开始 | [03-wp3-renderer-registry.md](03-wp3-renderer-registry.md) |
| WP-4 | 控件收敛下沉 zeta_ui | 4–5 | WP-2（可穿插） | G8；zeta_ui 纯度 | 未开始 | [04-wp4-zeta-ui-convergence.md](04-wp4-zeta-ui-convergence.md) |
| WP-5 | 历史分页 / 窗口化 | 5–8（含 spike） | 需先 spike；WP-1 之后 | G2 G3 G6 | 未开始 | [05-wp5-history-pagination.md](05-wp5-history-pagination.md) |
| WP-6 | **Markdown vendor + 深度改造** | 11–16（T1–T10 + 治理；P2 另计） | 无 | G6 G7 G8；包治理 | 未开始 | [06-wp6-markdown-vendor.md](06-wp6-markdown-vendor.md) |
| WP-7 | 卫生小修清单 | 2–3 | 无（T3 是 WP-1 解锁条件，优先） | G6 G7 G8 | 未开始 | [07-wp7-hygiene.md](07-wp7-hygiene.md) |

**依赖图**：

```
WP-7（独立，随时）     WP-6（独立，已决策优先做）
WP-2 ──→ WP-3
   └────→ WP-4
WP-1（独立，大重构，建议 WP-2 完成后减少 rebase 面）
WP-5（spike 结论后再排期）
```

## 5. 通用开发约定（所有 WP 遵守）

1. **分支**：基于 `dev` 开 `feature/<wp 简述>` 分支；一个 WP 允许拆多个 PR，每个 PR 独立过门禁。
2. **收尾协议**（每次改完代码，缺一不可）：
   ```sh
   dart format .
   flutter analyze
   bash tool/test_affected.sh        # 行为变化时
   bash tool/test_full.sh            # 重构类 WP（WP-1/WP-2/WP-3）收尾必跑
   bash tool/test_packages.sh        # 动了 packages/ 时
   ```
   `dart_test.yaml` 并发固定 2，不改。
3. **提交**：Conventional Commits；用户可感知变化写 `CHANGELOG.md` `[未发布]`；本目录文档随代码一起提交，粘贴日志/路径前脱敏（G7）。
4. **架构边界变更**（WP-1/WP-5/WP-6 涉及）：按 `AGENTS.md` §6 同步 `AGENTS.md`、`docs/architecture/`（engineering_standards / design_document / overview + overview.en）、`docs/guides/`（developer_guide / glossary + glossary.en）、`CONTRIBUTING.md`(+en)、必要时 `CLAUDE.md`。
5. **测试落位**：根 `test/` 新文件放进已有目录自动归片；新建顶层测试目录必须登记 `tool/test_shards.dart`（有守卫拦截）。
6. **单测试文件**：`flutter test <路径>`；定向用例：`--plain-name "<用例名>"`。

## 6. 开发记录

| 日期 | WP-任务 | 产出（PR / commit / 文档） | 备注 |
|------|---------|---------------------------|------|
| 2026-09-03 | 全部 | 本文档集落盘 | 分析完成；DR-001/002/003 登记 |
| 2026-09-03 | 全部 | 7 份 WP 文档二次修订 | 任务升级为伪代码级：补现状代码锚点（逐字摘录）、设计说明、实施骨架；WP-1 设计修正为「删 UiStateStore/SliceComposition、SliceStore 收缩保留命令编排」；WP-5/WP-6/WP-7 规模按细化后重估 |
| 2026-09-03 | 全部 | 对照仓库代码 review 并三轮修订 | 修正 11 项：WP-1 攒批理由与装配顺序（无环订阅模式）、补 publish 路径遗漏（threadSnapshot/管线指标/诊断）与 Widget 只读面清单；WP-2 改原地转换（不建 kit）；WP-3 改单层注册表 + 补 warmup hook 与 hidden 类 extent 隐患；WP-4 横幅清单纠错（2 处替换 + 2 处评估）；WP-5 补 overlay/standby 交互；WP-6 修 onTapLink 签名、补 T8 透传与 T1 重命名清单；WP-7 圈定 T2 范围 |
| 2026-09-03 | 全部 | 逐字终审并四轮修订 | 修正 15 项：WP-1 D2/D3 与骨架矛盾（effect 流归属、live 旁路时点）、补 `_effectController` 字段与 registry 接线（复用现有 sliceStoreRegistry）；WP-2 DoD grep 命令修复；WP-3 render context 拆分稳定/逐项参数（原设计会冻结 pendingState）、注册清单计数 10→9；WP-4 T1 与 WP-7 T2 循环引用解除（alpha 内建 zeta_ui）；WP-5 T3 刷新通道修正（TimelineStore 不发 UiUpdateRequest）+ G1 自查；WP-6 目录计数、pubspec 模板对齐 zeta_ui、import 计数 4→5、T8 工具栏补状态持有；全部 WP 的「登记 §5」统一改 §6 |
| 2026-09-03 | WP-1 T0 / WP-7 T3 | `feature/wp7-t3-scheduler-metric-label` | scheduler 指标标签改为构造注入；presentation 不再 import `zeta_agent_providers`；ViewModel 透传已有 `providerMetricLabel`；组合层绑定不变 |
| 2026-09-03 | WP-1 T2 | RuntimeController 下沉；删除 UiStateStore/SliceComposition | scheduler 进 application；SliceStore.connected 直接吃 UiUpdateRequest；ViewModel 成 Flutter 门面；因删除 Dart 文件 `test_affected` 走全量并绿 |
| 2026-09-03 | WP-1 T3 | 纯函数下沉：selection patch / skill 候选 / flatten 文件节点 | RuntimeController 改委托；三组表驱动单测 |
| 2026-09-03 | WP-1 T4 | Composer 图片附件 IO 下沉到 data 端口 | AgentPane 去掉 dart:io；生产写临时目录、测试走内存 fake |
| 2026-09-03 | WP-1 T5 | 删除 Conversation ViewModel；命令面改走 RuntimeController | Slice registry 解析 SessionHandle；AgentPane 持 RuntimeController；上下文面板显隐留在 Pane State |

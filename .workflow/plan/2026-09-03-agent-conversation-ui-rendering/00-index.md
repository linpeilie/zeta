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
| WP-1 | 切片 owner 归位 + ViewModel 拆分 | 10–14 | 独立，建议 WP-2 之后降低冲突 | G3 G6，一份状态一个 owner | 已完成 | [01-wp1-slice-ownership.md](01-wp1-slice-ownership.md) |
| WP-2 | part-of 单体 library 拆分 | 2–3 | 无（WP-3/WP-4 的地基） | G6 | 已完成 | [02-wp2-part-of-split.md](02-wp2-part-of-split.md) |
| WP-3 | 渲染分发插件化（renderer 注册表） | 3–4 | WP-2 | G1 G4（registry 保持中立） | 已完成 | [03-wp3-renderer-registry.md](03-wp3-renderer-registry.md) |
| WP-4 | 控件收敛下沉 zeta_ui | 4–5 | WP-2（可穿插） | G8；zeta_ui 纯度 | 已完成 | [04-wp4-zeta-ui-convergence.md](04-wp4-zeta-ui-convergence.md) |
| WP-5 | 历史分页 / 窗口化 | 5–8（含 spike） | 需先 spike；WP-1 之后 | G2 G3 G6 | 未开始 | [05-wp5-history-pagination.md](05-wp5-history-pagination.md) |
| WP-6 | **Markdown vendor + 深度改造** | 11–16（T1–T10 + 治理；P2 另计） | 无 | G6 G7 G8；包治理 | 进行中 | [06-wp6-markdown-vendor.md](06-wp6-markdown-vendor.md) |
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
| 2026-09-03 | WP-1 T6 | 全量门禁与文档同步 | overview(+en) 两跳发布图；工程规范 §3.0；developer_guide 切片接入；glossary region/slice；`test_full` 根包 2459 全绿；WP-1 已完成 |
| 2026-09-03 | WP-2 T1 | 共享符号盘点 | 15 part + 壳：217 个顶层 `_` 符号，75 个去下划线、142 个保持私有；T2 决议二分 styles/text；纠正 cards 非叶、T5 必须先于 T4 cards |
| 2026-09-03 | WP-2 T2 | styles 原地转独立 library + 文案二分 | `agent_pane_styles.dart` / `agent_pane_text.dart`；壳 import、part 调用去下划线；header 局部变量避同名；analyze 绿，`test_affected` 57 个根测试绿 |
| 2026-09-03 | WP-2 T3 | markdown 组件独立 | `widgets/agent_markdown_body.dart`；保留现状构造函数与右键/光标 hack；壳去掉 mixin_markdown import；analyze 绿，`test_affected` 53 个根测试绿 |
| 2026-09-03 | WP-2 T5 | 转换 L4 composer 族 | popover / model_config / mode_selector / 三个 picker / composer 独立 library；mode_selector 测试改 import；analyze 绿，`test_affected` 53 个根测试绿 |
| 2026-09-03 | WP-2 T4 | 转换 L2–L3 文件 | header / rail / cards / messages / context / sections / plan_panel 独立 library；presentation 已无 part；AgentBuildTarget runtimeType 同步；analyze 绿，`test_affected` 53 个根测试绿 |
| 2026-09-03 | WP-2 T6 | 壳收缩与全量门禁 | Composer 交互抽到 session，对话树抽到 body；`agent_pane.dart` 329 行；`test_full` 绿；WP-2 已完成 |
| 2026-09-03 | WP-3 T1 | renderer 契约 + 单层注册表落地 | `timeline_rendering/` 新目录两文件；注册表单测 3 条绿；对照代码修正文档 5 处设计（kindOf 取代常量 kind、build 补 BuildContext、context 持 controller、重复注册抛 ArgumentError、默认实现下沉 Base 类） |
| 2026-09-03 | WP-3 T2 | 9 个 renderer 迁移 + 默认注册清单 | extent 算式提取共享文件（工厂同步改调用，数值零变化）；计划审批卡装配下沉复用；对齐测试以现役工厂为基线 11 条绿；核实 permission/question 到达视口 → 估算 48px vs 实测 0px，renderer 已登记 hidden，接线后生效 |
| 2026-09-03 | WP-3 T3 | 收敛 switch + extent 工厂接线 + 导航谓词 | sections 两处 switch 与保温判断链归零（净减 130 行）；extent 工厂 585→255 行，八个私有估算/指纹方法删除；工厂改为显式注入 registry；导航兜底锚点跳过零高度块；架构守卫 4 条（源码盘点密封子类双向比对）。过渡 re-export 被零容忍守卫拦下，改为迁符号 + 直接 import 真源 |
| 2026-09-03 | WP-3 T4 | 注入接线与全量门禁 | AgentPane 持 registry 与 renderContext（换会话时重建）；timeline/body 两个缓存参数合并；`test_full` 绿；WP-3 已完成。接线后 permission/question 由 48px 估算改为 0，虚拟化少一份系统性偏差 |
| 2026-09-03 | WP-4 T1 | `IdeStatusCard` compact 变体 + 模型配置横幅收敛 | compact 默认 30px 下限、零外边距、Graphite tone 与 `IdeIconBox`；两处横幅保留原 key；模型禁用尾图标和模式列表警示因结构不同保留 |
| 2026-09-03 | WP-4 T2 | `IdePopupSelect` + 通用 popover 生命周期收敛 | session config 使用通用选择器；mode/permission/model 与三个 picker 复用 `IdePopoverController`；旧 Composer selector helper 删除；异步字体搜索因语义不等价保留 |
| 2026-09-03 | WP-4 T3 | `IdeTimelineRow` + 时间线摘要行收敛 | 命令组（含历史 search/system）、独立 tool 与 diff 标题改用自然高度原语；多行 history status card 保留；既有 key 不变 |
| 2026-09-03 | WP-4 T4 | `AgentTimelineGroupCard` 折叠组骨架收敛 | command/file-edit 共用 key、摘要、图标、间距和 hover 组装；slice 与 Widget 两类展开状态 owner 保持独立 |
| 2026-09-03 | WP-4 T5 | `IdeSubmitButton` + WP-4 收尾 | Composer 发送/停止/禁用态统一下沉；双层 key 与交互保持；feature `sf.IconButton.ghost` 10→9；WP-4 已完成 |
| 2026-09-03 | WP-6 T1 | `packages/zeta_markdown` fork 落地 | 31 个 lib 文件 + 1 个测试随迁，包内 180 条测试全绿。对照发布产物修正文档 5 处：依赖实为 pretext/flutter_math_fork（无 flutter_highlight/meta）、测试只有 1 个文件、新建包级 analysis_options 关三条风格 lint、example/benchmark/上游 AGENTS.md 不迁入、SDK 下限跟上游 ^3.5.0（用户决策：保住与上游逐字节一致，31 个文件仅 7 个有登记在案的差异）。顺带修上游 Windows 盘符被当成 URI scheme 导致本地图片全部加载失败的缺陷 |
| 2026-09-03 | WP-6 T2 | 根应用换到 zeta_markdown | 依赖与 3 个 lib + 2 个测试的 import 全部切换，`grep mixin_markdown` 零命中；lock 只少一个 hosted 条目。文档 §0.3 使用点清单已过期（descriptor 文件不存在、plan_panel 无该 import、messages 已被 WP-2 抽成 agent_markdown_body），已回写 |
| 2026-09-03 | WP-6 T3 | 测试基线 | 包内 184 条全绿零剔除；核实上游 tag 后确认「12 个测试文件」不存在（上游本来就只有 1 个，lib 与 tag 逐字节一致），UPSTREAM.md 的缺口条目改为核实结论；`test_packages.sh` 自动发现 + CI packages job 覆盖 + `--enforce-lockfile` 均已实测；确立本地用例放 `test/zeta_*.dart` 的约定并落地 Windows 盘符回归测试 |
| 2026-09-03 | WP-6 T4 | 外链交给系统浏览器 | SystemUrlOpener + fail-closed provider + 测试组合根记录型 fake；白名单只放 http(s) 且要求 host 非空；ui/core 守卫白名单加一条。关键坑：onTapLink 传每帧新建的闭包会让 view 每次 didUpdateWidget 清空 block 行缓存并炸布局断言（toolbar 一档 12 条），改成 State 绑定方法后 vendor 零改动解决 |
| 2026-09-03 | WP-6 T5 | 语法集注入点 | 包内 parser/controller/嵌套片段三处注入 + barrel 导出；默认行为零变化（包内 186 条绿）。文档 2 处修正：第二处 md.Document 在 const 语法类的实例方法里（改惰性绑定 + 按集合缓存，否则 details 内外两套语法），controller 默认路径仍可复用 const parser。Zeta 侧只接线不裁剪——增删哪些语法是产品决定 |
| 2026-09-03 | WP-6 T6 | 代码高亮 Graphite 调色板 | 包内 9 槽位调色板（带 lerp 与值语义 ==，后者是硬要求：引用相等会让 view 每帧清行缓存并撞 T4 那个断言）+ 主题五处逐字段同步；`_tokenStyle` 改「槽位 ?? 推导」。文档 2 处修正：上游 type 与 meta 共用推导色（拆两槽默认不变）、推导起点必须与 keyword 生效色分开否则改一个漂四个。Zeta 侧映射全部走 token，色相搭配待设计走查；flutter_highlight 那套（工具卡/diff）保留不动 |
| 2026-09-03 | WP-6 T7 | markdown 估算契约守卫 | 文档点名的 descriptor 文件不存在，守卫改盯 WP-3 的 `estimateAgentMarkdownExtent`；「偏差<20%」与实测不符（现状高估 30%~70%），且纯比值带拦不住 T8 的工具栏，故做成「真实高度基线 ±6% + 不对称比值带 0.95~2.2」两层。已变异验证：代码块 +28px 只让 code 那条红 |
| 2026-09-03 | WP-6 T8 | 代码块工具栏注入点 | 包内三态 builder（不注入=默认按钮/返回 widget=替换/返回 null=不渲染）+ 补齐 language/lineCount 透传；Zeta 侧语言标签+行数+1.5s 对勾反馈，复用既有 l10n 键。文档预期的「T7 守卫先红」未发生：工具栏与代码同处一行不增高，那句预期隐含了工具栏另起一行的形态。守卫脚手架换成 ShadcnApp 外壳（IdeIconButton 需要 shadcn 主题祖先，缺 l10n delegates 会量到错误组件的 10 万 px） |
| 2026-09-03 | WP-6 T9 | 右键菜单开关 + 文案注入 | 包内 enableContextMenu 早退 + MarkdownContextMenuLabels（默认英文不变）；Zeta 删掉空组件抑制 hack，改为过滤 selectAll 后交平台工具栏渲染，ARB 补两键。连带更新两处特征化旧 hack 的断言。踩坑：正文 build 现在读 l10n（脚手架缺 delegates 会渲染错误组件）、useColumn 下右键要点首行文字而非 getCenter |
| 2026-09-03 | WP-6 T10 | 正文光标修复 | 包内按文本块声明 I-Beam 缺省（可选中才给），链接 click 仍在更内层优先；应用侧两处 MouseRegion 补丁删除。没走 span 缺省那条路——那有 9 处构造点。补一条「单段正文只有一个文本光标区域」防补丁复活。WP-6 的 P0/P1 至此全部落地 |

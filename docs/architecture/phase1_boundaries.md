# 阶段 1：建立边界但不改变行为

最后更新：2026-08-22

状态：第二个增量（`zeta_ui`）已落地，review 提出的 8 条问题已全部修复。对应 [目标架构 §14 Phase 1](./target_architecture_riverpod_mvi_plugins_packages.md#phase-1建立边界但不改变行为)。

阶段 1 的规矩是**只搬边界，不动行为**：没有新功能、没有 UI 变化、没有持久化格式变化，
Provider wire 参数与状态 owner 全部保持原样。

---

## 1. 本增量交付了什么

| 交付物 | 位置 |
| --- | --- |
| Pub workspace | 根 [`pubspec.yaml`](../../pubspec.yaml) 的 `workspace:` 列表 |
| `zeta_foundation`（纯 Dart 公共契约） | [`packages/zeta_foundation`](../../packages/zeta_foundation) |
| `zeta_plugin_kernel`（可信插件微内核） | [`packages/zeta_plugin_kernel`](../../packages/zeta_plugin_kernel) |
| 编译期插件目录 | [`lib/src/app/plugins/zeta_plugin_catalog.dart`](../../lib/src/app/plugins/zeta_plugin_catalog.dart) |
| Agent Provider 贡献 + 兼容插件 | `lib/src/features/agent/data/agent_provider_plugin_contribution.dart`、`compatibility_agent_provider_plugin.dart` |
| 应用级依赖 Provider / 覆盖点 | [`lib/src/app/composition/app_dependencies.dart`](../../lib/src/app/composition/app_dependencies.dart) |
| Package 依赖图守卫（含跨包 `/src` 禁令） | `test/src/architecture/package_boundary_candidate_graph_test.dart` |
| Package 独立测试入口 | [`tool/test_packages.sh`](../../tool/test_packages.sh)（已接入 `tool/test_full.sh` / `.ps1`） |
| `zeta_ui`（Graphite 设计系统） | [`packages/zeta_ui`](../../packages/zeta_ui) |
| 设计系统文案注入端口 | `packages/zeta_ui/lib/src/zeta_ui_text_catalog.dart` + `AppZetaUiTextCatalog` 适配器 |

### 1.1 已物理拆出的 Package

```text
packages/
  zeta_foundation/        # 纯 Dart：Clock、OperationId、Transition、排版常量、指标端口
  zeta_plugin_kernel/     # 纯 Dart：descriptor / contribution / registry / 生命周期
  zeta_ui/                # Flutter：Graphite token、Ide* 控件、Workbench 骨架、虚拟滚动
```

依赖方向（守卫强制）：

```text
zeta_plugin_kernel ──> zeta_foundation
zeta_ui ───────────> zeta_foundation
root app ──────────> 三者
```

`zeta_foundation` 不 import 任何外部库（连 Flutter 都没有）；`zeta_plugin_kernel` 只依赖
`zeta_foundation`，且源码里不允许出现 `codex` / `grok` / `claude` / `Agent` / `package:zeta/`
任一标识——内核认识"插件"，不认识"Agent Provider"。

`zeta_ui` 依赖 Flutter / shadcn_flutter / flutter_svg / window_manager，但守卫禁止它出现
`dart:io`、`flutter_riverpod`、`package:zeta/` 与 generated l10n：

- **文案**：控件自有文案（无障碍标签、滚动条提示、Tab 加载后缀等 8 条）改走注入的
  `ZetaUiTextCatalog`。宿主用 `AppZetaUiTextCatalog` 把 ARB 投影进去，未注入时回退英文，
  保证设计系统可以脱离宿主独立渲染与测试。
- **本机 IO**：`ide_image_preview.dart`（读本地图片并预览）**留在 app 侧**
  `lib/src/ui/core/`——它本质是宿主能力封装，不是设计系统原语。公开 API
  （`IdeLocalImageThumbnail` / `showIdeLocalImagePreview`）与行为一字未改。
- 47 个设计系统文件整体 `git mv` 进包，372 处 `package:zeta/src/ui/core/...` import
  统一改成 `package:zeta_ui/zeta_ui.dart` 顶层 barrel。

### 1.2 插件微内核

内核只做四件事：登记、按拓扑序激活、按类型汇总贡献、按反序关闭。全部边界 fail-closed：

| 情况 | 行为 |
| --- | --- |
| 插件 ID 重复 | 构造即抛（编译期目录写错了，不拖到运行期） |
| API 主版本不符 | 该插件 `failed`，其余照常激活 |
| 依赖缺失 / 依赖失败 | 该插件 `failed`，分类分别为 `missingDependency` / `dependencyFailed` |
| 依赖成环 | 环上插件 `dependencyCycle`，环外依赖者 `dependencyFailed`，都不进激活序列 |
| `activate` 抛异常 | 只记分类，不记异常文本（G7） |
| 核心必需插件失败 | 报告 `isDegraded = true`，应用必须显式进入 degraded 状态 |

### 1.3 兼容层账本

| 项目 | 内容 |
| --- | --- |
| 兼容层 | `CompatibilityAgentProviderPlugin` |
| owner | 架构迁移（Phase 1 引入） |
| 使用点计数 | **1**（只允许由 `ZetaPluginCatalog.compatibility` 构造，测试断言） |
| 删除 Phase | Phase 3 第 6 批：Codex / Grok / Claude Code 拆成三个显式插件贡献后删除 |
| 回滚方式 | app 组合点改回 `_agentProviderFactory = DefaultAgentProviderFactory(...)` 直连，一行 |

`DefaultAgentProviderFactory` 内部按 kind 分派的 switch **一字未动**——本阶段只是把
"谁交出工厂"从 app 直接构造改成了从插件目录取。

---

## 2. 没有搬的部分（Phase 1 后续增量）

目标 Package 图里还有两个候选包**没有**物理拆出：`zeta_agent_core` 与
`zeta_agent_providers`。这是有意的：目标架构自己写了"一次只迁一个叶子边界"，这两个
候选包目前仍有反向依赖（application → data / presentation），直接搬会把循环依赖搬进编译期。

燃尽清单（守卫里的 `_knownEdgeViolations` / `_knownExternalViolations`，只允许变小）：

| 待修边界 | 数量 | 修法 |
| --- | ---: | --- |
| ~~`ui/core` → generated l10n~~ | ~~5~~ → 0 | ✅ 已改为注入 `ZetaUiTextCatalog` |
| ~~`ui/core` → `dart:io`~~ | ~~1~~ → 0 | ✅ 图片预览封装留在 app 侧 |
| agent `application` → agent `data` | 3 | 改为 app 注入端口（turn context store、静态能力） |
| agent `application` → presentation / workspace feature | 2 | Phase 2/3 拆解 `IdeShellController` 时处理 |
| `core/` → `dart:io` / Flutter | 8 | IO 部分下沉到 app 或独立适配层，`core/` 只留纯契约 |
| `zeta_agent_core` 候选层依赖 Flutter | 17 个文件 | `ChangeNotifier` 依赖，随 Phase 2/3 的 MVI 切片逐步移除 |

---

## 3. MVI 命名规范（Phase 2 起强制）

阶段 1 只定契约与命名，不建通用基类框架。每个 feature 切片按下面这套命名：

| 概念 | 命名 | 说明 |
| --- | --- | --- |
| 意图 | `<Feature>Intent`，变体用**发生的事**命名 | `SendMessageRequested`、`ThreadSelected`、`ModelCatalogLoaded`；不要用 `SetXxx` 这种命令式 setter 名 |
| 状态 | `<Feature>State` | 该 bounded context 的完整可渲染状态，不可变 |
| 转移 | `Transition<State, Effect>`（来自 `zeta_foundation`） | reducer 签名固定为 `Transition<S, E> reduce(S state, I intent)`，**纯同步** |
| 副作用 | `<Feature>Effect` | 只是**描述**，由 scope-aware runner 执行 |
| 结果意图 | `<Something>Succeeded` / `<Something>Failed` | effect 完成只能通过 result intent 回写状态 |
| 操作身份 | `OperationId`（来自 `zeta_foundation`） | 每个异步操作一个 id；迟到结果先比对 id 再决定是否写回 |
| 选择器 | `<Feature>Selectors` | 从切片派生不可变 UI 投影 |

`Transition` 是切片之间**唯一**共享的结构：不提供 `BaseStore` / `BaseReducer`。审批、提问、
Plan、文件树、设置的领域类型差异很大，强行统一只会造出一层空壳。

`Failure` 分类、`CancellationToken` 与 `Result` 留到 Phase 2 与**第一个真实调用方**一起落地——
先建无人使用的抽象违背目标架构 §1.1 第 8 条。

---

## 4. 命令

```sh
flutter analyze          # 根 Package
bash tool/test_packages.sh   # 每个内部 Package 的 analyze + test（Flutter 包自动走 flutter 工具链）
bash tool/test_full.sh       # 根测试 + 计时报告 + 上面这一步
```

Windows 用 `tool/test_full.ps1`（同样包含 Package 循环）。

---

## 5. 与阶段 0 基线的对比

| 指标 | 阶段 0 | 本增量 |
| --- | ---: | ---: |
| 根测试 | 2114 passed / 0 failed | 2122 passed / 0 failed |
| Package 测试 | — | 47 passed（foundation 23 + kernel 20 + ui 4） |
| 聚合测试耗时 | 248.4s | 244.0s（同机波动范围内） |
| `flutter analyze` | 0 issue | 0 issue |
| 流式 fixture 基线 | received 10 825 / accepted 309 / coalesced 10 516 / dispatched 309 | 未变（同一断言通过） |
| Widget 重建预算 | Shell 骨架各 1 次 | 未变 |

---

## 6. 与计划的偏差

1. **内核增加了同步激活入口**。目标架构 §5.2 只写了 `Future<ZetaPluginHandle> activate()`。
   首帧就需要 Agent Provider 工厂，纯异步激活会引入一个"还没有工厂"的中间态，
   属于行为变化。因此增加 `ZetaSynchronousPluginFactory` 与 `activateAllSynchronously()`：
   只支持异步的插件在同步入口上 **fail-closed**，不会被静默跳过。异步入口原样保留。
2. **移动的文件一律不保留旧路径兼容 barrel**。计划的回滚手段是"保留原路径 barrel"。
   两个增量都没有这么做：第一个增量只移动 3 个文件（15 处调用点），`zeta_ui` 增量是
   47 个文件、372 处调用点，都选择直接改写 import——改写是一次脚本化操作，`flutter analyze` 与 2116 个
   测试立刻验证；保留 47 个 shim 反而要再加一条守卫防止新代码继续引用旧路径，且全部
   要在 Phase 4 删除。两次的回滚方式都是 revert 单个提交。
3. **`Failure` / `Result` / `CancellationToken` 未落地**，理由见 §3。
4. **`zeta_ui` 的 36 个 Widget 测试留在根测试树**（通过 `package:zeta_ui/...` 引用），
   因为它们依赖应用侧的本地化宿主与主题 harness。包内另有独立的契约测试入口
   （文案注入 + token 解析）。把这批 Widget 测试迁进包内是后续增量。

---

## 7. 验收对照

| Phase 1 验收标准 | 状态 |
| --- | --- |
| 行为、状态 owner、Provider lifecycle、持久化格式零变化 | ✅ 全量测试与流式基线未变；工厂内部分派逻辑未动 |
| 根 app 仍是唯一装配点；kernel 不 import 具体 Provider | ✅ 守卫测试强制 |
| 禁止跨 `/src` import 与反向依赖 | ✅ 守卫测试强制（已拆包 + 候选包两套规则） |
| analyze / test / 构建通过，基线无退化 | ✅ 见 §5；三桌面平台构建**待执行**（见下） |
| compatibility layer 有使用点计数、owner 和删除计划 | ✅ 见 §1.3，测试断言使用点为 1 |

**待执行**：三桌面平台（macOS / Windows / Linux）的实际构建验证。workspace 只影响依赖解析，
不改 Flutter 构建配置，但按 `AGENTS.md` 的规矩，没有跑过就不能推断通过。

---

## 8. Review 修复记录

第二个增量的 review 提出 8 条问题，全部已修复并补了回归测试。

| 问题 | 修复 |
| --- | --- |
| **P1** 异步激活与 `close()` 竞态导致句柄永久泄漏 | `close()` 先 `await` 在途激活；激活循环每步重新检查 `_closed`；迟到句柄在 `_adoptHandle` 里就地释放并登记进 `_lateHandleCloses`，`close()` 等它们收尾；已关闭的 registry 的 `contributions()` 返回空 |
| **P2** 重复激活覆盖旧句柄、贡献翻倍 | 一个 registry 只能激活一次，两个入口都 fail-closed 抛 `StateError`；换代请重建 registry。原先把该行为当预期的测试已改写 |
| **P2** 标签"脱敏"仍留下可读路径 | 标签改为白名单：只接受 `^[A-Za-z][A-Za-z0-9_.-]{0,31}$`，其余**整体丢弃**而不是替换字符；观察器给未命名 provider 去掉泛型参数以保持合法 |
| **P2** CI 没有门禁到 Package 测试 | CI 的 Test 步骤改跑 `bash tool/test_full.sh`；`test_full.ps1` 的 Package 循环补上 analyze，与 shell 版对齐 |
| **P2** 退出顺序没有保证 runtime → plugin | 抽出可测的 `shutdownAgentResourcesInOrder`；窗口关闭 hook 与 `dispose` 共用同一入口，严格串行 |
| **P2** 设计系统文案未全部注入 | `ZetaUiTextCatalog` 补 `loading` / `running` / 四个窗口按钮文案，ARB 与适配器同步；窗口按钮补 `Semantics(button: true)`；新增守卫禁止包内出现字面量 tooltip / 无障碍标签 |
| **P2** `zeta_ui` 隐式依赖根 app 资产 | `WindowFrame` 改为接受注入的 `brandLogo`，包不再依赖 `flutter_svg`、不再读 `assets/branding/*`；包 pubspec 补 `uses-material-design: true`，消除 Material Icons 警告 |
| **P1** 分支门禁与文档口径不一致 | 根因是 `ide_session_restore_widget_test` 有一处 `MainApp` 没注入 fake 工厂，会真的拉起本机 Codex CLI 并留下 30 秒 JSON-RPC Timer（机器越快越不容易复现）。已注入 fake，并加守卫 `widget_test_hygiene_guard_test.dart` 断言测试里构造 `MainApp` 必须显式传 `agentProviderFactory` |

修复前 review 报告里"9 处裸 `MainApp` pump"是扫描口径问题（正则窗口没有做括号配对，把
`_pumpMainApp(` 和相邻用例一起算了进去）。**实际只有 1 处**。

### 第二轮 review 修复

| 问题 | 修复 |
| --- | --- |
| **P1** 并发 `close()` 提前返回，调用方误以为资源已释放 | 改成 `AgentProviderRuntimeRegistry` 同款 `_closeFuture`：并发调用返回同一个关闭任务；补"两个并发 close 都等到句柄真正释放"的回归测试 |
| **P2** 贡献 getter 抛异常会污染 registry，一个坏插件阻断整个 catalog | 激活时**先冻结贡献快照再原子登记**；快照失败即 `failed` + 就地关闭句柄，不进任何表。`contributions()` 改读快照，不再回调插件 getter（顺带变成无副作用纯读） |
| **P1** 指标标签只校验形态，判断不了来源 | 标签类型化为 `ZetaMetricLabel`（`constant` / `declaredIdentifier` / `hashed` 三个入口），`ZetaMetricTags` 不再接受 `String`；Provider ID 经 `AgentMetricLabels.forProviderId` 映射（内置→常量，其余→会话 hash）；新增守卫强制 `constant` 实参为字面量 |
| **P3** Widget 测试守卫能被注释绕过 | 改用 `package:analyzer` 的 AST：注释与字符串天然不参与判定；同时统计扫描到的构造点数量，防止守卫空转。守卫自带"注释伪装"回归用例，并做过一次变异验证（去掉真实注入后确实报错） |

新增 dev 依赖：`analyzer ^12.1.0`（此前是 transitive），仅用于架构守卫的 AST 解析。

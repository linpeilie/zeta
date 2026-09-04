# WP-E · 治理：守卫、门禁文本、文档同步与收尾

> 状态：未开始
> 规模：约 1 人天
> 依赖：WP-D 完成
> 性质：加固与文档。守卫是「新增 Provider 只加一个包」这句话的长期保证——没有守卫，架构会在半年后悄悄漂移回去。

## 1. 背景

WP-A~D 完成后，目标态的约束目前只存在于文档里。本 WP 把它们变成会失败的测试和会拦人的门禁文本，并整组同步文档（本计划动到包结构与 G1/G6 文本，按 `AGENTS.md` §6 必须整组走）。

## 2. 任务

### T1 · 架构守卫测试

全部放 `test/src/architecture/`（已有目录，自动归片）或 `test/src/app/plugins/`，逐条落地：

1. **manifest 一致性守卫**（`test/src/app/plugins/agent_provider_manifest_test.dart`）：
   - `zetaAgentProviderDefinitions` 与 `zetaAgentProviderPluginFactories()` 激活产出的 definitions **双向**核对（id/type 逐一对齐，顺序一致）；
   - `zetaAgentProviderDefinitionCatalog` 构造不抛（id/type 唯一、默认项唯一——这条白捡自 catalog 的 fail-closed）；
   - 每个 definition 的 `metricLabel` 是 `ZetaMetricLabel.constant`（内置插件不许回落 hashed）。
2. **包隔离守卫**（`test/src/architecture/provider_package_isolation_guard_test.dart`）：扫描文件系统断言 import 边界——
   - `packages/zeta_agent_provider_*/lib/**` 不得 import 其他 `zeta_agent_provider_*` 包；插件包不得 import Riverpod / `package:flutter/`（纯 Dart，`dart:io` 允许——CLI 进程与文件探测是插件的本职）；
   - `packages/zeta_agent_provider_api/lib/**` 不得 import sdk / 插件包 / Riverpod / Flutter / `dart:io`；
   - `packages/zeta_agent_provider_sdk/lib/**` 不得 import 插件包（testing 子库除外，它允许 import api/kernel 以构造测试上下文）；sdk 允许 `dart:io`（`cli_process_runner` 在 WP-B T5 迁入）但禁 `package:flutter/`；sdk 机制文件（不含 testing）grep `codex|grok|claude` 应零命中（注释除外）；
   - `lib/**` 与 `test/**` 中 import `zeta_agent_provider_{codex,grok,claude_code}` 的文件**只有** `lib/src/app/plugins/agent_provider_manifest.dart`（根测试的 fixture 统一经 manifest，见 WP-C §5.1）。**启用前置**：本条断言在 WP-D 收尾才成立——WP-C/WP-D 过渡期存在 §2 登记白名单（含 runner，实测 6 组文件），启用前先确认 WP-D DoD 的「白名单清零」项已勾；
   - `lib/**` 除 manifest 外不得出现三个 ProviderTypeId 字符串字面量（`'codexAppServer'` / `'acp'` / `'claudeCode'`）——防有人绕过包 import 直接写字面量重建厂商分支。
3. **D7 持久化身份红线守卫**（并入 manifest 守卫文件）：
   - 从 manifest definitions 断言字符串逐字节：三个 `providerType.value`、三个 `providerId`、`claudeCodeAccountDataEnrichmentExtraKey == 'claudeCode.accountDataEnrichment'`、`AgentProviderSettings.currentVersion` 未变；
   - `git diff` 断言（CI 脚本或评审清单项）：`agent_provider_config_codec.dart`、`agent_provider_config_store.dart`、usage 索引根版本常量在本计划全周期无 diff。
4. **贡献完备性守卫**（manifest 守卫文件内）：三个**内置**插件的贡献快照必须同时含 `AgentProviderPluginContribution` / `AgentManagementContribution` / `AgentUsageContribution` 三类，且 contribution 的 `providerId`/`providerType` 与 definition 一致——缺类即失败（防漏挂贡献导致功能静默缺失）。未来新插件只强制 bundle 贡献，management/usage 按其能力可选（`createFor` 返回 null 即 unsupported 语义）。**生效时点**：management/usage 贡献在 WP-D T2/T4 才挂上插件类，本守卫随 WP-D 收尾启用，不要提前到 WP-C。**附加 parity 断言**：`test/src/testing/agent_management_test_definitions.dart` 的测试字面量与对应贡献的 `definition` 逐字段一致（WP-D T0-5 引入的防漂移钩）。
5. **C6 登记例外守卫**：两道 grep——① 全仓 `AgentDefinition.claudeCode` 零命中（静态表已在 WP-D T0 删除，任何命中都是重建静态目录）；② `lib/src/features/**/presentation/**` 内 `'claude_code'` 字符串字面量只允许 `agent_management_page.dart` 的 `_setupGuideAgentId` 一处（断言精确到文件+命中数；664 分支已改经 `requiresConnectionTestConfirmation` 能力位，不再是厂商分支）。新增命中即失败并提示「先泛化或回 WP-D 登记」。
6. **G1 纯度守卫路径更新**：`agent_core` 既有纯度守卫与自查脚本里 `packages/zeta_agent_providers/lib/src/mappers/acp_*.dart` 等路径替换为 sdk 对应路径；检查 `feature_layering_guard_test` 与包边界守卫里所有 `zeta_agent_providers` 引用，按新包结构重写断言（不是删除——守卫强度不许降）。**实测点名的三处字符串引用守卫**（搬迁后字符串不失效、守卫静默漏检，必须逐条核对）：
   - `agent_core_raw_payload_freeze_test.dart:133/154`：以字符串引用 `mappers/agent_provider_payload.dart` 路径 → 更新为 sdk 路径；
   - `agent_provider_catalog_freeze_test.dart:47`：以字符串引用 `claudeCodeAccountDataEnrichmentKey` → WP-D T5 后该 key 只剩 claude 包内定义 + definition 声明两处，守卫改经 manifest definition 的 `accountDataEnrichmentExtraKey` 字段断言；
   - `agent_provider_bundle_contract_test.dart:45-47`：以字符串引用三个 type 常量名 → 改经 manifest definitions 断言（与守卫 1 合并亦可）。
7. **假插件 e2e 的 import 约束固化**：确认 WP-D T6 测试文件不含真实插件包 import（可直接在本守卫里加一条针对该测试文件的断言，防未来改坏）。

### T2 · 门禁与文档整组同步（`AGENTS.md` §6 清单）

| 文件 | 改动要点 |
|---|---|
| `AGENTS.md` | G1 范围清单与自查命令的路径（providers→sdk）；G6 包清单与依赖方向段落重写（五包结构 + manifest 唯一厂商认识点 + **application/domain/presentation 允许 import `zeta_agent_provider_api`** 这一新增合法依赖——api 与 core 同为中立契约层）；§2 路由表「接入新 Provider」行改写；§5 事实清单补「Provider 插件包列表与 manifest 位置」；G8 等其他门禁不动 |
| `docs/zh/architecture/engineering_standards.md` | §4.2 共享适配层纯度范围改指 sdk；新增「插件包边界」小节（隔离规则、三类贡献类型清单、fail-closed 约定、文案目录下沉的 `AgentUiTextCatalog` 先例模式） |
| `docs/zh/architecture/overview.md` + `overview.en.md` | Provider 能力协商/插件章节更新包图与注册流程 |
| `docs/zh/development/developer_guide.md` | §7「接入新 Provider」十二步改写为「新建插件包」流程：建包 → 实现端口与 definition → 声明三类贡献（bundle-factory / management-repository / token-usage-source）→ `runAgentProviderContractTests` 一行接入 → pubspec + manifest 登记 → 守卫确认。旧十二步中仍有效的协议/fixture/冒烟要求保留并挂到新流程对应步骤下 |
| `docs/zh/development/glossary.md` + `glossary.en.md` | 新增词条：`provider_api` / `provider_sdk` / manifest / 贡献类型（bundle-factory / management-repository / token-usage-source）/ D7 持久化身份红线 / D8 文案目录下沉 |
| `CONTRIBUTING.md` + `CONTRIBUTING.en.md` | 架构红线摘要里的包结构与「新增 Provider 改动面」表述 |
| `CLAUDE.md` | 包清单段同步；入口卡片其余不动 |

同步原则：门禁正文只维护一份（`engineering_standards.md`），其余文件写索引不写正文，避免副本漂移。

### T3 · 收尾验证

1. `dart format .` → `flutter analyze` → `bash tool/test_full.sh` 全绿。
2. 分片耗时检查：`bash tool/test_affected.sh --shards` 拿摘要，根树因测试迁出产生的失衡若超过可接受阈值（单片明显长于其他），按 `tool/test_shards.dart` 调整目录归属（只在失衡时做）。
3. 确认 CI 的内部 Package 任务自动覆盖五个新包（api / sdk / 三个插件）；若 CI 配置里包清单是写死的而非自动发现，同步 CI 配置并在本记录注明。
4. Codex 真实 CLI 冒烟按 AGENTS.md 流程执行或标阻塞（WP-C DoD 已要求一次，本 WP 复核记录齐全）。
5. `CHANGELOG.md` `[未发布]`：本计划整体是纯内部重构，默认不写条目；若 WP-D 文案剥离或装配顺序有任何用户可感知影响，补一条 fix 并在此记录原因。

### T4 · 计划归档

1. 回写 `00-index.md`：WP 状态列全部置「已完成」，§8 开发记录补收尾行。
2. 计划目录随代码一起提交（`.workflow/` 入 git，内容已按 G7 脱敏——无 prompt / 路径含用户目录 / 凭证）。

## 3. DoD

- [ ] T1 七类守卫全部就位且各自能被「故意破坏」触发失败（每个守卫写一条反例自证）
- [ ] T2 表格七行全部同步，交叉引用无旧包名残留（全仓 grep `zeta_agent_providers` 零命中，含 docs）
- [ ] `flutter analyze` 干净、`test_full.sh` 全绿
- [ ] 新人按 developer_guide 新流程能在不读其他文档的情况下完成一个 dummy Provider 插件（找一位没参与本计划的人走一遍，或按 WP-D T6 假插件路径自行演练）
- [ ] `00-index.md` 状态与开发记录回写完毕

## 4. 风险

| 风险 | 缓解 |
|---|---|
| 守卫写成「通过现状」而非「约束未来」 | DoD 要求每个守卫带反例自证（故意改坏一次看红） |
| 文档同步漏副本导致双源漂移 | T2 原则：正文一份，其余写索引；评审逐文件对照 §6 清单 |
| 根 test 分片因迁出失衡拖慢 CI | T3-2 显式检查，失衡才动 `test_shards.dart` |

## 5. 开发记录

| 日期 | 内容 |
|---|---|
| 2026-09-04 | 初稿 |
| 2026-09-04 | T1 守卫从 4 类扩到 7 类：包隔离守卫补「test/ 全域禁插件包 import」（WP-C §5.1）与「三个 ProviderTypeId 字面量禁令」；sdk 纯度改为「禁 Flutter、允许 dart:io」（`cli_process_runner` 迁入的实测事实）；新增 D7 持久化身份红线守卫、贡献完备性守卫（三类贡献缺一即失败）、C6 登记例外守卫（精确到文件+命中数）。T2 表补 G6 新增合法依赖（provider_api）与贡献类型登记步骤 |
| 2026-09-04 | 完整勘察报告对账：守卫 6 点名三处字符串引用守卫（`agent_core_raw_payload_freeze_test` 路径字符串、`agent_provider_catalog_freeze_test` key 字符串、`agent_provider_bundle_contract_test` type 名字符串）——搬迁后字符串不失效、会静默漏检；守卫 5 收敛为 `page.dart:451` 一处（664 改经 `requiresConnectionTestConfirmation` 能力位）；守卫 4 附加测试字面量 parity 断言（WP-D T0-5 联动） |
| 2026-09-04 | 终审轮：守卫 5 改双 grep 形态——`AgentDefinition.claudeCode` 在 WP-D T0 后符号本身不存在（旧断言目标会编译失效），改为全仓零命中断言 + presentation 层 `'claude_code'` 字面量唯一命中（`_setupGuideAgentId`）断言；守卫 2 补启用前置（WP-C/WP-D 过渡白名单实测 6 组文件含 runner，WP-D DoD 清零后本守卫才生效） |

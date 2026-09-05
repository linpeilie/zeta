# WP-E 治理与验收记录

日期：2026-09-05。基线：`df539ac3`（WP-D 完成提交）；起始工作区干净。状态：已完成，WP-A～WP-E 归档。

## 1. 交付

本轮只修改测试、测试工具、CI 和文档；生产 `lib/`、内部包、pubspec.lock、dart_test.yaml、pinned schema 无 diff。

| 类别 | 实现与反例 |
|---|---|
| manifest 一致性 | `agent_provider_manifest_test` 比较静态/激活定义的双向顺序、默认 settings、三类贡献所有者；反例覆盖遗漏、增加、重排、重复身份、缺默认项 |
| 包隔离 | `provider_package_isolation_guard_test` 与同一个 AST 判定器扫描真实树/错误样本；覆盖 import/export/条件导入、跨包相对路径、纯 Dart、API 方向、独立 testing 出口、顶层 barrel、manifest 常量出口、未来插件名及 TypeId 字面量 |
| D7 冻结 | 内置三组 id/type、配置版本 2、用量根索引版本 4、增强键和确认能力有真实声明断言；篡改类型、缺内置项的反例会失败 |
| 贡献完备性 | 按激活插件所有者逐一验证 Provider/management/usage，测试定义必须复用原贡献对象；WP-D e2e 保留未激活、essential 失败、缺 usage、重复 management、身份错配及关闭后失败反例 |
| C6 品牌内容 | 安装指引仅允许管理页 const `_setupGuideAgentId`；新厂商业务判断、删除/移动登记都会失败。现有图标资源表的窄例外见下一节 |
| G1 与迁移守卫 | SDK 机制、core 五文件/reduction 的 token 纯度受同一反例检查；raw 包装与唯一渲染出口、bundle 端口、feature 与 DAG 守卫动态纳入未来插件。SDK 纯测试子库可调用原文渲染接口，但生产导入该子库会被隔离守卫拒绝 |
| 贡献接缝 | AST 拒绝组合层直接访问 registry；WP-D 用例验证两消费点空表/重复/错误身份抛错及覆盖后不建插件目录 |
| 假插件 import | 同一包隔离规则限制 e2e 的直接插件 import，并提供向该文件注入未来插件 import 的失败反例；现有第四插件 UI/检测/用量 query 演练通过 |

三处原字符串守卫逐条核对：raw 包装路径已在 SDK，新增 API/SDK/未来插件扫描；catalog 保留禁止私有键渗入 core 的字符串检查，同时新增真实能力键冻结断言；bundle 保留禁止厂商 type 分支的原断言，同时以 manifest 正反例核验真实 definition。既有禁令没有因为符号迁移而删除。

原 DAG 守卫曾允许三个插件相互引用，现改为各插件只能依赖自身及中立包，且动态发现未来包。已有 raw、bundle、feature 断言保留；分片选择器的预期编号随 domain 从 6 迁到 5 而更新。

## 2. 按当前代码修正的计划假设

1. **完整贡献要求一致**：WP-D 已验收的宿主强制每个 Provider 都拥有三类贡献；本轮不采用旧 WP-E 草案“未来插件 management/usage 可缺省”的矛盾表述。不支持的具体功能必须明确拒绝，不能靠缺贡献、空成功绕过装配检查。
2. **测试定义没有副本**：WP-D 直接复用插件 definition；守卫使用对象同一性，避免为 parity 再造一份字面量。
3. **品牌图标资源表是漏记的现存形态**：`agent_provider_icon.dart` 中的 `_agentProviderIconAssets` 用 id 选择 SVG 与原色策略，未知项回退中立图标；不参与能力或协议路由。新守卫只豁免该文件 const Map 的 key，同文件新增厂商判断仍失败。不修改原图标行为。
4. **CI 用动态矩阵**：静态十包矩阵会让新插件还需修改 CI 名单，与“只增加包 + pubspec/manifest 登记”矛盾。`--list-json` 复用本地自动发现，CI 先发现后 `fromJSON` 展开；`--only` 负责逐包执行。无可测试包/非法选择均失败，不把空 job 当通过。
5. **历史留痕**：活动源码、测试、工具、AGENTS/CLAUDE/CONTRIBUTING 和 docs 的旧聚合包路径清零；`.workflow/` 历史清单和验收记录保留旧包名，以便审计迁移。对历史文档的路径示例只更新物理位置，不改原决策。
6. **D7 全周期事实**：从计划实施前 `e49fea0e` 对比，config codec 仅 import 从旧包改为 api，去除 import 后正文相同；config store 全文相同。WP-D 的用量分区类物理下沉导致 Store 文件有结构 diff，根版本与 codec 行为保持，不能声称整个文件全周期零 diff。
7. 本机缺少仓库文中提到的 `.agents/skills`、`.claude/skills`、`.codegraph`，沿实际源码与已有测试执行；不创建索引或工具产物进入仓库。

## 3. CI 与分片测量

WP-D 最后一次完整 JSON 报告经 `report_test_timings.dart` 复核：根 1873 条，failed=0，墙钟 266.76s。下表是报告中 suite 累计耗时（含各 suite overhead），**不是 CI job 墙钟**。

| 分片 | 旧分组累计 | 新分组累计（同一基线报告） |
|---|---:|---:|
| 1 Agent presentation | 122.01s | 122.01s |
| 2 UI | 80.98s | 80.98s |
| 3 其他 feature | 96.17s | 96.17s |
| 4 app-shell | 119.83s | 69.05s |
| 5 agent-data → contracts-data | 10.75s | 88.40s |
| 6 Agent logic → application | 98.64s | 71.77s |

contracts-data 纳入 Agent data/domain/architecture、根 architecture/core/testing 与 test/tool；app 与 application 保持完整目录。覆盖守卫验证每个根测试恰好归属一片，目录存在且六片与 CI 一致。当前实际为 10 个内部包、90 个包测试文件，不沿用旧计划的约 83 个文件估计。

CI workflow 已经 YAML 解析，动态矩阵接线与发现清单有正反例检查。远端 CI 尚未触发，不宣称已取得 Linux runner 的最慢 job 实测；本地完整门禁与以下入口测试证明覆盖及失败传播。

本地逐包执行 CI 同款 `--only` 入口（含 analyze + test，按顺序测量，无并发争用），10 包全绿，共 981 条；最慢包为 Markdown 16.04s。该测量不包含 GitHub checkout/安装依赖的冷启动成本。

| 包 | 本地入口墙钟 | 测试 |
|---|---:|---:|
| `zeta_agent_core` | 1.93s | 7 |
| `zeta_agent_provider_api` | 1.78s | 2 |
| `zeta_agent_provider_claude_code` | 3.99s | 251 |
| `zeta_agent_provider_codex` | 2.97s | 175 |
| `zeta_agent_provider_grok` | 4.87s | 193 |
| `zeta_agent_provider_sdk` | 2.49s | 74 |
| `zeta_foundation` | 6.93s | 32 |
| `zeta_markdown` | 16.04s | 208 |
| `zeta_plugin_kernel` | 1.88s | 23 |
| `zeta_ui` | 9.53s | 16 |

## 4. 验证

| 检查 | 结果 |
|---|---|
| 格式化 | 通过 |
| flutter analyze | 0 issue |
| 架构/manifest/假插件/脚本/选择器定向回归 | 104 条通过；补充 manifest 常量实现对象反例后，隔离守卫 27 条再次通过 |
| Bash 选择入口 | 正确区分 Dart/Flutter、参数透传、单包选择、失败后继续、非法/空选择拒绝、动态新包发现；已修复 macOS Bash 空数组与 nounset 的兼容问题 |
| CI YAML 与矩阵 | 解析通过，动态发现和 --only 接线正反例通过 |
| 受影响门禁 | 通过：根 1912 + 内部包 981，共 2893；CI/分片基础设施变化触发全量。随后新增一条常量实现对象反例，独立完整门禁覆盖最终版本 |
| 独立完整门禁 | 通过：根 1913 + 10 个内部包 981，共 2894 条，退出码 0；包含最终新增出口反例 |
| diff/锁文件/生产边界 | `git diff --check` 通过；lib/packages/lock/schema/dart_test.yaml 无 diff |
| 实际 --only 矩阵 | 10 包全部通过（981 条），各入口退出码 0 |
| shard 5 实际入口 | 363 条通过，退出码 0；JSON reporter 墙钟 40.22s（本地） |

所有工具使用进程级 `DASH__SUPPRESS_ANALYTICS=true` 规避本机统计上报网络崩溃；不修改用户全局配置或测试并发。开发中反例首次暴露的相对路径样本层数、构造表达式 AST 形态、品牌资源表漏记，以及重分片后的旧编号，均修正到对应规则/样本，不改产品代码。

## 5. CLI 证据与归档边界

已复核 [WP-C 验证记录](06-wpc-validation.md) 的 Darwin/x86_64、Codex 0.144.5、stable schema app-server 18/18 通过记录；本轮未改 wire/schema，不重复发起真实会话。额外 experimental Plan 冒烟 18/19 中缺少 `turn/plan/updated` 仍为后续协议核验项，不能宣称通过。其他平台未据此视为已验收。

本计划无新增用户可感知行为，不写 CHANGELOG 条目。本轮新增 40 个测试，完整门禁较 WP-D 的 2854 条增加到 2894 条。最终门禁全部通过，WP-A～WP-E 已归档；不将远端 CI 墙钟或额外 Plan 事件的未核验项隐藏在“全绿”结论中。

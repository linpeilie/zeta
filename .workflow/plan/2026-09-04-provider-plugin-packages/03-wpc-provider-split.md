# WP-C · 三插件拆包 + manifest 落地

> 状态：未开始
> 规模：每个 Provider 约 1–2 人天（Claude 取上限），共 3 个独立 PR + 1 个 manifest PR
> 依赖：WP-B 完成
> 性质：纯搬移。每个 PR 全量绿 + 测试断言零修改（除路径/import）为唯一正确性证据。

## 1. 背景与拆分顺序

WP-B 后 `zeta_agent_providers` 只剩厂商私产。按文件实测（2026-09-04 清点），三包体量：

| 包 | 文件构成 | 合计 |
|---|---|---|
| codex | `datasources/app_server/` 8 + `local_history/codex_*` 2 + `mappers/codex_*` 11 + `codex_cli_locator.dart` + `codex_plugin.dart` | **23** |
| grok | `datasources/acp/` 3（全 `grok_*`）+ `local_history/grok_*` 4 + `mappers/grok_*` 11 + `grok_cli_locator.dart` + `grok_plugin.dart` | **20** |
| claude_code | `datasources/claude_code/` 24（23 个 `claude_code_*` + `stream_json_peer.dart`）+ `mappers/claude_code_*` 4 + `claude_code_cli_locator.dart` + `claude_code_plugin.dart` | **30** |

另有三个跨包文件在 T5 拆除：`native_agent_provider_bundles.dart`（129 行，三个 `nativeBundleFromXxx` + 三个 `createXxxBundle` 按家拆分随迁）、`agent_provider_static_capabilities.dart`（86 行，常量随家迁，类本体删除）、`built_in_agent_provider_plugins.dart`（51 行，由 manifest 取代）。

**Flutter 依赖清除（实测）**：providers 包内仅 3 个文件 import `package:flutter/foundation.dart`——`agent_ignored_message_logger.dart`（WP-B T4 已处理）与两个厂商 adapter（`codex_app_server_agent_provider.dart:6`、`grok_acp_agent_provider.dart:7`，只用 `@visibleForTesting` 注解，实测 L246/251、L236/241）。迁移这两个文件时把 import 换成 `package:meta/meta.dart`（foundation 的该注解本就 re-export 自 meta；providers pubspec 已有 meta 依赖，插件包照常带上）。替换后**三个插件包纯 Dart**（允许 `dart:io`，禁 `package:flutter/`、禁 Riverpod）。这两个一行替换是本 WP 唯二的文件体非 import 改动，PR 描述点名。

拆分顺序 **Codex → Grok → Claude**：

1. Codex 依赖面最小（不依赖 sdk 的 ACP codec），先跑通全流程，沉淀模板。
2. Grok 重度依赖 sdk 的 ACP codec（6 处 import），验证 sdk 边界。
3. Claude 最复杂（三个宿主注入工厂、stream-json 私有 peer、metadata coordinator），放最后。

**每拆完一个 Provider 立刻落地其 manifest 行**（manifest 在 T1 先建好只含 Codex；逐 PR 追加），每步独立可交付。

## 2. 过渡态约定（重要）

WP-C 删除 `zeta_agent_providers` 后、WP-D 完成前，app 层以下文件**临时**直接 import 插件包——已登记的过渡白名单，WP-D 逐一消灭，WP-E 守卫只放行这几个：

| 文件 | 引用的插件包 | WP-D 消灭手段 |
|---|---|---|
| `lib/src/features/agent_management/data/{codex,grok,claude_code}_agent_management_repository.dart` | 对应插件包（locator、历史解析、config codec 等） | WP-D T2 迁入插件 |
| `lib/src/features/agent_management/data/claude_code_auth_status_probe.dart` | claude 插件包 | WP-D T2 迁入插件 |
| `lib/src/features/usage_statistics/data/providers/{codex,grok,claude_code}/**` | 对应插件包（`GrokUpdatesHistoryParser`、`ClaudeCodeSessionHistoryReader` 等） | WP-D T4 迁入插件 |
| `lib/src/app/agent_management_slice/agent_management_slice_composition.dart`、`ide_workbench_composition.dart`（enrichment key 与 repository 注册处） | 各插件包 | WP-D T1/T5 |
| `lib/src/app/agent_management_slice/agent_management_slice_runner.dart`（`:4` import providers barrel，`:217/219` 用 enrichment key，实测） | claude 插件包 | WP-D T5 |

> `cli_process_runner.dart` 不在此列——WP-B T5 已迁 sdk，WP-C 开始前 app 侧就只剩 sdk import。

每个插件包 barrel 只导出两类符号：**manifest 需要的**（插件类 + definition 常量 + 默认配置/类型常量）与**过渡白名单需要的**。其余一律 `src/` 私有；过渡导出在 barrel 里注释分组并标注「WP-D 后移除」。

## 3. 通用拆包流程（每个 Provider 重复）

```
1. 建包：pubspec/analysis_options 对齐兄弟包；根 pubspec workspace 登记
2. 迁移实现文件（§4 清单），import 改写：
   - 契约类型   → package:zeta_agent_provider_api/...
   - 共享机制   → package:zeta_agent_provider_sdk/...
   - core       → package:zeta_agent_core/...（不变）
   - 严禁       → 其他插件包、根 app、Riverpod、package:flutter/（纯 Dart）
3. 插件入口改造：插件类 + definition 常量（含 WP-A 的 metricLabel）+ 静态能力常量迁入
   - AgentProviderStaticCapabilities.<vendor> 常量改为本包顶层 const，类本身在 T5 删除
4. native_agent_provider_bundles.dart 中本 Provider 的组装函数（nativeBundleFromXxx
   及 createXxxBundle 链路）随迁本包 src/；该文件随三家拆完后删除
5. barrel 定稿（见 §2 导出规则）
6. 测试随迁（§5 映射表），契约测试一行接入：
   // packages/zeta_agent_provider_<x>/test/contracts_test.dart
   import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart';
   void main() {
     runAgentProviderContractTests(() => XxxContractFixture());
   }
   （XxxContractFixture 实现 sdk 的 AgentProviderContractFixture，
    createBundle() 走本包 createXxxBundle 的 fake 依赖变体；
    注意走 testing 独立 barrel——主 barrel 不导出套件，见 WP-B §3）
7. 单包验收：flutter test packages/zeta_agent_provider_<x> 全绿
8. 全仓验收：bash tool/test_full.sh 全绿（断言零修改）
```

## 4. 文件迁移清单

### T1 · `zeta_agent_provider_codex`

| 从（zeta_agent_providers） | 到（同相对路径） |
|---|---|
| `lib/codex_plugin.dart`（含 `defaultAgentProviderId = 'codex'`、`codexAgentProviderType = AgentProviderTypeId('codexAppServer')`、`codexAgentProviderDefinition`、`CodexAgentProviderPlugin`） | `lib/` 同名 |
| `lib/src/datasources/app_server/**`（8 个文件） | `lib/src/datasources/app_server/**` |
| `lib/src/datasources/local_history/codex_jsonl_history_parser.dart`、`codex_thread_history_reader.dart` | 同相对路径 |
| `lib/src/mappers/codex_*.dart`（11 个） | `lib/src/mappers/` |
| `lib/src/codex_cli_locator.dart`（注意：L3 import sdk 的 `cli_command_locator.dart`） | `lib/src/` |
| `AgentProviderStaticCapabilities.codexAppServer` 常量 | `lib/src/codex_static_capabilities.dart`（顶层 const） |
| `native_agent_provider_bundles.dart` 的 `nativeBundleFromCodex` + `createCodexBundle` 链路 | `lib/src/` |

barrel 导出：`CodexAgentProviderPlugin`、`codexAgentProviderDefinition`、`codexAgentProviderType`、`defaultCodexAgentProviderConfig`、`defaultAgentProviderId` + 过渡白名单符号。

**D7 红线自查**（每个 PR 必做）：`AgentProviderTypeId('codexAppServer')`、`'codex'`、`defaultCodexAgentProviderConfig` 全部字段值与搬迁前逐字节一致——这些字符串进了 `~/.zeta/config` 持久化与模型目录指纹。

完成后：manifest 建文件（§6，只登记 Codex），app 的 Codex 引用全部换包。

### T2 · `zeta_agent_provider_grok`

| 从 | 到 |
|---|---|
| `lib/grok_plugin.dart`（含 `grokAgentProviderType = AgentProviderTypeId('acp')`） | `lib/` |
| `lib/src/datasources/acp/**`（3 个 `grok_*`，含 `grok_models_cli.dart`） | 同相对路径 |
| `lib/src/datasources/local_history/grok_*.dart`（4 个：chat_history_parser、session_history_reader、updates_history_parser、user_content_parser） | 同相对路径 |
| `lib/src/mappers/grok_*.dart`（11 个） | `lib/src/mappers/` |
| `lib/src/grok_cli_locator.dart` | `lib/src/` |
| `AgentProviderStaticCapabilities.grokAcp` 常量 | 本包顶层 const |
| `nativeBundleFromGrok` + `createGrokBundle` 链路 | `lib/src/` |

注意：`grok_acp_agent_provider.dart` 的 barrel 导出历史上带 `hide JsonRpcPeerFactory`（与 sdk transport 冲突名）——迁移后 sdk 已是独立 barrel，检查该 hide 是否仍必要，不需要就删。

### T3 · `zeta_agent_provider_claude_code`

| 从 | 到 |
|---|---|
| `lib/claude_code_plugin.dart`（含 `claudeCodeAgentProviderType`、三个宿主注入参数的插件类；L11 `export ... show claudeCodeAccountDataEnrichmentKey`） | `lib/` |
| `lib/src/datasources/claude_code/**`（24 个文件，含 `stream_json_peer.dart`——虽无前缀但全文 Claude 专有，WP-B §1.1 已实证） | 同相对路径 |
| `lib/src/mappers/claude_code_*.dart`（4 个） | `lib/src/mappers/` |
| `lib/src/claude_code_cli_locator.dart` | `lib/src/` |
| `AgentProviderStaticCapabilities.claudeCode` 常量 | 本包顶层 const |
| `claudeCodeAccountDataEnrichmentKey` 常量（定义于 `src/datasources/claude_code/claude_code_provider_config.dart:4`） | 随包自然随迁；barrel 保持导出（过渡白名单，WP-D T5 后改由 definition 字段承载） |
| `nativeBundleFromClaudeCode` + `createClaudeCodeBundle` 链路 | `lib/src/` |

Claude 特有：插件工厂收三个宿主注入（`sessionDecisionStoreFactory` / `hiddenThreadStore` / `metadataLoader`），签名原样随迁；manifest 继续透传（§6）。

### T5 · 删除 `zeta_agent_providers`

三个插件全部落地后：

1. 全仓 `grep -rn "zeta_agent_providers"` 零残留（含注释里的路径示例与 G1 自查命令中的路径——守卫文本更新在 WP-E T1）。
2. 删包目录、根 pubspec workspace 成员与依赖条目。
3. 删 `AgentProviderStaticCapabilities` 类本体、`native_agent_provider_bundles.dart`、`built_in_agent_provider_plugins.dart`（能力/注册已由 manifest 承接）。
4. `bash tool/test_full.sh` 全绿。

## 5. 测试迁移映射表

根 test 树 → 插件包（逐文件核对后执行；usage/management 相关测试在 WP-D 才迁，本表不含）：

| 根 test 路径 | 目标包 |
|---|---|
| `test/src/features/agent/data/datasources/app_server/**` | codex |
| `test/src/features/agent/data/mappers/codex_*_test.dart` | codex |
| `test/src/features/agent/data/datasources/local_history/codex_*_test.dart` | codex |
| `test/src/features/agent/data/datasources/acp/**` | grok |
| `test/src/features/agent/data/datasources/local_history/grok_*_test.dart` | grok |
| `test/src/features/agent/data/mappers/grok_*_test.dart` | grok |
| `test/src/features/agent/data/datasources/claude_code/**` | claude_code |
| `test/src/features/agent/data/mappers/claude_code_*_test.dart` | claude_code |

注意事项：

- 枚举命令（实施时先跑它生成真实清单再逐行核对）：
  `git ls-files test/ | rg "(app_server|/acp/|claude_code|codex_|grok_)"`
  实测去重后 **59 个文件**（58 个 `*_test.dart` + 1 个 fixture 辅助 `grok_canonical_signature.dart`）。
- `test/src/features/agent/data/native_agent_provider_bundle_test.dart` 是三家混合断言（经 `nativeBundleFromXxx` 组装）——函数本体随家迁，测试按家拆成三段随迁；纯组装一致性部分（若有）留根树改经 manifest 断言。
- `datasources/app_server/codex_app_server_runtime_info.dart` 是 `part of 'codex_app_server_agent_provider.dart'` 的 part 文件——迁移时必须与主文件同包同相对路径，`part of` URI 不变。
- 测试里对 fixture 的相对路径引用随包迁移调整；fixture（脱敏 wire 序列）一并随迁。
- 跨厂商契约测试（不依赖具体厂商的部分）留在 core/sdk 或根 `test/src/features/agent/architecture/`，不为迁就迁移破坏 G1 纯度守卫。
- 迁出后根树分片自然减重；`tool/test_shards.dart` 无需改动（目录仍在），分片耗时若失衡留 WP-E 处理。
- `tool/test_packages.sh` 对 `packages/*` 自动发现，无需登记。

### 5.1 根测试的身份常量与 fixture 来源（重要设计）

实测约 25 个根测试文件引用 `defaultAgentProviderId`、`codexAgentProviderType`、`builtInAgentProviderSettings`、`builtInAgentProviderDefinitionCatalog` 等符号（它们今天由 providers barrel 导出）。拆包后这些符号物理上进了各插件包，而**根测试不允许 import 插件包**（WP-E 守卫把「manifest 唯一」扩展到 `test/`）。

解法：**manifest 即测试 fixture 源**。manifest（app 代码，`lib/src/app/plugins/`）除了 §6 的四类成员，再暴露一组派生快照，根测试统一改为 import manifest：

```dart
// manifest 内的测试支持面（同时也是 codec/DI 的生产来源，见 §6）
/// 与旧 builtInAgentProviderSettings 逐字段相同的启动快照。
const AgentProviderSettings zetaBuiltInAgentProviderSettings =
    AgentProviderSettings(
      providers: <AgentProviderConfig>[
        defaultCodexAgentProviderConfig,
        // T2/T3 追加
      ],
      activeProviderId: defaultAgentProviderId,
    );

/// 默认激活 Provider id（= 目录首个 definition，保持 'codex' 不变）。
const String zetaDefaultAgentProviderId = defaultAgentProviderId;
```

引用 `codexAgentProviderType` 等**类型常量**的测试走 §6 成员五的 show 再导出（manifest 是全仓唯一 import 插件包的文件，再导出天然遵守该规则）。

根测试的迁移是**纯 import 改写**（`package:zeta_agent_providers/...` → `package:zeta/src/app/plugins/agent_provider_manifest.dart`），不断言变化，符合本 WP「断言零修改」纪律。`test/src/testing/provider_settings_test_store.dart:60/99`、`memory_feature_stores.dart:48`、`activated_agent_provider_plugins.dart:11` 等公共 harness 先改，多数测试文件经 harness 间接消掉 providers import。

## 6. T4 · manifest 与注册点改造（与 T1 同 PR 落地，逐 PR 追加）

新建 `lib/src/app/plugins/agent_provider_manifest.dart`——**全仓库（含 `test/`）唯一允许 import 插件包的文件**（WP-E 守卫固化）：

```dart
/// Agent Provider 插件的编译期 manifest。
///
/// 新增 Provider：根 pubspec 加依赖 + 本文件一行 import + 三处一行登记。
/// 不做目录扫描/反射/自注册：本文件就是评审与编译期检查点。
library;

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_codex/zeta_agent_provider_codex.dart';
// import 'package:zeta_agent_provider_grok/...';        // T2 追加
// import 'package:zeta_agent_provider_claude_code/...'; // T3 追加
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

// ── 成员一：静态 definition 列表（替代 builtInAgentProviderDefinitions）──
const List<AgentProviderDefinition> zetaAgentProviderDefinitions =
    <AgentProviderDefinition>[codexAgentProviderDefinition /* T2/T3 追加 */];

// ── 成员二：不依赖激活的只读目录（替代 builtInAgentProviderDefinitionCatalog）──
// 供 codec / DI / 指纹白名单在激活前使用。与激活产出同源（同一常量），
// 一致性由 WP-E 守卫测试双向核对。
final AgentProviderDefinitionCatalog zetaAgentProviderDefinitionCatalog =
    AgentProviderDefinitionCatalog(zetaAgentProviderDefinitions);

// ── 成员三：编译期插件工厂目录（替代 createBuiltInAgentProviderPlugins）──
List<ZetaPluginFactory> zetaAgentProviderPluginFactories({
  AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
}) {
  // Claude 的三个宿主注入在 T3 追加；它们由成员四的 provider 读入。
  // manifest 是唯一允许认识厂商类型的文件，厂商专属参数集中在这里是可接受的
  // （且有且仅有这里有）。
  return <ZetaPluginFactory>[
    CodexAgentProviderPlugin(textCatalog: textCatalog),
    // T2/T3 追加
  ];
}

// ── 成员四：插件专属宿主 store 的 Riverpod provider（T3 追加）──
// claudeCodeSessionDecisionStoreFactoryProvider / claudeCodeHiddenThreadStoreProvider /
// claudeCodeCliMetadataLoaderProvider 从 zeta_store_providers.dart 整体迁入本文件——
// 它们的类型来自 Claude 插件包，只有 manifest 允许 import。

// ── 成员五：身份符号再导出（根测试 fixture 通道，§5.1）──
// 约 25 个根测试文件还引用 codexAgentProviderType 等类型常量；根测试禁 import
// 插件包，统一经本文件再导出（show 列表显式收敛，不倒灌整个 barrel）：
export 'package:zeta_agent_provider_codex/zeta_agent_provider_codex.dart'
    show codexAgentProviderType, codexAgentProviderDefinition,
        defaultCodexAgentProviderConfig;
// T2/T3 追加 grok / claude 两行
```

> **生产注入注意**：`zeta_plugin_providers.dart` 调 `zetaAgentProviderPluginFactories` 时
> 必须显式传入本地化 `AgentUiTextCatalog`（组合层既有做法）——默认参数里的
> Fallback 只是测试与装配兜底，生产路径落空等于英文文案泄漏（G7 精神）。

同步改造（**厂商类型不得逃出 manifest**——本设计的自洽关键）：

1. **`zeta_plugin_catalog.dart`**：`ZetaPluginCatalog.builtIn` 改**厂商中立**签名——只收 `Iterable<ZetaPluginFactory> factories`（+ clock/metrics），不再出现 Claude 三参数。Claude 宿主注入由 manifest 函数自己携带（读成员四的 provider 后传入工厂），`zeta_plugin_providers.dart` 调 manifest 函数拿工厂列表再传 catalog。若 `ZetaPluginCatalog` 其他签名引用厂商类型，一并下沉为 core/api 中立类型。
2. **Claude 三依赖的 Riverpod provider**（当前在 `zeta_store_providers.dart`）：整体迁入 manifest 成员四。
3. **`zeta_store_providers.dart:77`**：`fingerprintExtraKeysFor: builtInAgentProviderDefinitionCatalog` → `zetaAgentProviderDefinitionCatalog`。
4. **`agentProviderSettingsCodecProvider`**：codec 本体已是 catalog 驱动（`agent_provider_config_codec.dart:18` 的 `fallbackSettings => _providerDefinitions.defaultSettings`，`:45/:51` 用 `defaultDefinition.providerId`），只需把注入的 catalog 实例从 builtIn 换成 manifest 目录。catalog 的 `defaultSettings` 以 definitions 顺序生成，**manifest 保持 Codex 在首位**即保住 `activeProviderId='codex'` 的持久化默认（D7）。
5. 过渡期「静态目录只含已拆出的 Provider」合法：`ensureDefaultProviders` 只补回已登记 definition，与现状行为一致（现状也是三选一目录）。

## 7. DoD

- [ ] 三个插件包各自 `flutter test packages/zeta_agent_provider_<x>` 独立绿
- [ ] 每个插件包接入 `runAgentProviderContractTests` 且全绿
- [ ] manifest 是唯一 import 插件包的文件（`lib/` 与 `test/` 全域；§2 过渡白名单除外且均已注释登记）
- [ ] `zeta_agent_providers` 已删除，全仓零引用
- [ ] `AgentProviderStaticCapabilities`、`native_agent_provider_bundles.dart`、`built_in_agent_provider_plugins.dart` 不存在了
- [ ] D7 红线：`grep -rn "codexAppServer\|'acp'\|claudeCode" packages/zeta_agent_provider_*/lib` 的字符串值与拆分前逐字节一致；`agent_provider_config_codec.dart` 无 diff
- [ ] 每个 PR 全量绿、测试断言零修改（除路径/import）
- [ ] Codex 协议冒烟（`tool/smoke_codex_app_server.py --expected-version 0.144.5`）按 AGENTS.md 流程执行；无设备/凭据时在 PR 描述标「待执行/阻塞」，不得推断通过

## 8. 风险

| 风险 | 缓解 |
|---|---|
| 迁移中 import 图失真导致测试选择器漏算 | 本 WP 全部走 `test_full.sh`（已在 §3 固化） |
| 过渡白名单失控扩散 | 白名单写死 §2，WP-E 守卫只放行这几个文件；新增一律打回 |
| Claude 包体量大（30 文件）单 PR 难审 | T3 内部再拆两个 commit（先实现文件、后入口+测试），或按评审要求拆 PR |
| Grok/Claude 历史解析被 usage 与 conversation 两处共用，迁走后 usage 侧断链 | §2 已列为过渡白名单，WP-D T4 收口 |
| 根测试误留插件包 import | §5.1 统一到 manifest；WP-E 守卫 `test/` 全域禁插件包 import |

## 9. 开发记录

| 日期 | 内容 |
|---|---|
| 2026-09-04 | 初稿 |
| 2026-09-04 | 重写：三包文件数按实测清点（23/20/30）；`stream_json_peer` 归 Claude 实证落档；过渡白名单移除 `cli_process_runner`（WP-B 已迁 sdk）；新增 §5.1「manifest 即测试 fixture 源」取代测试身份常量文件方案（~25 个根测试文件纯 import 改写）；codec 的 catalog 驱动事实落档（`fallbackSettings => defaultSettings`，manifest 保持 Codex 首位保 D7）；barrel 导出清单补 `builtInAgentProviderSettings` 后继者 `zetaBuiltInAgentProviderSettings` |
| 2026-09-04 | 完整勘察报告对账：Flutter 依赖实测（仅 2 个厂商 adapter 用 `@visibleForTesting`）→ 迁 `package:meta` 的一行替换方案落档，三插件包纯 Dart 论断成立；`native_agent_provider_bundles.dart` 实测 129 行、static capabilities 86 行、built_in 51 行；测试枚举实测 59 文件（58 测试 + 1 fixture 辅助）；补 `native_agent_provider_bundle_test` 按家拆分与 part 文件（`codex_app_server_runtime_info`）随迁两条注意事项 |
| 2026-09-04 | 终审轮：① §2 白名单补 `agent_management_slice_runner.dart`（实测 `:4` import providers barrel、`:217/219` 用 enrichment key，此前漏列，WP-D T5 消灭）。② manifest 新增**成员五：身份符号 show 再导出**（约 25 个根测试还引用 `codexAgentProviderType` 等类型常量，纯派生快照不够，再导出守住「唯一 import 点」规则）与生产注入注意（localized textCatalog 必须显式传，fallback 只是测试兜底）。③ 契约测试接入改经 testing 独立 barrel（WP-B 终审定稿）。 |

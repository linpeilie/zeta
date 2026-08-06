<!--
中文在前，英文在后。不适用的条目请勾选并注明「N/A + 原因」，不要直接删除。
Chinese first, English second. For items that don't apply, tick them and note "N/A + reason" rather than deleting.
-->

## 这个 PR 做了什么 / What this PR does

<!-- 一两句话说明改动目的。/ One or two sentences on the intent. -->

关联 Issue / Related issue: closes #

## 改动类型 / Type of change

- [ ] `feat` 新功能 / New feature
- [ ] `fix` 缺陷修复 / Bug fix
- [ ] `refactor` 重构（无行为变化）/ Refactor (no behavior change)
- [ ] `docs` 文档 / Documentation
- [ ] `test` 测试 / Tests
- [ ] `chore` / `perf` 其他 / Other

## 本地验证 / Local verification

- [ ] `dart format .`
- [ ] `flutter analyze`
- [ ] `flutter test`（行为有变化时必跑 / required when behavior changed）
- [ ] 手动验证过实际界面 / Manually verified in the running app

手动验证说明 / Manual verification notes:

<!-- 用了哪个 Provider、什么场景、观察到什么。/ Which provider, what scenario, what you observed. -->

## 架构门禁 / Architecture checklist

> 详见 [CONTRIBUTING 架构红线](https://github.com/linpeilie/zeta/blob/dev/CONTRIBUTING.md#架构红线)。
> See [architectural hard lines](https://github.com/linpeilie/zeta/blob/dev/CONTRIBUTING.en.md#architectural-hard-lines).

- [ ] 依赖方向未被打破，新代码放在对应 feature 的 domain/application/data/presentation 下
      / Dependency direction intact; new code sits in the right feature layer
- [ ] Provider 原始协议只出现在 data 层，UI/application 只消费中立 domain 契约
      / Raw provider protocol stays in the data layer; UI and application consume neutral contracts
- [ ] 共享层（decoder、CoalescingPolicy/Buffer、Pipeline、TimelineStore）没有新增 Provider import、kind/id 分支或 raw 字段读取
      / No new provider imports, kind/id branches, or raw field reads in shared layers
- [ ] UI 按 capability 渲染，未支持能力 `capability = false` 且抛 `UnsupportedError`，没有静默成功
      / UI renders by capability; unsupported paths throw `UnsupportedError` instead of silently succeeding
- [ ] 未硬编码颜色、圆角、阴影；语义 token 走 `IdeThemeScope` / `IdeColors` / `IdeTextStyles`
      / No hard-coded colors, radii, or shadows; semantic tokens only
- [ ] 未读取或改写 `~/.codex`、`~/.grok`、`~/.cursor`；新增持久化字段在白名单内，未落盘 prompt、回复、工具输出、原始错误文本或凭证
      / No access to other CLIs' config; no prompts, responses, tool output, raw errors, or credentials persisted
- [ ] 未引入自动授权命令、文件或网络的行为
      / No behavior that auto-authorizes commands, files, or network access

### 仅在相关时勾选 / Only if applicable

- [ ] **改动了 `AgentEvent`**：已逐项回答开发者文档 §7 的 16 条接入清单，并用测试固定
      / **Changed `AgentEvent`**: worked through all 16 checklist items and pinned with tests
- [ ] **改动了 reducer**：保持纯同步，无 scheduler / `Timer` / `Future` / 外部回调，副作用走 EffectRunner
      / **Changed a reducer**: still purely synchronous; side effects via EffectRunner
- [ ] **改动了页面切换行为**：已用真实 `IdeHome` 补 Widget 测试，验证 Element、草稿、滚动位置、面板宽度不被重置
      / **Changed page switching**: added widget tests against the real `IdeHome`
- [ ] **升级了 Codex 协议**：已跑 `gen_codex_schema --diff` 并完成真实 CLI 冒烟
      / **Upgraded the Codex protocol**: ran the schema diff and real-CLI smokes
- [ ] **新增了依赖**：已确认内建方案不足，并在下方说明用途
      / **Added a dependency**: confirmed built-ins fall short; purpose explained below
- [ ] **平台生成目录有改动**：已确认由 Flutter 工具产生，并在下方说明原因
      / **Generated platform files changed**: confirmed tool-generated; reason explained below

补充说明 / Notes:

<!-- 新依赖用途、平台文件改动原因、已知限制、后续计划。/ New dependencies, platform file changes, known limitations, follow-ups. -->

## 截图 / Screenshots

<!-- UI 改动请附前后对比。/ For UI changes, please include before/after. -->

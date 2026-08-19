# 迁移执行决策日志

中文 | [English](../../en/architecture/migration_execution_decisions.md)

状态：**持续记录中**。本文记录架构基线冻结后，实施阶段出现的偏差、证据、决策与
影响。2026-08-19，项目所有者授权迁移 Agent 对后续决策采用风险最低、最符合既有架构
的建议方案并持续执行。

## 2026-08-19 — 步骤 10 桌面契约校正

**问题。** 脚手架级桌面 port 过窄，无法保留旧项目行为：字体缺少稳定 family identity；
文件选择与剪贴板 API 无法表达多图片/多文件；menu、window、attention 与系统文件管理器
操作缺少所需的类型化输入。

**证据。** 旧项目 macOS/Windows/Linux runner 与 app composition 已使用这些行为；同时
冻结规则仍禁止 Flutter/plugin 类型越过共享包边界。

**决策。** 经所有者逐项批准，只扩充 pure-Dart value contract；所有 plugin/channel
具体实现仍限制在 `lib/app/platform/`。使用结构化不可变值和可注入 facade，不暴露
plugin 类型。

**影响。** 步骤 10 在不把平台 IO 移入 Bloc/Presentation 的前提下保留行为。native
contract test 与 Windows Debug build 已验证结果；未改 Provider port。

## 2026-08-19 — 步骤 11 当前 schema 与失败语义

**问题。** 旧 Provider codec 同时接受 settings V1/V2、迁移权限字段，并在文件损坏时
静默返回默认值或空 cache/context。步骤 11 明确要求只支持当前 schema，并返回 typed
decode failure；共享层 `AgentProviderSettings.supportedVersions` 与
`AgentModelCatalogCacheStore` 注释仍保留旧语义。

**证据。** `AgentProviderSettings.supportedVersions` 为 `{1, 2}`，cache port 要求损坏或
不兼容内容返回空列表，与步骤 11 任务及包 API 契约直接冲突。

**决策。** 经所有者批准：Provider settings 只支持 V2；未知版本、非法 JSON、字段结构
错误、重复稳定 id、落盘 thread identity 不匹配均返回类型化解码失败。文件不存在仍是
正常首次运行状态（空列表或 `null`）。是否重建由上层决定，Data client 不自行恢复。
不持久化 active Provider 选择状态，也不新增或修改 Provider 方法签名。

**影响。** 共享契约注释与支持版本常量收敛到当前 schema。`agent_config_client` 失败关闭，
不做历史迁移或静默截断，使用原子替换，并排除 CLI locator、Controller 与选择状态。

## 2026-08-19 — 步骤 12 Codex 协议基线与包边界

**问题。** 步骤 12 的目标 package 只有占位实现；要求锁定的 Codex `0.144.5` schema
快照及生成脚本仍只存在于旧仓库。旧 adapter 还依赖应用 localization 与全局日志，不能越过
新的 Data/neutral-contract 边界。

**证据。** 旧快照恰为 269 个文件，与文档 pin 完全一致。冻结的 package API 要求 barrel
只暴露 bundle factory、静态 capability 与 CLI locator，并要求 peer、process、logger、clock
注入缝；无需修改任何共享 Provider 签名。

**决策。** 原字节迁入 schema 快照和两套生成脚本；contract test 固定文件数、版本、消息、
终态通知、capability 与 server request。应用 localization 不进入 package：中立状态使用 typed
code，仅对协议 item 必需的可读标签使用私有稳定英文 fallback catalog。只导出三个冻结入口；
专项协议测试入口放在 `lib/src/testing/`，不进入 barrel。

**影响。** Codex 实现及 schema 真相源由 `codex_app_server_client` 独立持有和测试；不 import
Presentation/localization package，也未修改共享适配层或 Provider port。

## 2026-08-19 — 步骤 12 CLI 路径与覆盖率加固

**问题。** 兼容测试发现 Unix HOME fallback 的 join 会去掉开头 `/`，把 Codex 可执行路径变成
相对路径。首次完整 package coverage 为 87.66%，缺口主要是旧 adapter 继承的宽容协议与
lifecycle 分支。

**证据。** Unix HOME locator 测试稳定复现相对路径。coverage 报告还定位到重复或不可达的
防御分支（包括重复的 patch output fallback、validate 后不可能进入的 conversation-mode 分支），
以及尚无专项用例的 malformed/future 协议形态。

**决策。** 唯一 CLI locator 同时保留 Unix root 与 Windows UNC 前缀。100% 门禁不变；增加
真实兼容/lifecycle 测试、非 barrel 的内部协议测试 harness 和可注入本地文件读取缝。只删除经
当前调用图证明不可达或重复的分支，不添加 coverage ignore，也不降低阈值。

**影响。** Unix fallback 始终为绝对路径，进程恢复覆盖 platform/config environment 组合；
步骤 12 的 168 tests 达到人工 coverage 100%（3,601 / 3,601）。测试缝保持内部实现，不扩张
受支持的 package API。

## 2026-08-19 — 步骤 11 desktop run 被取消

**问题。** 步骤 11 的 desktop-build workflow run `32262347277` 最终为 cancelled，且各 job
没有报告 failure。

**决策。** 按并发取消而不是产品失败处理，记录该事件，并要求下一次迁移提交重新跑完整
desktop matrix。

**影响。** 未针对不存在的失败修改代码；远端 desktop 验证顺延至步骤 12 push。

## 2026-08-19 — 步骤 12 hosted source 锁文件可移植性

**问题。** 步骤 12 的 `license_check` run `32269642148` 尚未进入许可证扫描，就因
`flutter pub get --enforce-lockfile` 判定 176 个 hosted 依赖都会变化而失败。

**证据。** 依赖版本和 SHA-256 均未变化；唯一的批量差异是本机
`PUB_HOSTED_URL=https://pub.flutter-io.cn` 环境把 `pubspec.lock` 中所有 hosted URL 改成了
镜像地址，而 GitHub Actions 按约定使用 `https://pub.dev`。

**决策。** 用仅作用于当前命令的官方源环境变量重新生成并校验锁文件；依赖版本与校验和
保持不变，不放宽 lockfile、CI 或许可证门禁。以后即使开发机使用镜像，提交的锁文件也必须
规范化为 `https://pub.dev`。

**影响。** `flutter pub get --enforce-lockfile` 已能在与 CI 相同的源上通过。本次失败是提交
锁文件的可复现性缺陷，不是依赖许可证例外。

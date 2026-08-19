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

## 2026-08-19 — 步骤 12 与宿主无关的覆盖率

**问题。** 锁文件可移植性修复后，`zeta` run `32269931378` 在 Linux 上通过了
`codex_app_server_client` 全部 168 个测试，但覆盖率为 99.78%。本地 Windows 结果为 100%，
原因是两个恢复测试在非 Windows runner 上提前返回。

**证据。** 未覆盖行为属于 Windows CLI 发现与 launcher 恢复；`CodexCliLocator` 已提供明确的
environment、platform 与 file-existence 注入缝。所有者此前仅豁免旧仓库覆盖率，不适用于新的
VGV 目标仓库。

**决策。** 保持 VGV package 的 100% 覆盖率阈值；通过已有 pure-Dart 注入缝，在所有宿主上
覆盖 Windows PATH、LOCALAPPDATA、APPDATA、命令包装器和 UNC 路径。不添加 coverage 排除，
也不降低 CI 门禁。

**影响。** CLI 发现测试不再依赖 runner 操作系统；Linux 结果由下一次 push 验证。生产 API
与共享 Provider port 均保持不变。

## 2026-08-20 — 步骤 13 Claude 包边界与延期能力

**问题。** 旧 Claude adapter 同时引用应用 localization、全局日志、auth probe 和 token usage
来源；若逐文件照搬会越过新的 Data package 边界，并把步骤 16/21 的职责提前混入步骤 13。

**证据。** 已冻结的 `agent_provider_contracts` 足以表达 conversation、permission、question、
plan、model、quota 与 history；无需新增 Provider 方法。迁移任务又明确把 Claude auth probe 归入
`agent_management_client`，把 provider token metering source 归入用量步骤。

**决策。** `claude_code_client` 只迁 stream-json runtime、vendor mapper/adapter、history、quota、
credential/keychain 只读来源与唯一 CLI locator。应用文案改为 package-private 稳定英文 catalog，
日志改为可注入的 scoped logger。auth probe 延至步骤 16，token metering source 延至步骤 21；
不改共享适配层或 Provider port。barrel 只暴露 factory、static capabilities 与 locator。

**影响。** 三方 vendor 隔离保持可由 pubspec 和 barrel 判定；凭据不由本包写盘，异常和日志不含
token、stderr、路径或原始协议体。延期能力仍由后续步骤显式追踪，没有静默丢失。

## 2026-08-20 — 步骤 13 覆盖收敛与状态恢复加固

**问题。** 首次完整覆盖率为 85.51%。缺口既包含真实的 process/stream/filesystem 故障路径，
也包含被更早会话校验、peer 清理或 mapper 规范化严格支配的重复分支。故障测试还发现：模型或
权限切换的新 peer 启动失败、且旧配置恢复也失败时，provider 会残留一个已绑定但未启动的 peer。

**证据。** 调用图证明 session id 与 working directory 同时安装，pending registry 在 peer 脱离前
清空，history reducer 的 title/kind/location/input 已由同一 reader 内的 mapper/file tracker
补全。反向注入则稳定复现 stdin/control response、filesystem、双重恢复和并发切换失败。

**决策。** 保持 100% 门禁，不添加 coverage ignore、不降低阈值。为可达 I/O 与状态机故障增加
内部注入缝和真实回归测试；删除仅由同一调用链前置不变量保证不可达的重复判断。双重恢复失败时
立即 teardown 恢复 peer，provider 回到明确不可用状态，不保留半初始化 transport。

**影响。** 264 个随机顺序测试覆盖 permission/question/plan、identity、history、process lifecycle、
Windows/POSIX locator 与密钥链边界，人工 coverage 达到 100%（2,962 / 2,962）。测试缝未进入
barrel，也未扩张共享契约。

## 2026-08-20 — 步骤 13 metadata 异步泄漏与 smoke 路径

**问题。** 正式随机门禁发现 metadata probe 在进程启动失败前就注册 timeout；主调用已经返回
脱敏异常后，遗留计时器仍会稍后向测试 zone 抛错。随后 fixture smoke 又因脚本仍指向旧仓库
`test/src/features/...` 路径而误报 fixture 无效。

**证据。** 将启动失败测试 timeout 缩短后可稳定观察到“测试结束后失败”。当前 fixture 的真实
归属是 `packages/claude_code_client/test/src/datasources/claude_code/fixtures/`，内容 contract
测试已通过。

**决策。** 仅在 peer 成功启动并发送 initialize 帧后创建 timeout future，所有更早失败不再留下
异步任务；增加等待超过 timeout 的回归断言。smoke fixture 路径改为当前 package 归属，不复制
第二份 fixture。真实 smoke 只执行无 Prompt、只读 initialize，不执行可能修改配置的操作。

**影响。** 两轮随机 Very Good test/coverage 均稳定通过；fixture smoke 与本机 Claude Code
2.1.227 initialize smoke 均通过，且输出只包含 OS/架构/版本、模型计数、default 计数和脱敏订阅名。

## 2026-08-20 — 步骤 13 官方依赖源锁文件复验

**问题。** 在官方 `pub.dev` 环境执行 `flutter pub get --enforce-lockfile` 时，工作区锁文件仍包含
中国镜像 URL，因此工具报告 176 个依赖会发生变化；版本与校验和本身没有冲突。

**决策。** 将官方源作为已批准 Flutter 3.47.0 / Dart 3.13.0 基线的一部分，先用官方源正常
解析并恢复锁文件来源，再立即以 `--enforce-lockfile` 复验。不得把本机镜像 URL 提交进仓库。

**影响。** 复验通过，锁定版本未改变，`pubspec.lock` 不再包含 `flutter-io.cn`；该处理不涉及
共享适配层或 Provider 端口。

## 2026-08-20 — 步骤 14 Grok 契约与迁移顺序偏差

**问题。** 任务要求覆盖 Grok usage/history，但共享契约中没有文档假定的 usage-window 类型；
同时 manifest 把 vendor-specific Grok history reader/parser 标为步骤 15，而步骤 14 的出口又明确
要求 history contract tests。照字面拆分会导致 `grok_acp_client` 无法独立闭环。

**证据。** 现有 `agent_provider_contracts` 已能表达 quota、token usage 与 thread history，旧 Grok
usage-window 标签只在 vendor 内部消费，无需新增 Provider 方法。步骤 15 的目标则明确只保留跨
Provider merge/replay 和通用容错，禁止复制 vendor parser。

**决策。** 不修改共享适配层或 Provider port；usage-window 文案保持 Grok package-private helper。
将 Grok 私有 history reader/parser 随步骤 14 一并迁入，步骤 15 只迁跨 Provider 聚合。barrel 仍
只导出 factory、static capabilities 与 locator。

**影响。** 步骤 14 可独立完成 usage/history 契约，步骤 15 不会再复制 Grok 协议解析。迁移顺序
偏差已显式记录，没有扩大共享 API。

## 2026-08-20 — 步骤 14 覆盖率与运行时不变量收敛

**问题。** 首轮完整覆盖只有 83.01%。大部分缺口是可达的 filesystem、permission/question/plan、
prompt race、model merge、title polling 与 replay 前缀分支；另有少量检查与
`ProviderRuntimeJsonRpcPeer` 或 pending registry 的前置保证重复。

**证据。** 注入故障稳定覆盖了 malformed UTF-8、响应失败、late prompt error、dispose/cancel 与
离线 history；调用链同时证明 initialize 成功后必有 runtime scope、只有非空 permission options
会进入 pending、转发的 notification/server request 必带当前 runtime scope。

**决策。** 保持 100% 门禁，不加 coverage ignore、不降阈值。为真实故障补 contract tests；只删除
被同一调用链严格支配的重复防御分支，并把 scope/options 约束写成实现不变量。包内异步文件读取
保留，关闭 `avoid_slow_async_io`；内部实现不逐符号承担公共 API 文档，关闭
`public_member_api_docs`，三个 barrel 导出仍有文档。

**影响。** 233 个随机顺序测试达到人工 coverage 100%（3,257 / 3,257），analyze 为 0 issues；没有
测试专用符号进入 barrel，也没有修改共享 Provider port。

## 2026-08-20 — 步骤 14 Grok 真实恢复烟测竞争

**问题。** 首次 Grok CLI 1.0.4 smoke 中两个独立进程的 prompt 均成功，但原进程终态返回后立即
回收，新进程恢复在合并的 `recovery/timeout` 标签下超时，无法判断具体阶段。两次运行之间 CLI
又自动更新到 1.0.5。

**证据。** 脚本未输出 session id、正文、payload、stderr 或凭据。增强阶段标签并在源进程关闭后
增加 2 秒有界持久化窗口，再以 CLI 1.0.5 复跑，两个并发 session 与新进程 `session/load` 后的
prompt 全部以 `end_turn` 完成。

**决策。** 将首次失败视为终态与本地 session 异步持久化的回收竞争；保留 2 秒 flush window 和
细粒度恢复阶段标签，不放宽超时、不重试 prompt，也不读取真实项目。协议基线以最终实测的
Windows 11 / Grok 1.0.5 / 2026-08-20 为准。

**影响。** AC1 进程隔离和回收后恢复均有真实 CLI 证据。烟测仍使用临时空目录、默认 Ask 与
反向请求拒绝策略，未修改用户配置。

## 2026-08-20 — 步骤 14 本机镜像再次改写锁文件

**问题。** 单独诊断测试未显式覆盖官方源环境变量，Flutter 自动解析依赖时再次把 176 个 hosted
URL 改成 `pub.flutter-io.cn`。

**决策。** 仅机械恢复为 `pub.dev` 并确认锁文件最终无差异；正式门禁继续在命令作用域显式设置
官方 pub 与 Flutter storage 源。依赖版本、SHA-256 与约束不变。

**影响。** 没有镜像 URL 或无关 lockfile 噪声进入步骤 14 提交。

## 2026-08-20 — 步骤 13 desktop-build Linux 工具链超时

**问题。** 步骤 13 提交的 desktop-build run `32277823777` 在 30 分钟 workflow timeout 时被
取消。macOS 三个 flavor、Windows 三个 flavor、Linux staging 均已成功；Linux development 与
production 都停在 `Install Linux desktop toolchain`，尚未进入 Flutter 或构建步骤。

**决策。** 判定为 runner apt/toolchain 阶段超时，不修改产品代码，也不把部分成功视为完整桌面门
通过。步骤 14 push 后重新要求完整 desktop matrix；若同一 apt 阶段再次超时，再单独优化 workflow
安装方式。

**影响。** 步骤 13 的 zeta、license、OSV 均成功；桌面全矩阵证据顺延到步骤 14 远端验证。

## 2026-08-20 — 步骤 14 Linux 覆盖率平台偏差

**问题。** 本机 Windows 门禁为 100%（3,257 / 3,257），但 GitHub Actions zeta run
`32284769504` 连续两次在 233 个测试全部通过后报告 99.79%。同一提交的 desktop-build run
`32284769075` 九个 OS/flavor 作业全部成功，步骤 13 的 Linux apt 超时未复现。

**证据。** 为 CI 保留通用的失败行诊断后，run `32285470965` 精确报告 7 行未覆盖：Linux 没有
走到 Windows `APPDATA/npm` locator 分支，也没有走到 history reader 的跨项目递归兜底扫描。
这两条都是受宿主平台和 fixture 目录编码影响的真实兼容路径，不是无效代码。

**决策。** 不降低 100% 阈值、不加 coverage ignore。新增显式注入 Windows 模式的 APPDATA
locator 测试，以及不提供 project/session path 的递归历史查找测试，让每个 runner 都验证两条
兼容路径。保留 CI 的未覆盖文件/行号输出，作为所有 package 的通用失败诊断。

**影响。** Grok 包现有 235 个随机顺序测试，本机仍为 100%（3,257 / 3,257）；修复只补测试与
CI 诊断，不修改生产实现、共享适配层或 Provider 端口。

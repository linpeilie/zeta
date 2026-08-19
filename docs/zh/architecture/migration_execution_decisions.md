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

## 2026-08-20 — 步骤 15 无旧聚合实现与合并语义

**问题。** 文档要求迁移 Provider 中立的 history merge/replay 输入，但旧仓库只存在 Codex、Claude
与 Grok 各自的 parser/reader，没有可直接搬迁的跨 Provider 聚合实现。目标 package 也只有模板
占位类；若复制任一 vendor parser 会违反步骤 15 边界。

**决策。** 按已批准契约新建通用 JSON Lines 外壳：caller 注入完整 reader 与 vendor decoder，
本包不理解 vendor 字段。malformed JSON、非 object 与显式 `HistoryRecordDecodeException` 只跳过
当前行并返回 typed warning；reader IO failure 和其他 decoder 异常不捕获。输入按 caller 顺序
处理，重复 turn id 由后输入在首次位置覆盖。warning 不保存原始行、异常或用户内容。

**影响。** `agent_history_client` 只依赖 `agent_provider_contracts`，删除模板遗留且未使用的 logging、
storage 与 mock 依赖；barrel 只导出 `history_merge.dart`。没有 vendor、Flutter、Repository 或 UI
依赖，也没有修改共享 Provider port。5 个随机顺序测试达到 100%（41 / 41）。

## 2026-08-20 — 步骤 16 旧 Repository 超出新 Data 边界

**问题。** 三个旧 management repository 把外部 IO 与 runtime registry、model catalog 组装、
本地化文案、latest-version 检查和 UI progress 状态混在一起；整体复制会违反步骤 16 契约。同时
每个 vendor package 已拥有唯一有效的 CLI locator，在本包重写路径发现会产生竞争归属。

**决策。** 新建 `AgentManagementDataSource` 边界，不整体复制旧 repository。vendor 自有的路径解析、
CLI 定位、无 Prompt protocol probe 与 account-evidence callback 全部通过注入复用；对外只返回稳定
neutral response 与 failure code。runtime catalog、本地化、repository policy 和 UI 状态留给后续层。
不修改共享适配层或 Provider port。

**影响。** 三个具体 management source 只依赖 contracts 与共享 IO 工具，不互相导入，也不导入
vendor client、Flutter、Repository 或 Presentation。步骤 17 可以直接验证 locator 唯一归属，
无需再消解重复实现。

## 2026-08-20 — 步骤 16 配置契约与旧行为不同

**问题。** 步骤 16 API 明确要求配置可读写，且 save 只接收 `contents`。旧 Codex/Grok save 还接收
original snapshot 来做乐观冲突检测；旧 Claude 则只返回 metadata 并拒绝所有 save。保留任一旧行为
都会与已批准公共契约矛盾。

**决策。** 服从新契约：Codex/Grok 支持当前语法 TOML，Claude 支持 JSON object；拒绝符号链接，
复制既有备份，并委托 `zeta_storage` 原子替换。document signature 保留为读取证据，但不虚构 save
API 无法执行的 conflict exception。只把已知 parser `FormatException` 转为安全 typed validation
code，非预期 parser failure 原样抛出。Data 层继续使用异步 IO，因此本包关闭不适用的
`avoid_slow_async_io` lint。

**影响。** Claude current-schema 配置编辑按迁移计划可用；Codex/Grok 不再宣称新 API 不具备的
乐观并发保证。后续 Repository/UI 在保存后重新读取；若以后确需该保证，应单独提出契约变更。

## 2026-08-20 — 步骤 16 credential 与日志最小化

**问题。** 旧 Grok detector 通过读取 `auth.json` 推断账户状态；CLI 原始输出、配置与日志都可能
含凭据。让通用 management client 返回这些 payload 会扩大密钥处理面。

**决策。** 不读取 Grok credential file 内容，账户证据通过注入获得。Claude probe 只执行
`auth status --json`，只接受 exit code 0/1，并只保留四个非密钥白名单字段。限制 process output
与 log tail 大小，拒绝不安全日志路径，在返回 log entry 前脱敏常见 token/key/password 模式；
不记录 raw auth JSON、stdout、stderr、配置或捕获异常。

**影响。** 静态安全审计未发现内嵌密钥、原始 credential 日志或 provider credential storage 依赖。
detect 保持无 Prompt；证据不可用时返回 neutral status，不再根据 credential 文件名猜测登录态。

## 2026-08-20 — 步骤 16 跨平台 process fixture 与官方依赖源

**问题。** 首个真实 process 测试执行 `Platform.resolvedExecutable --version`；在 `flutter test`
中该路径是 Flutter test host，不是 Dart CLI，所以成功断言失败。此前另一次 `--no-pub` 诊断忘记
设置命令作用域官方源变量，打印了本机中国镜像警告，但未解析依赖、也未改动 lockfile。

**决策。** 使用一次性跨平台 system shell 和有界 sleep 命令覆盖默认 process starter；其余 process
行为继续用注入 fake 确定性测试。删除不可达 parser catch-all，而非将其排除出 coverage。最终包级
与 workspace 门禁显式设置 `pub.dev`/Google storage，并用
`flutter pub get --enforce-lockfile` 复验锁文件。

**影响。** 本包 35 个随机顺序测试在 Windows 达到 CI 口径 100% coverage（329 / 329），未添加
coverage ignore。最终 workspace 同轮 1,052 tests、12,941 / 12,941；lockfile 保持官方源，
生产代码不带入镜像或 test-host 假设。

## 2026-08-20 — 步骤 17 缺少两份已裁决迁入的 Codex smoke harness

**问题。** migration manifest 明确把 5 个真实 CLI smoke 脚本分配给步骤 17/33/36，但新仓库只有
Claude 两个和 Grok 一个，两个 Codex 脚本仍留在旧仓库。旧 app-server 与 Grok smoke 还会继续
创建 session 并发送 Prompt，超出了步骤 17 的只读 capability probe。

**决策。** 先逐字节迁入两份旧 Codex 脚本，再做有限增量。Codex app-server 新增
`--capabilities-only`，在 initialize 与 `model/list` 后停止；Grok 同名模式只执行 initialize，
不 authenticate、不建 session、不 recovery、不发 Prompt。Codex plan-mode harness 留到后续验收
步骤再执行。不替换现有 vendor locator，也不调用会修改配置的命令。

**影响。** 已裁决的 5 个 harness 全部到位。步骤 17 可在不执行模型任务、不传用户内容、不持久化
session、不修改配置的前提下验证当前 wire capability；步骤 33/36 仍保留其所需完整 prompt/session
harness。

## 2026-08-20 — 步骤 17 将 Provider 隔离与 teardown 变成可执行约束

**问题。** pubspec 隔离已有通用测试，但 locator 精确归属、fixture 分配、smoke 清单与 teardown
证据仍只是 checklist 文案。首版 guard 还假定每个 provider test 都必须显式调用
`subscription.cancel`；Claude 实际在 `StreamJsonPeer` 关闭时证明 listener 完成。

**决策。** 在 `.architecture.yaml` 声明 locator owner 与 5 个 smoke 脚本；新增 root architecture
test，要求每个 owner path 恰好一个 locator class declaration，拒绝所有 vendor test/fixture 的外部
vendor package/path 引用，并绑定真实 lifecycle 测试。Codex/Grok 要求显式 subscription cancel；
Claude 则要求 provider dispose 加上 peer 的 `emitsDone` 和 `close` process/stream 断言。按真实生命周期
契约验证，不为测试制造无意义 subscription handle。

**影响。** 今后重复 locator、跨包 fixture、缺失 harness 或删除 teardown 证据，都会让普通 root
quality job 失败；没有修改生产 API 或 Provider port。

## 2026-08-20 — 步骤 17 真实 capability smoke 基线

**问题。** 集成门需要三个已安装 CLI 的新证据，但不能泄漏 payload 或改变用户状态。首次用于
创建并递归清理计算型临时目录的 wrapper 被执行安全策略拒绝。

**决策。** 只运行有界 capability 路径。Codex capability-only initialize 与 `model/list` 不检查或
创建 thread，因此从仓库 cwd 复跑且不执行清理写操作；Claude 使用现有临时目录、无 Prompt metadata
harness；Grok initialize 不 authenticate、不建 session。只报告版本与计数，随后检查进程表是否
残留协议子进程。

**影响。** Codex 0.144.1 返回 7 models；Claude Code 2.1.227 返回 5 models、1 default；Grok
1.0.5 返回 protocol v1、6 个 capability key、2 种 auth method。三者均通过，未打印 raw payload
或身份信息，也没有残留 Codex app-server、Claude stream-json 或 Grok stdio 子进程。

## 2026-08-20 — 步骤 18 的 system font 归属冲突

**问题。** 逐文件 migration manifest 把旧 Flutter `MethodChannel` 实现
`system_font_catalog_service.dart` 分给 `settings_client`；但更具体的步骤 18 checklist、package API
contract、topology 与 ownership map 都明确禁止本 Data 包包含 system font concrete implementation，
并把 font catalog 读取归给后续 `settings_repository`，通过 `desktop_platform_api` 中已经存在的
`SystemFontCatalogApi` 端口完成。

**决策。** 服从更具体的分层架构契约：不复制旧 service、不修改共享端口，也不为当前不使用的端口
给 `settings_client` 增加 `desktop_platform_api` 依赖。后续 `settings_repository` 步骤消费现有端口，
由 composition 注入平台实现。

**影响。** `settings_client` 保持 pure Dart，只负责 general/appearance 文档 IO；不产生重复
`MethodChannel`，不提前实现平台层，也没有修改共享适配层或 Provider port。

## 2026-08-20 — 步骤 18 的 current-schema 与失败策略不同于旧实现

**问题。** 旧 general codec 接受 schema v1/v2；两个旧 store 还经常把损坏文件或 IO failure 静默
转成默认值。旧 appearance store 同时包含 SharedPreferences 迁移和 callback/domain model。
保留这些行为会违反明确的 current-schema-only Data 契约，还会把权限拒绝或原子写失败伪装成持久化成功。

**决策。** 只支持 general schema v3 与 appearance schema v1。持久化值改为 immutable、无 Flutter
的 `Response` 对象；domain 转换、legacy migration 与 policy 留给后续 Repository。缺失、空或只有
空白的 clean-install 文档返回注入默认值；malformed JSON、非法字段与不支持版本抛出不含原文的 typed
decode failure。storage read/permission failure 与 atomic-write failure 通过可注入的
`SettingsDocumentStorage` 原样传播；生产 adapter 委托 `zeta_storage.AtomicTextFile`。保留合理的异步
文件 IO，并在本包关闭不适用的 `avoid_slow_async_io` lint。

**影响。** 损坏文件不会被误认为 clean install，写入失败也不会伪装成功。测试覆盖两个 schema、
缺失/空/损坏输入、IO 权限拒绝、close 行为，以及保留旧文档的真实 atomic replacement failure。
本包没有 Flutter、SharedPreferences、Repository、Bloc、Cubit 或 system font 具体实现依赖。

## 2026-08-20 — 步骤 18 desktop-build runner 超时

**问题。** desktop 9 个矩阵已有 8 个通过，Linux staging 却把 30 分钟 job 上限全部耗在 Ubuntu
desktop 系统包安装，尚未开始 Flutter setup、依赖解析或项目编译便被取消。同一 workflow 的其余
Linux variant 与全部代码质量 job 都是绿色。

**决策。** 将首次结果视为 runner 基础设施延迟，只重跑失败 job；没有代码或构建证据支持修改项目、
扩大 workflow timeout，或重跑已经成功的 8 个矩阵，因此均不做。

**影响。** attempt 2 约两分钟即完成 Linux staging。步骤 18 commit 的 zeta、desktop-build（9/9）、
OSV 与 license workflow 全绿；没有为一次性 apt 延迟引入 CI 配置变更。

## 2026-08-20 — 步骤 19 拆分 gitignore 输入与匹配策略

**问题。** 步骤 19 与 package API contract 把 gitignore input 分给 `workspace_client`，migration
manifest 则把旧 `workspace_gitignore.dart` domain matcher 分给 `workspace_repository`。把 matcher
复制进 Data 会违反该裁决；把所有 gitignore concern 留在 Repository 又会让外部文本 IO 越层。

**决策。** `GitignoreReader` 精确读取 root `.git/info/exclude` 与各目录 `.gitignore` 原始文档；
`WorkspaceScanner` 维护遍历作用域，并把 immutable active-document 列表交给注入的纯
`WorkspaceEntryFilter`。include/skip/prune 是中立机制；pattern parse、last-match-wins、negation 与
Zeta hard-ignore policy 留给后续 Repository。链接形式的 `.git`、`info` 或 ignore file 均不遍历。
不修改共享适配层或 Provider port。

**影响。** 所有 `dart:io` ignore input 留在 Data，domain policy 不下沉。嵌套文档不会泄漏到 sibling；
忽略目录可为可能的 negation 继续遍历，也可直接 prune。`workspace_client` 不依赖 `glob` 或 Repository。

## 2026-08-20 — 步骤 19 用可取消 async IO 取代同步 isolate walk

**问题。** 旧 corpus builder 在 isolate 中执行同步文件系统调用，把 access failure 静默变成空/部分
结果，且只能靠文件数上限停止。旧 tree builder 还把 `expandedPaths` 交互状态与目录 IO 混在一起。
步骤 19 明确要求大目录取消、权限拒绝/文件消失行为，以及只反映文件系统的 response。

**决策。** 使用异步 `Directory.list`/read/watch primitive，并全部放在可注入的
`WorkspaceFileSystem` 后；async streaming 已避免 UI 路径阻塞，不再保留额外 isolate protocol。
每个遍历边界检查 cooperative `WorkspaceScanCancellationToken`，取消抛 typed exception；达到
`maxFiles` 时 response 明确标记 `truncated`。denied/list failure typed 传播；枚举期间消失的实体、
不支持实体与 link child 跳过。`readDirectory` 只读一层并排序，不含 expanded/selected；recursive
watch 由 caller 取消，底层 subscription 同步释放。

**影响。** Data test 可完全绕过真实 IO。root/请求目录遇到 link、词法逃逸或 canonical 逃逸时
fail closed；生产枚举从不跟随 child link。本 client 只暴露 file scan、directory read、gitignore
input 与外部 change stream；index/query policy 和交互 progress 留给后续 Repository/Cubit。

## 2026-08-20 — 步骤 19 最终门禁中的无关 keychain 时序 flake

**问题。** 首次最终 workspace test 同轮在未改动的 `claude_code_client` compatibility test
`keychain process runner covers success, timeout, and start failure` 出现一次失败。Step 19 包测试没有
失败，且错误只在该次随机顺序聚合运行出现。

**决策。** 先单独复现该 named test，再用新 random seed 与 100% coverage gate 重跑整个归属包。
两者分别 1/1 与 264/264 通过，因此不修改无关 keychain 代码，也不放宽断言。由于 green gate 要求
最后一次完整同轮无中断通过，从头重启 26-root test/coverage iteration。

**影响。** 第二次 workspace 同轮全部 1,107 tests 与人工代码 13,380 / 13,380 通过。该瞬时时序
问题得到记录，没有污染 Step 19 patch，也没有削弱既有 security-sensitive timeout 测试。

## 2026-08-20 — 步骤 19 desktop-build 再次出现隔离的 apt 超时

**问题。** 步骤 19 desktop workflow 再次达到 8/9 绿色，但 Linux production 把 30 分钟 job 上限
全部耗在 `Install Linux desktop toolchain`。Flutter setup 与仓库代码都未开始；另两个 Linux variant
以及全部 Windows/macOS matrix 均通过。

**决策。** 沿用既有基础设施策略：只重跑失败 job，不改源码、timeout 或 workflow。本次受影响的是
Linux production，与步骤 18 的 Linux staging 不同，仍没有可确定复现的项目或特定矩阵故障可修。

**影响。** attempt 2 未改代码即通过。步骤 19 的 zeta、desktop-build（9/9）、OSV 与 license
workflow 全绿；两次 apt 事件均保留记录，供后续观察趋势。

## 2026-08-20 — 步骤 20 将 session domain 与恢复策略留在 Data 之上

**问题。** 旧 `IdeSessionState` 把持久化 schema 字段与 domain object 混合；旧 snapshot helper 又把
codec 投影与 `ProjectThreadListState` restore plan 混合。manifest 与 ownership map 则把 domain model
分给 `project_session_repository`、restore plan 分给 Cubit/Bloc，仅把 current-schema IO 与 codec 分给
`project_session_client`。

**决策。** 在 Data 定义中立的 `SessionSnapshotResponse`、`SessionThreadSummaryResponse` 与
`SessionWorkbenchResponse`。保留当前 v4 JSON 投影，但不复制 domain 转换、filesystem pruning、
selected-thread 归一化或恢复时序。只接受 v4：缺失/空文档表示 clean install；malformed、不支持版本或
非法 current document 抛出不含内容的 typed decode failure。不修改共享适配层或 Provider port。

**影响。** 本包不依赖 Flutter、Bloc、Cubit、Repository 或 provider contract。后续 Repository 可把
持久化 response 映射为自己的 domain，Data 无需导入有状态 application 类型；损坏文件也不会静默
变成空恢复会话。

## 2026-08-20 — 步骤 20 显式定义 debounce cancel 与 close flush

**问题。** 旧 persistence coordinator 持有 timer，但 `dispose()` 会丢弃待写 snapshot。把该 timer
原样留给后续 Cubit 会违反“debounced write 可取消且 close 时 flush”的 package contract。close-time
atomic write 也可能失败，既不能阻止 storage teardown，也不能作为未观察 timer error 消失。

**决策。** `ProjectSessionStore` 合并最后一份 scheduled response；对尚未开始的写提供
`cancelScheduledSave()`，但不打断已经开始的 atomic write。immediate save 会取消 pending debounce。
`close()` 先拒绝新操作，flush 最新 pending response，等待串行 write tail，始终关闭 storage，再传播
已捕获的 background、flush 或 close failure。

**影响。** close-time 数据不丢失，被替换的 snapshot 不落盘，写失败保持可观察。包级测试分别覆盖
timer 已启动后的 background failure，以及由 close-time flush 发起的失败。

## 2026-08-20 — 步骤 20 desktop apt 停滞在 job 上限前重试

**问题。** 步骤 20 首次 desktop run 已有 8/9 matrix 成功，Linux development 却在 Ubuntu 系统包
安装阶段超过十二分钟没有进展；Flutter setup、依赖解析与项目构建均未开始，形态与步骤 18、19 已记录
的隔离 runner-side apt 延迟一致。

**决策。** 只取消仍运行的 matrix 并 rerun failed jobs，不等待 30 分钟上限，也不重跑已有证据通过的
八个 matrix。workflow 保持不变：apt 延迟在不同 Linux variant 之间漂移，仍无项目代码失败特征。

**影响。** attempt 2 的 apt 约七分钟后继续并构建成功。步骤 20 的 zeta、desktop-build（9/9）、
OSV 与 license workflow 全绿，未修改源码或 CI 配置。

## 2026-08-20 — 步骤 21 以具体 storage/vendor topology 覆盖泛化 manifest

**问题。** 泛化的逐文件 manifest 把所有旧 usage data 文件映射到不存在的
`packages/usage_statistics_client`；步骤 21、topology 与 package API contract 却明确把 cache/index
IO 放入 `usage_statistics_storage_client`，把 Codex/Claude/Grok 原始 reader 留在各 vendor client。
旧 vendor scanner 合计约 2,600 行，也明显超出 placeholder package 预估。

**决策。** 服从更具体的架构契约，把工作拆成一个共享 storage increment 与三个独立门禁的 vendor
reader increment。不创建第四个共享 vendor client，不修改共享适配层或 Provider port。重复的 response
shape 仍由 vendor 自己拥有，避免某一方格式意外固化成跨 Provider contract。

**影响。** vendor pubspec 继续互相隔离；`usage_statistics_storage_client` 不依赖 vendor 或 provider
contract；后续 Repository 是唯一聚合四个 Data 输入的层。超出预估的实现量被显式拆分和验证，没有藏进
一个过大的 package change。

## 2026-08-20 — 步骤 21 将路径与损坏 index 视为可重建私有输入

**问题。** 旧 cache 持久化 source path 并接受多个历史 shape；照搬会保留本地目录信息，还会混淆
current-schema corruption 与 cache miss。复核同时发现新 root index model 起初声称防御性不可变，实际
仍保留调用方可修改的 partition map。

**决策。** 只接受 root schema v4。provider 自有 JSON-safe partition 由串行、原子的
`UsagePartitionStore` 保存；malformed、不支持或语义非法的派生数据原子写为空 v4 index 后返回 miss。
cache key 使用规范化 source identifier 的 hash，绝不持久化 source path。root partition map 与嵌套
payload 都防御性复制并冻结；storage failure 原样传播，不伪装成成功清理。

**影响。** corruption 可恢复但不会冒充有效 cache；index 不再泄漏路径；并发写不会丢掉其他 provider
partition；构造后外部 mutation 无法改变编码状态。回归测试覆盖 corruption、不可变性、失败后的队列
恢复、1,000 次并发 insert 与真实 atomic file IO。

## 2026-08-20 — 步骤 21 复用 vendor history 语义但不暴露私有 Provider 代码

**问题。** Claude 与 Grok 已有适合窄 usage 投影的 package-owned history reader/parser；Codex 对应
parser 是 Provider 实现的私有 `part`，公开它会扩大 Provider surface。Grok 初测还发现损坏的百分号
编码项目目录会使 `Uri.decodeComponent` 抛 `ArgumentError`，另一个 fallback 断言误把 project name
顺序当成契约，而实际契约是 source path 确定性排序。

**决策。** Claude/Grok 从已有 vendor history model 投影 usage；Codex 新增独立 vendor reader，只理解
session metadata、turn lifecycle/context 与 token-count record，并保留 exact last-usage、累计差分、
重复 signature、计数器重置和 fork replay suppression。不得暴露 prompt、response、error body 或 raw
frame。损坏 Grok 目录名原样保留；file read 可注入以测试 summary IO failure；fallback value 使用无序
断言，不覆盖 source-path 排序。所有 reader 使用半开区间与 cooperative cancellation。

**影响。** 未修改共享或 Provider port。大扫描可在 discovery、parse、load 与 stat 边界取消；损坏源
只计数不泄漏内容；每个 vendor 继续独占自己的落盘格式。兼容性缺陷由回归测试覆盖，没有用 coverage
exclude 隐藏。

## 2026-08-20 — 步骤 21 最终门禁排除生成的 package asset

**问题。** analyze/format 首次预检递归搜索全部 `pubspec.yaml`，因此把 Flutter 生成的
`packages/app_ui/build/unit_test_assets/.../shadcn_flutter` 副本也计入，得到 28 roots。它没有在
workspace 中声明，并携带上游 lint info。

**决策。** 不修改、不计数生成 asset。权威 root 集合只由 root workspace、直接 `packages/*` 成员和
显式嵌套的 `packages/app_ui/widgetbook` 组成，并重启正式 analyze/format 计数。

**影响。** 正式结果为 27/27 真实 roots，383 个 source/test/tool Dart files 且 format 零改动；生成
副本保持原样，后续门禁计数不会被它放大。

## 2026-08-20 — 步骤 21 在写入边界强制 cache 隐私

**问题。** 提交前 static-security 复核发现，`usageSourceId(path)` 虽生成无路径 key，
`UsageScanCacheEntry` 却仍接受任意字符串；后续 caller 仍可能直接传原始路径并持久化，违背文档隐私
契约。任意 fingerprint 字符串与非法 cache schema 也要到更晚操作才失败。

**决策。** 所有持久化 source id 必须严格为 16 位小写 FNV-1a，fingerprint 必须为数字
`size:mtime`。cache source key 与 schema version 在构造时校验，read/invalidate 输入也校验；helper
拒绝空 source path 与负 file size；model 与 decode 同时拒绝空白/带首尾空格的 partition key。

**影响。** 路径保密从约定升级为入口强制，非法 cache 配置立即失败，落盘的非法 identifier 仍触发
clear/recompute；加固后 storage 包人工 coverage 继续为 100%（222 / 222）。

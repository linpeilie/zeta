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

## 2026-08-20 — 步骤 22 显式解决异步配置与同步 bundle 契约

**问题。** 文档构造函数接收异步 `ProviderConfigStore`，同一公共契约却要求同步
`configSnapshot` 与 `bundleFor`，没有定义初始化。磁盘读取完成前创建默认 bundle 可能启动错误命令，
然后 dispose 已交给消费者的 runtime。旧 controller 用可变默认值避免崩溃，但没有无竞态的 ready 边界。
API 示例还把已导出的 `AgentModelCatalogCacheStore` 端口缩写成了不存在的
`ModelCatalogCacheStore`。

**决策。** 构造时立即启动 config read，并增加 `ready` Future。异步目录 API 自动等待；同步
`bundleFor` 在完成前返回 typed `repository_not_ready` failure。clean install 的空 response 只在内存
展开为既有 Codex/Grok defaults，不主动写盘。`persistDefaultModel` 解释为显式持久化命令：Repository
保存 caller 提交的值，但不持有当前 model、permission、mode、loading 或 retry UI 状态。文档改用
既有 cache port 的真实名称；不修改共享 contract 或 Provider port。

**影响。** bootstrap 获得确定的 await 点，不会泄漏临时 process；snapshot 只发布成功加载或写入的
外部数据，文档要求的同步 API 保持不变。

## 2026-08-20 — 步骤 22 串行化全局目录所有权并保留诊断 cause

**问题。** 直接包装 port 会重复 provider-local cache 生命周期，并让并发首次读取或 full-cache write
竞争。某 Provider 的迟到写可能覆盖包含另一 Provider 新 snapshot 的文件。只映射为
`AgentProviderFailure` 还会丢失 sanitized logging 所需的原 cause 与 stack。

**决策。** 使用一个构造时启动的 cache-read Future；model refresh 按 canonical provider id 与不含
secret 的 config fingerprint single-flight；完整 cache snapshot 进入串行写队列。fresh 为 1 小时；
refresh 失败时 last-known-good 最多保留 7 天。空 refresh 不替换也不持久化目录，cache read/write
failure 作为 best effort 记录。Repository 调用抛 `AgentProviderRepositoryException`，同时携带中立
failure 与原 cause/stack；其字符串和 `AppLogger` 输出保持不含内容/经清洗。
`runtime.initialize()` 返回 Future 前的同步抛错，以及持久化成功后的 `updateModelSelection()` failure
都进入同一翻译边界；后者不会回滚已经成功的原子 config write。

**影响。** 跨 Provider 的 global runtime/catalog 所有权无竞态；cache 不会因乱序完成倒退；application
获得稳定 failure code 的同时保留诊断证据。回归测试覆盖 cache-read 与跨 Provider write 两类竞争。

## 2026-08-20 — 步骤 22 最终门禁重试既有 Claude keychain 时序 flake

**问题。** 26-root 随机门禁首次只在 seed `2572682378` 下失败于既有 Claude keychain process-runner
测试，其余 Claude 测试继续成功。已批准的 VGC-only 测试策略无法做 named-test 诊断，因为
`very_good test` 既不接受 `--plain-name`，也不接受位置型 test path；尝试命令在任何测试启动前即被
参数解析拒绝。

**决策。** 不绕过既定 runner 改用 `flutter test`，不放宽 timeout，也不修改无关 Claude 代码。用
完全相同的 100% coverage VGC 门禁和新随机种子重跑整个 Claude 包，再从下一 root 继续被中断的
workspace 序列。

**影响。** seed `1621963295` 未改代码即通过全部 270 个 Claude tests 与 3,037 / 3,037 lines。
继续后的 workspace 门禁完成 26/26 roots，并在 Repository 最终加固重跑后达到 14,552 / 14,552
lines；该事件继续归类为已记录的
Windows child-process 时序 flake，而非步骤 22 回归。

## 2026-08-20 — 步骤 22/23 门禁工具使用权威 root 与原生命令边界

**问题。** 在一次 Windows 调用中格式化全部权威 Dart 文件超过了命令行长度上限；随后把完整 SHA
嵌入 PowerShell 到 `gh --jq` 的表达式也被参数解析拒绝。步骤 23 开始时还误把 `format`、`analyze`
当作 Very Good CLI 顶层命令，而这些命令不存在；两次被拒调用都没有执行源码操作。

**决策。** 保持已批准的 runner 分工：Dart 直接负责 analyze/format，workspace 权威文件集合按有界
chunk 处理；所有测试继续使用 `very_good test`。Actions 使用
`gh run list --commit <full-sha>` 查询，再在嵌套 `--jq` shell quoting 之外解析 JSON。不增加
`--check-ignore`，也不改用 `flutter test` 绕过 VGC。

**影响。** 工具参数上限不会改变实际检查文件集合；被拒命令不会修改 workspace；步骤 22 commit
`8e5485c` 的四个 workflow 均已确认成功。
步骤 23 首次人工汇总误读了 workspace root 的旧 LCOV，得到 294 / 294；权威 package-local LCOV 为
1,096 / 1,096。更正的只有报告计数，包级 100% 门禁结果没有变化。
最终 analyze 还发现 `app_ui/widgetbook` 一个既有的依赖字母序 info；仅机械调整顺序，不修改版本或
topology，隔离重跑后无诊断。
生命周期加固后，一段组合 analyze/test shell 没有在 analyze 发现 nullable promotion 错误时短路，导致
VGC 预期地进入编译失败但没有运行业务测试。局部值已改为显式非空，后续组合门禁在任一 preflight
非零时立即停止；最终包级证据以 1,121 / 1,121 为准。
首次紧凑版 final-analyze 脚本只枚举 `packages/` 的直接子目录，因此报告 26 roots 并漏掉嵌套的
`app_ui/widgetbook`。权威枚举已改为从所有受控 `pubspec.yaml` 推导 root；替代重跑 27 / 27 全部通过。
test root 仍为 26，因为嵌套 widgetbook 没有 test 目录。

## 2026-08-20 — 步骤 23 服从已完成 history/config 契约而非不存在的类型

**问题。** 步骤 23 构造函数草案写了 `AgentHistoryClient` 和 `TurnContextStore`；但步骤 15 有意只导出
`HistoryReplayInput` 与 `mergeHistoryInputs`，步骤 17 导出的是 `AgentTurnContextStore`。新增草案中的
object 会重复已经验收的数据边界。

**决策。** 注入既有 `AgentTurnContextStore` 与可选、由 conversation package 自己拥有的中立
`HistoryReplayInput` factory。Provider 自有 typed history 通过现有 `bundle.threadCatalog` 进入；通用
input 使用步骤 15 merge function。`ConversationKey` 与 timeline aggregate 暂留本 Repository package，
因为当前没有共享 consumer 要求修改 Provider contract。

**影响。** 实现原样使用已经完成的下层契约，不修改共享 adapter 或 Provider port，并保持 vendor parser
所有权；中英文 API 草案已改为可执行签名。

## 2026-08-20 — 步骤 23 租用借入 bundle，并对未绑定 identity fail-closed

**问题。** 步骤 22 拥有并 dispose 稳定 global bundle，旧 conversation registry 则拥有自己创建的
runtime；复制旧所有权会让两个 Repository dispose 同一 runtime。步骤 23 初测还发现，无 session 的
draft 因没有 expected thread id 可比较，错误接收了一条 thread-scoped status。

**决策。** bundle 视为借入资源。conversation registry 追踪 identity lease count 与单调 generation，
但只取消自己的 event pipeline、释放 lease 并 best-effort unsubscribe；runtime 最终 dispose 继续归
步骤 22。在 draft 收到 `AgentSessionStartedEvent` 前，拒绝所有携带 session/thread identity 的事件；
绑定后要求 session/thread 精确一致，turn 必须已知或正 active。只合并规范化 delta/snapshot key；其他
事件都是顺序 barrier，queue dispatch 时再次检查 generation。

**影响。** close/open race 不会产生 ghost update 或 double dispose；三类安全响应保持独立 pending
registry 与方法；event storm 保持 FIFO barrier 顺序；失败使用 typed code，原 cause/stack 只进入
sanitized logging。error、deprecation 与 reroute 的 timeline record 只保留不含内容的 typed signal，
不保存 Provider raw event。
当前 event stream 自然结束时会发布 typed conversation failure；start/resume/send 返回的每个
session/turn 在进入 aggregate 前都会再次校验 identity。

## 2026-08-20 — 步骤 24 在 Data 边界统一 management identity

**问题。** 已完成的 management Data client 在 Claude detect response 中返回 `claude-code`，但共享
Provider contract、持久化配置和全部 runtime route 使用 `claude_code`。Repository 若直接复制 response id，
会静默产生第二套 identity。同一 Data 实现已经包含所需的纯 JSON/TOML 语法 validator，但 public barrel
没有导出它，迫使步骤 24 重复 parser 或导入 package `src/`。

**决策。** 三个具体 Data source 全部改用既有 Provider-contract id 常量，Claude Data test 同步改为
canonical value；management-client barrel 只新增导出现有纯 validator。Repository 用 canonical id 作为
client key，并拒绝 detect response id 与路由不一致的结果。对外验证仍由 Repository 以 typed 同步 domain
result 暴露；Widget 以后只能通过 Bloc event 到达该方法。

**影响。** 从持久化、Data 到 Repository 只有一套 Provider identity，跨 Provider 错误路由 fail closed，
且没有复制 parser 实现。这是窄范围 Data API 修正；未修改共享 adapter、Provider port、runtime protocol、
配置 schema 或 vendor parser。management client 继续独立全绿：35 tests、329 / 329 covered lines。

## 2026-08-20 — 步骤 24 保持 management 编排无状态

**问题。** 旧 controller 把外部 detect/config/log 调用与 selected Agent、progress、loading、runtime、
editor、log-view、本地化错误和检测缓存状态混在一起，还把 detection summary 写回全局 Provider config。
复制这些策略会同时违反步骤 24 的禁止状态清单和步骤 31 的明确 Bloc 归属；另一方面，新 config store
在 clean install 合法为空。

**决策。** Repository 只持有不可变 client registry 与注入的 `ProviderConfigStore`。需要 config 的操作
每次重新解析；store 为空时只在内存使用三个 contract defaults，不写盘。显式 detection path 跳过 config
读取；否则优先非空 `cliPath`，再回落 command。不持久化 detection summary。拒绝重复、非 canonical、
kind 错配、缺失与空 command 配置。redacted logs 按 path 串行合并，以 timestamp/id 排序并执行单一全局
行数上限。异常转换为 typed safe failure，cause/stack 只保留给 sanitized diagnostics。

**影响。** 步骤 31 可独占 cancellation、selection、progress、editor validation state、runtime composition
与本地化文案，不会和 Repository 形成双状态源。clean install 保持可用，失败或部分操作不会修改全局
配置，输出顺序与资源上限确定。Repository 有 28 个随机顺序测试，覆盖 290 / 290 手写行。

## 2026-08-20 — 步骤 25 Settings 采用单文档提交语义

**问题。** general v3 与 appearance v1 是两个独立文件；把一次设置更新伪装成跨文件事务会让内存快照
在部分写失败时失真。旧 controller 还把系统字体展示选项、当前选择和提示状态混在持久化路径中。

**决策。** Repository 只接受 `GeneralSettingsUpdate` 或 `AppearanceSettingsUpdate` 单文档 replacement；
对应 store 写成功后才递增 revision 并发布完整 snapshot。字体目录经已有 `SystemFontCatalogApi` 映射为
纯 domain family，语言解析器只接收字符串 locale components。未修改 desktop port，也不保存 UI option、
loading 或错误提示。

**影响。** 失败写不会成为已生效设置，两个 schema 的真实原子边界得到保留。Settings Repository 以
23 tests、262 / 262 covered lines 独立全绿。

## 2026-08-20 — 步骤 25 修正按需目录的祖先 ignore 语义

**问题。** 步骤 19 的递归扫描会携带 root→current `.gitignore`，但 `readDirectory` 只读取目标目录文档；
展开嵌套目录会漏掉 root/ancestor 规则。迁入的旧 matcher 还把 `**/cache/**` 追加为多余层级，深层路径
无法命中。

**决策。** 不改 `WorkspaceScanner`/`GitignoreReader` 签名；仅在 Data 实现内为按需读取构造完整祖先
document chain，并在 Repository 纯 matcher 中补上 leading-`**/` 的完整相对路径 glob。Repository 持有
不可变 index 与共享 watch，按 root 串行扫描；expanded、selected、loading、progress 和 debounce 编排
继续归 WorkspaceCubit。

**影响。** 递归索引与惰性树读取使用一致 ignore 语义。Workspace Repository 17 tests、330 / 330，
修正后的 client 30 tests、255 / 255，均独立 100%；端口和共享适配层未变化。

## 2026-08-20 — 步骤 25 Project Session 统一聚合游标

**问题。** 旧 project-threads controller 同时持有搜索/选择/加载状态与跨 Provider 拉取、去重、排序、分页；
Provider 原生 cursor 不能直接作为合并目录的全局 cursor。session schema v4 又必须完整往返，不能只迁导航
字段。

**决策。** Repository 完整映射 schema v4，并在 Data save 成功后才发布 snapshot。注入不可变的
`providerId → AgentThreadCatalogPort` registry，每个 Provider 最多收集 50 条，按 provider 内 id 去重，
再按 recency/provider/id 稳定合并，以 `agg:<offset>` 分页。部分 Provider 失败随页面返回不含内容的 typed
evidence；身份错配或重复 cursor 作为 invalid Data 隔离。搜索词、选择、加载和失败展示留给 Bloc。

**影响。** Provider cursor 不越过聚合边界，部分成功可用且顺序可复现；没有修改共享 thread port。
Project Session Repository 以 17 tests、275 / 275 covered lines 独立全绿。

## 2026-08-20 — 步骤 25 Windows keychain 测试回收抖动

**问题。** 最终逐包 matrix 第一次运行 `claude_code_client` 时，keychain runner 的 success/timeout/start
failure 断言已执行，但 Windows 删除临时目录时仍有子进程短暂持有句柄，报 `PathAccessException`
（errno 32）。当前 Very Good CLI 1.4.0 不接受 file path 或 `--plain-name`，因此不能在坚持统一 runner
的同时只跑 named test。

**决策。** 不绕过 `very_good test`、不修改未触及的 Claude 源码，也不放宽 timeout/coverage。直接用新
random seed 重跑 Claude 全包，随后从下一个 root 继续 matrix；将 CLI 过滤能力限制一并记录。

**影响。** Claude 重跑 270 tests、100% 通过；最终 27/27 roots、16,840 / 16,840 covered lines 与
Bloc lint 405 files / 0 issues 全绿。该事件判定为 Windows 临时句柄回收竞争，不构成步骤 25 产品回归。

## 2026-08-20 — 步骤 26 保持 vendor usage shape 私有并缓存 report 投影

**问题。** 三个已完成 vendor reader 有意导出不同 response shape，共享 usage store 也只接受 Provider 自有
JSON partition；新增通用 Data model 或 Provider port 会违背步骤 21。cache entry 只按文件 fingerprint，
不含 query identity；若直接用于另一时间窗会返回不完整记录。实际 aggregation、cache codec、部分失败与
取消语义的工作量也明显超过最初 placeholder 估算。

**决策。** 每种 vendor response 只在 `usage_statistics_repository` 内映射成不含内容的 domain record，
cache 只存 Repository 自有投影。每个 entry 同时保存半开 query 边界，fingerprint 与两端边界都相同时才
命中；force refresh、时间窗变化、payload 损坏或 storage 失败都从当前 scan 重建。三方并行执行，未知
Provider 失败转为 typed warning 并与其它结果隔离；协作取消显式翻译，Codex replay sample 去重，quota
能力逐 Provider 独立收敛。依据用户已授权的代理决策接受本步骤增量扩大，不以削弱契约或修改共享端口换取
更小改动。

**影响。** filter selection/loading 仍归 Bloc，源文件路径继续由既有 storage boundary 哈希；单个 vendor
或 cache 损坏不会清除其它结果，也没有创建跨 vendor Data contract；跨源 fork replay 由聚合边界使用
Provider sample key 去重。该包独立以 13 个随机顺序测试、348 / 348 covered lines 全绿。

## 2026-08-20 — 步骤 26 用 Repository facade 暴露桌面能力

**问题。** 如果 Repository 直接透传 `desktop_platform_api` object，后续 Bloc 仍会依赖 Data port；若把
通知启用条件或本地化文案放进 notification Repository，又会产生 Repository→Repository 依赖或第二份
settings 状态源。

**决策。** directory/file picker、clipboard、file manager、window lifecycle/command 与 native menu
全部包装为纯 Dart Repository 方法/facade，并统一转换为不含内容的 typed failure。notification Repository
只接受 title/body 已本地化的 `NotificationRequest`，校验非负 badge，再转发 notification/attention；它不
读取 settings，两个包也不依赖任何其它 Repository。

**影响。** 后续 Bloc 只消费 domain boundary，无需 import platform API；具体 adapter 仍留在
`lib/app/platform`，presentation policy 不产生双重 owner。Notifications 6 个随机顺序测试、21 / 21 行，
Desktop Platform 7 个、44 / 44 行，均独立全绿。

## 2026-08-20 — 步骤 26 重试已知 Claude keychain 回收竞态

**问题。** 首轮权威矩阵再次完成 keychain runner 全部断言，但 Windows 删除临时目录时失败；失败文件与
handle-sharing 错误和步骤 25 完全一致。Claude 之前的 root 及步骤 26 三包隔离门禁均已全绿。

**决策。** 保持统一 `very_good test` runner、timeout、随机顺序与覆盖阈值；本迁移增量不修改无关 Claude
production/test 代码。使用新 seed 重跑完整 Claude package，通过后从 Codex root 恢复权威矩阵，不丢弃
已经证明成功的 roots。

**影响。** 未改代码的 Claude 重跑全部 270 tests 与 100% coverage 通过；恢复后的矩阵最终完成 27/27。
该事件仍归类为已记录的 Windows cleanup race，而不是步骤 26 回归。

## 2026-08-20 — 步骤 27 拆成五个独立门禁的 UI 增量

**问题。** 迁移清单把 `app_ui` 描述为一个步骤，但旧 `ui/core` 实际包含 48 个 Dart 文件、约一万行，
横跨主题 token、基础控件、WindowFrame、Workbench 布局与虚拟滚动。将该体量作为一次不可分割改动，
明显超过占位估算，也难以隔离回归。

**决策。** 保持步骤 27 契约不变，将实现拆成五个可回滚增量：27A token/theme、27B 基础组件与
WindowFrame 纯 UI 部分、27C Workbench 原语、27D 虚拟滚动、27E 无障碍/golden 总验收。每个增量先做
聚焦测试与本地门禁，最后再执行步骤 27 的 workspace 总矩阵；不修改共享 adapter 或 Provider port。

**影响。** 用户目标与出口标准不变，但 review、回滚、coverage 与失败归因被限制在可控范围内。在五个
增量及最终远端门禁全部通过前，步骤 27 始终保持进行中状态。

## 2026-08-20 — 步骤 27A 新增语义排版且不破坏 scaffold API

**问题。** VGV scaffold 已公开并完整测试 `AppTextStyles`，而旧桌面 UI 需要更丰富、感知语义颜色的
排版表。若在 token 增量直接替换 scaffold 类型，会在其计划增量之前迫使无关 Widgetbook 与组件一起改动。

**决策。** 将迁移后的 `AppTypography` 新增为 `ThemeExtension`，同时暂时保留 `AppTextStyles` 作为公开
兼容 extension。`AppTheme` 同时安装两者，所有新迁组件统一使用 `AppTypography`。Material 与 shadcn
投影、语义颜色、间距、尺寸、圆角、效果与动效均来自同一套 extension-backed 真源；shadcn import 始终
限定为 `as sf`。

**影响。** 既有 VGV consumer 保持源码兼容，后续 UI 增量可以逐组件迁移。步骤 27A 的 app_ui analyze、
86 个随机顺序测试及手写 coverage 100% 全绿；Widgetbook analyze 与 root 72-test 架构门禁也通过，且没有
任何禁止的下层依赖 import。

## 2026-08-20 — 步骤 27B 将图片与窗口副作用改为 app 注入

**问题。** 旧图片预览直接执行 `dart:io` 文件读取并从 `AppLocalizations` 获取文案；旧 WindowFrame 直接
调用 `window_manager`、拥有 Zeta SVG asset、读取最大化状态并内嵌英文窗口按钮文案。照搬实现虽能保留
视觉，却会违反文档规定的 `app_ui` 纯 UI 边界。

**决策。** `IdeImageThumbnail` 与 `showIdeImagePreview` 接受 `ImageProvider` 以及全部可见/语义文案，文件
校验、读取失败留给后续 app adapter。`WindowFrame` 接受视觉平台、app-owned Logo widget、本地化标签、
拖拽区 wrapper、窗口状态与最小化/最大化/还原/关闭回调；包内不出现平台通道、应用 asset 路径、
Repository、Data client 或 `AppLocalizations` import。紧凑控件统一守住 WCAG 2.2 AA 24 dp 命中下限，
纯图标 action 强制可访问名称，进度/Toast 使用 live region，resize handle 提供方向键替代，动效尊重系统
reduce-motion。

**影响。** 共享包只拥有确定性渲染与交互，OS 副作用和本地化文案由后续 bootstrap/presentation 组合；
全部 API 无需 `window_manager` 或文件系统 fake 即可跨主机测试，且没有修改 Provider port 或共享领域 adapter。

## 2026-08-20 — 步骤 27B 将 shadcn 0.0.53 Overlay 限制封装在 UI 包内

**问题。** 旧项目已有针对 `shadcn_flutter 0.0.53` anchor-follow 变换失败的兼容层。组件测试还发现同版本
在主动关闭 Toast 后仍保留自动关闭 timer，且测试 Overlay 可能把 Toast paint 放到合成 viewport 之外。
删除兼容层会重新引入桌面 MouseTracker 故障；直接修改依赖又会把本迁移扩成 vendor 变更。

**决策。** 按原职责迁移 `IdeStablePopoverOverlayHandler`：委托全部 Overlay 生命周期，仅在打开及 live
configuration 更新时强制关闭 anchor following。Popover/Toast wrapper 对正常 consumer 隐藏第三方句柄。
Toast 测试使用短自动关闭时钟并推进 fake clock，以公开 overlay 状态为断言，不修改 shadcn 内部；Toast
语义节点改为 explicit children，使 live message 与本地化关闭 action 保持独立。

**影响。** 已知 vendor 行为被隔离并完整覆盖，无 Provider port 或 vendored source 改动。Widgetbook 现从
`AppTheme` 同时应用 Material 与 shadcn 投影，并为生成的组件 gallery 显式声明相同 shadcn 版本。步骤 27B
最终 app_ui analyze 零问题、192 个随机顺序测试、手写 coverage 100%；Widgetbook analyze 同样全绿。

## 2026-08-20 — 步骤 27B 的 Widgetbook 依赖未新增许可证类别

**问题。** Widgetbook 内应用 shadcn 投影需要显式声明 `shadcn_flutter`。依赖清单发生变化时必须基于完整
解析树审计，不能因 app_ui 已使用该包或凭包名推断安全。

**决策。** 从 Pub workspace root 使用 Very Good CLI 分别扫描 direct-main、direct-dev 与 transitive
依赖。当前会话没有 skill 指定的 MCP scanner，已安装 CLI 也不再接受旧 `--licenses` 参数，因此按当前
`--reporter text` 接口扫描三个解析集合；本 UI 增量不修改无关依赖。

**影响。** 28 个 direct-main 与 10 个 direct-dev 全为 MIT/BSD/Apache；`shadcn_flutter` 是
BSD-3-Clause，且没有增加新的解析包。138 个 transitive 的完整扫描仍保留两个既有人工复核项：`dbus`
（MPL-2.0，medium/弱 copyleft）与 `pubspec_lock_parse`（unknown，high/需人工复核）。二者均非 27B 引入，
继续作为显式供应链观察项，而不被静默判定为合规。

## 2026-08-20 — 步骤 27C 注入 Workbench 文案并保持布局状态由调用方持有

**问题。** 旧 Workbench 原语整体属于纯 UI，但 `IdeWorkbenchScaffold` 会直接从 `AppLocalizations`
读取 Overlay 关闭标签；照搬会违反 `app_ui` 契约。本增量还覆盖响应式 Rail/Pane、模态 Overlay、保留式
页面状态、紧凑行、指标条、Surface 与页面组合，这些行为必须继续与 Bloc、Repository、Provider port 解耦。

**决策。** 将非空 `closeOverlaySemanticLabel` 设为必填构造参数；Overlay 可见性、Pane 宽度、关闭动作与
焦点恢复继续由调用方持有。其余 Workbench 原语按“一文件一公开组件”、const constructor、公开 Dartdoc、
barrel export、ThemeExtension token 迁移。非交互指标/数据行不再声明 button role；装饰分隔线从语义树排除；
页面与分组标题声明 heading；模态 Overlay 保留本地化 scrim action、Esc 关闭和触发器焦点恢复。不修改共享
adapter 或 Provider port。

**影响。** `app_ui` 仍不依赖 `AppLocalizations`、应用 asset、IO、Repository 或 Data client；响应式
Workbench 已加入 Widgetbook。步骤 27C 的 app_ui analyze、215 个随机顺序测试与手写 coverage 100% 全绿；
Widgetbook analyze 以及 root 72-test/100%-coverage 架构门禁同样通过。

## 2026-08-20 — 步骤 27C 验证区分测试宿主问题与产品行为

**问题。** 首轮响应式测试在固定 800 px surface 的 helper 内请求 900–1400 px widget，名义 wide/medium
场景实际走了 compact；保留页探针又与 PageView wrapper 复用了相同 key，导致 State 查找歧义。修正后覆盖率
达到 99.77%，唯一结构缺口是第二次 index clamp；由于 `didUpdateWidget` 会在每次非空 build 前解析 index，
该分支不可达。当前 build runner 还提示 `--delete-conflicting-outputs` 已废弃并忽略该参数。

**决策。** 为共享测试 pump 增加可选 surface size，给探针独立 key，并断言真实响应式几何。删除不可达的
重复 clamp，不降低覆盖率，也不编造破坏 widget 状态不变量的测试。继续使用当前 build-runner 行为；生成已
正常完成并刷新 Widgetbook directory 输出。

**影响。** 最终测试真实覆盖 wide/medium/compact、键盘、焦点、身份保留、RTL-safe inset 与语义路径，
且没有削弱 100% 门禁。生产行为只删除死防御代码，未改变任何包边界或公开 port。

## 2026-08-20 — 步骤 27D 保持虚拟滚动为纯 UI/Render 基础设施

**问题。** 旧虚拟化目录约 2,180 行生产代码和 2,133 行测试。Extent index、RenderSliver、列表控制器与
滚动协调器符合 `app_ui` 边界，但旧 scrollbar 直接读取 `AppLocalizations`，一个文件还同时公开 scrollbar、
滚到底部按钮和组合 Shell。旧 Shell 的 `coordinator` 参数从未被读取；照搬会保留误导 API，并把本地化依赖
带入共享 UI 包。

**决策。** 迁移纯算法与 render 基础设施；将 scrollbar、滚到底部按钮和 Shell 拆成三个文件，并要求调用方
传入 scrollbar、action 与可见状态文案。Shell 不再携带未使用的 coordinator 字段，列表是否显示按钮仍由
上层状态决定；另提供只接受 Flutter notification、controller 与通用 coordinator 的用户滚动桥接函数。
样式、圆角、间距和动效全部读取 ThemeExtension，定位使用 `PositionedDirectional`，reduce-motion 由主题
动效解析。没有修改共享 adapter、Repository、Data client 或 Provider port。

**影响。** app_ui 现在拥有稳定 ID 高度索引、锚点修正、动态高度 RenderSliver、平滑桌面滚轮、follow/free
协调器与可访问滚动组合；Widgetbook 新增 200 项动态会话示例。27D 的 app_ui analyze 零问题、284 个随机
顺序测试和手写 coverage 100% 全绿；Widgetbook analyze 同样全绿。

## 2026-08-20 — 步骤 27D 用不变量审计收敛旧代码覆盖缺口

**问题。** 旧实现迁入 VGV lint 后先出现 38 个风格问题；`dart fix --apply` 机械修复其中 15 个，剩余为
级联、参数赋值、公开文档和导入边界。旧测试迁入后行为全部通过，但新包首次完整覆盖率只有 96.75%。缺口
包含真实的 driver 生命周期/通知桥接契约，也包含由 Fenwick lower-bound、非空索引必有 epoch、layout 前置
garbage collection 等不变量保证不可达的重复 fallback。反向 sliver 的错误详情位于 debug-only assert 内，
把非法 render tree 持续泵入测试会反复触发 layout exception。

**决策。** 保留统一 `very_good test`、随机顺序和 100% 阈值。为 value equality、pending sequence、anchor
fallback、driver attached/detached、默认 frame 调度、动画 offset、用户通知桥接、平滑滚动 correction、空数据、
controller 替换与缺失 delegate child 增加契约测试。删除可证明不可达的 epoch/index/trailing-garbage fallback；
仅对 debug-only 非法方向诊断块使用局部 coverage ignore，并保留运行时 assert，不扩大文件/包排除范围。

**影响。** 覆盖率从 96.75% 提升到 100%，且分母仍包含全部虚拟化生产文件。清理只移除与既有不变量重复的
死防御路径；有效布局、滚动状态机、公开组件行为及包边界均未改变。

## 2026-08-20 — 步骤 27E 用可执行验收关闭 WCAG 2.2 AA 缺口

**问题。** 总验收首次把语义色、桌面控件和 200% 文字缩放放进同一套 AA 契约后，发现可点击
`IdeChip` 的命中高度只有 20 dp，低于 24 dp 下限；固定 44 dp 高的 `IdePageHeader` 在 200% 字号且含
副标题时向下溢出 21 px。两项都是 `app_ui` 内部布局缺口，不涉及共享 adapter 或 Provider port。

**决策。** 仅对带点击或删除动作的 Chip 使用 `AppMetrics.minimumInteractiveTarget` 扩展命中盒；静态标签
保持原视觉密度。页头的 `pageHeaderHeight` 改为最小高度，让内容在文字缩放时自然增高。增加明暗主题全部
内容表面的普通文字 4.5:1、焦点环 3:1、四类交互控件 24×24 dp、200% 字号和 reduce-motion 可执行验收；
既有组件测试继续证明 semantics、键盘/焦点、live region、方向键拖拽替代与 Overlay 焦点恢复。

**影响。** 两个真实 AA 缺口被生产代码修复，未放宽断言或 token。修复后新增 7 项 AA 验收全部通过，
app_ui 完整随机顺序测试增至 293 项，手写代码覆盖率保持 100%。

## 2026-08-20 — 步骤 27E 固定 golden 扫描、布局与 Very Good 执行语义

**问题。** Dart test 元数据解析器不接受 `@Tags([TestTag.golden])` 中的常量，只接受字符串字面量；首版
画廊还把 stretch Row 放进纵向 `SingleChildScrollView`，产生无限高度约束。修正并生成基线后又发现 Very
Good 的默认测试优化器合并套件时丢失文件级 tag，使普通 `--tags golden` 报告无匹配测试；更新 golden 的
命令因自动关闭优化而未暴露此问题。当前 Very Good CLI 也没有 `analyze` 子命令，首轮 Flutter analyze
另报告测试夹具 13 个 const 提示，`dart fix --apply` 合并为 8 项安全机械修复。

**决策。** 元数据保留解析器要求的 `@Tags(['golden'])`，并在测试体引用 `TestTag.golden`，兼顾真实 tag 与
工作流文件扫描。画廊在固定桌面画布内直接使用 token padding，不把 stretch 布局放进无界滚动轴。
golden job 显式传 `--no-optimization`，架构测试锁定该参数；package 声明 golden/perf/slow 三类 tag。
测试统一使用 `very_good test`，静态分析使用官方 `flutter analyze`。

**影响。** 明暗两张候选基准图由固定 760×560、device-pixel-ratio 1 的组件画廊产生并经目视检查；
非更新 golden 门禁在 Windows 连续三次随机顺序通过，不再出现“零测试”假绿。工作流调整只修复测试发现
语义，不改变生产依赖或架构边界；后续远端复验再决定 Linux 权威基线。

## 2026-08-20 — 步骤 27E 将 golden 从普通矩阵隔离并冻结渲染工具链

**问题。** 首次远端复验中，app_ui 普通 quality job 在 Ubuntu/Flutter 3.47.1 上执行了 Windows/Flutter
3.47.0 生成的 golden，两张图分别出现 0.95% 与 0.96% 的栅格差异，导致普通测试失败，专用 golden job
因依赖 quality 而被跳过。这证明前述三次通过只证明 Windows 本机稳定，不能称为 Linux 基线。当前安装的
Very Good CLI 也不提供顶层 `analyze` 子命令，静态分析不能经由该可执行文件运行。

**决策。** 普通 analyze/format/test/coverage 矩阵增加 `--exclude-tags golden`，视觉测试只由固定
Ubuntu 24.04 的专用 job 执行。该 job 单独钉死已批准的 Flutter 3.47.0，避免普通 `3.47.x` 补丁漂移改变
像素；失败时用 `actions/upload-artifact@v7` 保存 Flutter 生成的 failure feedback，供一次性提取权威 Ubuntu
基线。架构测试锁定隔离、版本和 artifact 三项配置。静态分析继续使用官方 `flutter analyze`，所有测试
门禁仍统一使用 `very_good test`。

**影响。** 行为/覆盖门禁与平台视觉门禁拥有互不重复的职责，普通矩阵不再被开发主机基线污染；golden
失败仍保持硬失败并留下可审计图像，不会因排除 tag 形成假绿。

**后续证据。** 首次隔离运行表明，Very Good 优化器在处理 `--exclude-tags golden` 时同样会丢失文件级
元数据：app_ui 普通 job 仍执行两项视觉测试并先于专用 job 失败。现将 `tags: TestTag.golden` 直接挂到每个
`testWidgets` 用例，同时保留供 Flutter 直接发现的字面量文件注解。单测级元数据可穿过优化过程，因此普通
job 可继续使用优化器，专用 job 的选择范围仍明确且可审计。

**最终证据。** 运行 32333147922 的 29 个普通 quality job 与 Ubuntu 专用 golden job 全部通过；专用 job
固定 Flutter 3.47.0 后，现有基准在 Ubuntu 24.04 上逐像素一致，因此无需替换图片。运行 32333147860 与
32333147698 也分别通过 OSV 扫描和三平台九项桌面构建。此前 0.95%/0.96% 差异由 Flutter 3.47.1 渲染漂移
引起，并非 Windows 与 Linux 平台必然不同。

## 2026-08-20 — 步骤 28 按实际临时本地化边界拆分

**问题。** 迁移计划点名四组旧 TextCatalog/Fallback 及 `ZetaTextCatalogs`，但 package 拆分后这些旧 app
文件已经不存在；当前代码实际残留的是 Codex、Claude、Grok 三个 client 内的临时英文目录。保留或改名会
同时违反“TextCatalog 为零”和“package 不编写 Zeta 可本地化 UI 文案”两项出口。删除它们需要定向调整共享
中立模型字段，属于真实 Provider 契约调整，而非计划字面描述的简单删文件。

**决策。** 将该偏差视为迁移过程形成的中间态，把步骤 28 拆为四个独立门禁增量：28A app 自有 shadcn
本地化、28B typed failure 穷尽映射、28C 冻结 Locale 的桌面通知文案、28D 用 typed 或 provider 原生中立数据
替换所有 provider 本地目录。`AppLocalizations` 不下沉 package，也不把英文 fallback 换名保留。

**28A 证据。** `ZetaShadcnLocalizations` 已迁至 `lib/l10n`，排在 app 与测试 delegate 链首位，并从现有
1,035-key en/zh ARB 读取全部 shadcn 文案。旧冒烟套件只抽查少量 override，首次使根覆盖率降至 62.93%；
现已增加完整表面契约测试，执行每个 getter、参数化 formatter 与 delegate 分支。Analyze 与 77 项随机顺序
根测试通过，手写覆盖率恢复 100%。

**28B 边界修正。** 原 source guard 仅允许 bootstrap、Bloc/Cubit 与 Page 引用 Repository，这与计划明确要求
`lib/l10n/failure_messages.dart` 映射 Repository code 直接冲突。现只把这个精确文件加入 allowlist，并由架构
配置测试锁定；其他 Presentation 路径不获得 Repository 权限。导入的 zh ARB 中 `agentRequestTimedOut` 现值
本来就是英文；不静默改写已批准的 1,035-key 基线，测试记录该值，并通过其他已翻译 mapping 证明双语行为。

**28B 覆盖率修正。** 首轮 79 项测试已执行新增 mapping 的全部 103/103 行，但覆盖率只报 4.23%；原因是
8 个 workspace package barrel 被导入后，`--report-on lib` 把数千行未执行的兄弟 package 源码也计入根 app
分母。各 package 已在独立矩阵 job 中执行自己的 100% 门禁，因此只从根聚合排除 `packages/**`，继续保留
generated source 排除；矩阵进入单个 package 工作目录时该 glob 不产生作用。不通过外部 `src` 导入操纵
instrumentation。修正后根目录 79 项随机顺序测试全部通过，覆盖率 100%。

**28C Locale 与边界决策。** bootstrap 通过 settings repository 既有 D1/D7 resolver 冻结首个系统 Locale：
支持的简体中文映射为 `zh-Hans`，英文、不支持语言及繁体中文变体回退英文。由同一个同步
`AppLocalizations` 实例创建 `FailureMessages` 和 `DesktopNotificationCopyResolver`，所有 flavor 都在
`runApp` 前接收同一 `AppDependencies`，`MaterialApp.locale` 固定为该值，保证进程生命周期内稳定。首版
resolver 直接返回 Repository `NotificationRequest`，被 source guard 正确拦截；现改用 app 自有 immutable
`DesktopNotificationCopy`，Step 29 Bloc 再在既有允许的 Repository 边界转换。没有修改 Repository port 或
共享 adapter。测试覆盖中英文全部 7 种 attention、Windows/POSIX/空项目路径、安全 body、稳定 tag、Linux
action 文案、同步/异步 bootstrap builder、observer/error hook，以及显式与平台 Locale 两条路径。Analyze
与 85 项随机顺序根测试均通过，覆盖率 100%。

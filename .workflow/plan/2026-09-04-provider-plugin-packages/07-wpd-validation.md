# WP-D 实施与验证记录

状态：已完成。日期：2026-09-05。基线：`8d8d6d6d`（WP-C 完成提交），开始时工作区干净。范围：management/usage 插件贡献化；WP-E 完整治理及 CI 拓扑重排仍未执行。

## 1. 交付与边界

- api 新增 management/usage 子库：管理模型、元数据、能力、文案目录、模型缓存窄端口；用量查询、记录、source、JSON-safe 分区、五成员文案端口及两种贡献。报表和页面时间窗仍留宿主。
- 4 个 management 文件和 8 个 usage 实现文件进入各自插件；9 个纯协议/数据测试文件随迁（74 个用例）。插件激活 handle 同时贡献 Provider、management 和 usage。
- 宿主在一次激活后校验每个插件自身的贡献数量、身份匹配及唯一性，再生成共享不可变快照。管理与用量各有可覆盖的 Riverpod 接缝；组合层不查询原始 registry。空表和重复身份抛错；未知用量类型保留 unsupported。
- Zeta v4 根分区 Store、模型目录仓库与应用状态继续由宿主拥有。插件只借用两个窄端口，不获得宿主 StorageService。
- `AgentDefinition` 静态厂商表及 `ManagedAgent` 厂商 factory 删除；管理定义由贡献提供。账户增强键与能力同源，连接测试确认按能力渲染。仅保留 WP-D §3.6 登记的 Claude 整卡安装指引 id 门。
- lib 对具体插件的 import/export 仅在 manifest；生产 barrel 删除 management/usage 所需的过渡实现出口。插件实现的根测试访问仍只经 `test/src/testing`。

## 2. 实测差异与处理

1. 计划中的独立 config/log/version/locator shim 已不在当前树中，未创建这些壳文件。
2. Grok 实际复用 Codex repository 的版本比较、配置遮挡和日志清洗。通用函数移至 sdk；两边共用的纯文本脱敏和显式环境 HOME 解析移至 foundation，保持单一实现。原宿主 `ZetaDataPaths` 不下沉。
3. 用量 fallback 的五条文本实际为中文，全部逐字保留；未把默认来源切换到 ARB。`usageProjectName` 的原默认“未知项目”也保留。当前 ARB 文案实现类名是 `App*TextCatalog`，其方法实现未改。
4. Grok 管理仓库原已使用 TOML，拆包后补声明原有 `toml: ^0.18.0`；不新增第三方版本。
5. 旧配置 codec 接缝本来会读取激活目录。因此测试助手在覆盖 bundle 时，还为未显式覆盖的 definition/management/usage 接缝提供静态测试声明；显式覆盖优先，生产装配不安装测试兜底。实测基线含 11 个匹配 bundle override 的文件（其中一个是结构守卫），不沿用计划中“12 个”的历史估计。
6. T0–T5 一次完成，不落地随后即删除的临时 app contribution 文件。计划伪代码的直接 registry 读取替换为激活后按所有者校验的快照，避免未激活、降级或缺项的静默成功。

## 3. 等价性审计

| 审计 | 结果 |
|---|---|
| 迁移实现主体 | 14 个文件（12 个插件实现 + 扫描缓存 + 脱敏基础函数）token 比较一致；仅归一化 import、类型/定义符号、能力表达和格式化尾逗号；Codex 文件抽出的共享助手及 HOME 解析另行 token 比较均一致 |
| 既有测试断言 | 全仓原有 `expect`/`expectLater` 11867 个，迁后同为 11867，缺失 0；仅规范化私有键测试样本符号及格式化尾逗号。新增 e2e/失败边界断言另计 |
| 管理元数据 | 原三个定义字面量逐字段搬移，含原 `isBeta` 默认值 |
| 持久化身份 | providerId、providerType、增强键值未变；provider 配置 codec/store 无 diff |
| 用量持久化 | 三个 partition codec 主体一致，根索引版本仍为 4；分区冻结/宽容解码实现随模型迁移 |
| 文案 | App 文本目录方法体无 diff，只改 import/implements；默认文案按实际旧文本保留 |
| 依赖和协议 | pubspec.lock、dart_test.yaml、pinned schema 无 diff |

新增假插件只存在于测试文件及测试注入，不修改 manifest。测试先激活真实三插件声明与第四个假插件，校验 definition/贡献目录；管理 UI 检测时仅替换前三家的 IO 工厂为内存实现，第四家沿原贡献工厂创建。验证第四张管理列表项、检测路由和用量 query 路由，同时覆盖空表、重复、身份不匹配、未激活、essential 失败、缺项、关闭后重新解析与接缝覆盖。该测试不拉起真实 CLI。

## 4. 验证

| 检查 | 结果 |
|---|---|
| 改动前完整基线 | 通过：根 1942 + 10 个内部包 907，共 2849 条 |
| 内部包独立分析/测试 | 通过：core 7、api 2、Claude 251、Codex 175、Grok 193、sdk 74、foundation 32、markdown 208、kernel 23、ui 16，共 981 条 |
| 假插件/页面/测试卫生定向回归 | 11 条通过 |
| 最终格式化/静态分析 | 格式化通过，flutter analyze 0 issue |
| 最终受影响测试 | 通过：根 1873 + 内部包 981，共 2854 条；选择器因文件迁移自动提升到全量，退出码 0 |
| 最终完整门禁 | 通过：根 1873 + 内部包 981，共 2854 条；独立运行退出码 0 |
| 根目录三个插件 Flutter 测试 | 619 条通过（Codex 175 / Grok 193 / Claude 251） |

首轮开发期受影响回归出现一份测试依赖符号未识别，另有新 e2e 未显式覆盖 bundle 的测试卫生问题；均已修正测试注入。新 e2e 的插件目录在 Widget 测试体内完成异步关闭，避免在假时钟退出后等待该时钟中的 Future。既有断言和测试卫生守卫没有放宽。

包级复验曾因 Dart 分析服务的统计上报网络请求取消而崩溃。已确认本机工具支持进程级 `DASH__SUPPRESS_ANALYTICS=true`，最终门禁使用该变量禁用工具统计上报；未改用户全局工具配置，也未调整测试并发或断言。两次最终门禁均完成 10 个内部包分析，未再出现统计上报崩溃。

本轮没有修改 wire adapter 或 pinned schema，未重复协议升级冒烟。WP-C 额外 Plan 冒烟缺失 `turn/plan/updated` 的待核验项仍按 06 号记录保留，不推断已通过。

## 5. 下一项

WP-D 已完成，下一项为 WP-E：完整隔离守卫、贡献完备性与新增 Provider 流程治理、CI package 矩阵和分片重排。现有架构说明按本轮边界同步，不将 WP-E 标为完成。

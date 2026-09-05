# WP-C 实施与验证记录

日期：2026-09-05。状态：**WP-C 已完成**。范围：三个 Provider 物理拆包、编译期 manifest、测试迁移与既有守卫路径同步。WP-D management/usage 贡献化及 WP-E 完整治理、CI 拓扑重排尚未执行。

## 1. 交付

| 项目 | 当前结果 |
|---|---|
| 独立插件 | `zeta_agent_provider_codex`、`zeta_agent_provider_grok`、`zeta_agent_provider_claude_code` |
| 实现搬迁 | 22 / 20 / 26 个既有生产文件，共 68 个；另按厂商拆分 static capabilities 与 native bundle 函数 |
| 宿主登记 | `lib/src/app/plugins/agent_provider_manifest.dart` 集中 definitions、settings、工厂与两个 Claude 宿主 store provider |
| 生命周期 | `ZetaPluginCatalog.builtIn` 只接收中立工厂列表；激活/关闭/fail-closed 顺序未变 |
| 根测试边界 | 身份常量经 manifest；实现类型经 `test/src/testing/agent_provider_implementations.dart` 和插件独立 testing barrel |
| 生产导出 | 插件入口 + manifest 宿主注入 + WP-C 已登记过渡调用点所需的精确 `show` 列表 |
| 旧包 | 聚合包及其 static capabilities 类、native bundle 聚合文件、built-in 登记文件删除 |
| 依赖 | 复用已有 toml（Codex）、crypto/unorm_dart（Claude）和 meta；无新第三方版本，锁文件无 diff |

## 2. 等价性审计

- 对 68 个已迁生产文件解析 Dart token，排除 import/export 指令和注释，规范化静态能力限定名及格式化尾逗号后逐文件比较：**68/68 实现主体一致**。
- D7：三个插件入口也包含在上述审计中，providerId、providerType、默认配置、metric label 与 enrichment key 未改值；`agent_provider_config_codec.dart`、`agent_provider_config_store.dart`、`pubspec.lock` 均无 diff。
- 对本次变更范围的原测试与迁后测试提取全部 `expect` / `expectLater`：原 **6230**，当前 **6235**，原断言缺失 **0**。归一化仅包含 catalog/能力符号改名、格式化尾逗号及日志捕获层的 `Level.trace` → `'trace'` 等价表示。新增 5 个断言来自 SDK 模式目录自测和 manifest 出口守卫。
- 43 个根协议测试/辅助 Dart 文件随包迁移；旧包内时间戳断言补入 Codex/Grok，跨插件的 3 条组装契约留根；六条 native bundle 用例按厂商拆分；宿主 codec 往返用例留根。
- 32 份迁移/复制的 fixture 与原仓库逐字节比较，无差异。
- 嵌套 Claude fixture 随包迁移；共享证据清单仍留根，各插件仅保存所需的脱敏 fixture 副本，以支持独立运行。未将 AI 生成内容冒充真实协议捕获，原 provenance 保持不变。

## 3. 验证

| 检查 | 结果 |
|---|---|
| 改动前完整基线 | 通过：根 2454 条 + 全部 8 个既有内部包；根阶段约 4m49s |
| Dart 格式化 | 通过 |
| 根 `flutter analyze` | 0 issue |
| 锁文件严格校验 | `flutter pub get --enforce-lockfile` 通过；沿用仓库既有源和锁定版本 |
| 受影响守卫定向回归 | 15 条通过；包含 manifest 正例/反例与生产调用点边界 |
| Codex 独立 Dart 测试 | 155 条通过 |
| Grok 独立 Dart 测试 | 177 条通过 |
| Claude Code 独立 Dart 测试 | 213 条通过 |
| SDK 独立测试 | 74 条通过 |
| 仓库根指定三个插件的 Flutter 测试 | 545 条通过（Codex 155 / Grok 177 / Claude 213），无跳过 |
| 包内逐包 Flutter 测试 | 三包均通过：Codex 155 / Grok 177 / Claude 213 |
| 最终 `bash tool/test_full.sh` | 退出码 0：根 1942 条 + 10 个内部包 907 条，共 **2849** 条全部通过（根阶段 4m40s） |
| 活动源码旧包引用 | `lib` / `packages` / `test` / `tool` / AGENTS / CLAUDE 零引用 |
| 补充审计 | `git diff --check` 通过；没有新增生产逻辑、权限策略或存储格式 |

本地环境曾把依赖源及 Riverpod 补丁版重新解析；已恢复锁文件并按原源严格校验，最终全量以原锁定版本执行。第一轮迁后全量发现两条结构守卫失配：包内测试被误算为生产调用点、manifest 身份再导出被误算为旧过渡 API。已分别限制生产扫描和新增精确常量出口验证，原断言不删减。

测试入口补查发现：原 fixture reader 使用当前目录，根目录运行 Claude 插件时会找不到资源。现通过中立 `ProviderTestFiles` 读取 runner 的 package config，定位所属包根；不修改全局当前目录，不依赖根测试目录副本。该实现兼容 Dart 与 Flutter（flutter_tester 不支持同步 Isolate 包 URI 解析）。根目录三插件 545 条测试已通过，包内入口也纳入最终全量验证。

## 4. 真实 CLI 冒烟

环境：Darwin / x86_64。CLI：**0.144.5**，安装在临时目录；未改写用户 CLI 配置。工作区为临时只读目录，沿用仓库脚本的最小非破坏性请求。记录仅保留版本、环境、模式和检查结果，不保存 prompt、回复、文件内容、原始错误、payload、thread/turn id 或 stderr 原文。

| 脚本/模式 | 结果 | 边界 |
|---|---|---|
| app-server，stable schema | **18 passed / 0 failed** | 首次继承本机默认模型时回合失败；改用该 CLI 的 `model/list` 公布的默认模型并显式只读后，原脚本完整通过 |
| Plan，experimental schema | **18 passed / 1 failed，待核验** | 两次均未观察到 `turn/plan/updated`；模式列表、Plan/Default 启动、Plan delta、用户提问回写、重启恢复与归档等其余 18 项通过。未修改脚本断言、未据此变更 Provider 适配逻辑 |

WP-C DoD 要求的 app-server 冒烟已通过。Plan 是本轮额外核验，不能把缺失事件推断为支持或通过；保留给后续协议验收排查。本轮不升级 pinned schema，不宣称验证了其他 OS/架构。

## 5. 后续任务

下一项仍为 **WP-D**。实现侧要消除已登记的 management/usage 过渡 import（含 usage source registry 的三个 type 常量导入），贡献化后再由 WP-E 启用最终隔离守卫与 CI 矩阵。当前前移的守卫/文档修改仅为保证物理拆包后已有约束继续有效，不代表 WP-E 已完成。

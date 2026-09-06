# WP-5 首页探测验收

日期：2026-09-06。前置提交 `479839d6`（WP-2 登记，实现 `16cba246`）；开始时 dev 工作树干净。本包实现与最终门禁均已完成，实现提交待登记。

## 1. 完成范围

首页与管理页共用应用会话级 `AgentManagementSliceNotifier`。首页原有 detector、安装列表缓存、加载 token、全局回滚和 post-frame 镜像更新全部移除；`agentManagementHomeProvider` 直接投影该 owner。app coordinator 在初始恢复结束且无活动项目时发起同一个 ensure，近期 thread 预热仍由 Shell 独立负责。

- `AgentManagementDetectionState` 独占逐 Provider confirmed、pending partial、progress、outcome、失败和缓存写入警告。只有正式成功替换对应记录；A 成功/B 失败保留 A 的新记录和 B 的旧记录，未确认的 partial 不成为首页安装行，首次失败保持 unknown。成功 `notInstalled` 移除行并删除旧安装路径缓存。
- `ensureDetected/refreshDetection` 在任何 dispatch/await 前占住 caller Future 和物理执行；初始化、运行以及取消后的排空均加入同一个 Future。ensure 消耗一次自动尝试，显式刷新才能重试。cancel 立即返回 canceled，close 返回 closed，底层无取消能力的 I/O 仍等待自然结束后排空。原 `detect` 同义入口也返回 typed 结果并保持相同 Future。
- app `ContributedAgentManagementDetectionAdapter` 使用已验证贡献目录，逐项隔离异常；缓存失败单独记录，持久化前重读最新配置，只合并既有检测白名单，保留 command、arguments、enabled、environment、权限与无关 extra。目录按 app-session 冻结，旧 owner/旧目录代次不能接受新结果，不新增插件热替换产品能力。
- application 中不再保存 `ManagedAgent` 或路径版 definition/connection result，`agentsById` 无 backing field/copyWith 写入口。安全视图从确认字段、当前设置、显式连接检查、配置/日志摘要和运行事实计算。
- 详情资源只留在 app catalog；同步发布前 staged handle 已可读，拒绝/异常立即丢弃，探测与显式检查独立分槽，替换/关闭使旧 handle 失效。页面仅使用缩略显示及受控复制/打开操作，原始路径不传给 Widget。
- 显式连接检查单列保存，空模型结果保留探测模型；进程相关配置变化清除覆盖并拒绝仍在等待的旧检查结果。配置编辑、日志读取和 WP-1 session 运行事实保持独立。
- 初始化等待设置加载后读取当前快照，避免复用首轮 Future 时恢复旧配置；用户可感知修复同步记录到 `CHANGELOG.md` 未发布段。

## 2. 关键接线与证据

| 接线 | 验证 |
|---|---|
| application owner → runner → 安全 detection port → bool receipt | 初始化共享 Future、observer 重入/异常、cancel/close/drain、旧 owner/目录代次测试 |
| 贡献仓储 → safe Details/Partial | 每项异常继续、partial 不确认、首次失败不误报安装、cache warning、配置并发修改测试 |
| confirmed → Home/Management selector | 真实 IdeHome 首页 → 管理页 → 首页的成功与失败流程；保留非默认 Provider 运行事实测试 |
| app 详情目录 → presentation display/copy/open | staged 同步读取、拒绝/关闭/替换失效、两类句柄互不淘汰、真实复制按钮点击 |
| 测试统一端口 | 通用测试 port 发逐 Provider 事件；第四个插件用真实 adapter + 内存仓储，不走单独 Home loader |
| 边界守卫 | 禁止 application 的 ManagedAgent/私有字段、禁止 Home 镜像；正反例；原 owner、分层、l10n、插件隔离守卫 |

原声明/断言审计见 [01-assertion-audit.md](01-assertion-audit.md)，跨版本红绿证据见 [02-regression-before-after.md](02-regression-before-after.md)。三条跨版本回归在前置提交全部失败，在当前实现全部通过。

## 3. 验证记录

环境：`DASH__SUPPRESS_ANALYTICS=true PUB_HOSTED_URL=https://pub.dev`；保持 `dart_test.yaml` concurrency=2。未找到 `.codegraph/` 索引及仓库 `.agents/skills`/`.claude/skills`，使用源码搜索和现有仓库测试工具。

| 门禁 | 结果 |
|---|---|
| 开发定向 | 管理、adapter、详情、架构守卫及 Home 渲染 96 条通过；真实页面切换 2 条通过；受影响接线修正后另 18 条通过 |
| 格式化 | 1,140 个 Dart 文件，最后 0 改动 |
| 静态检查 | `flutter analyze` 无问题 |
| 受影响 | 121/319 个根测试文件，6 个分片均涉及；880 条通过 |
| 完整门禁 | 根 2,118 条、10 个内部包 1,076 条，共 3,194 条通过；10 包分析无问题；脚本退出码 0 |
| 本地化 | literal checker 通过；两语言 1,048 个 key、206 个 placeholder 名称/类型对齐 |
| 原断言 | 89 个原测试声明全部保留；661 条原断言中 649 条原文不变、12 条逐项登记；另记录探测 waiter 从原异常列表分离 |
| 依赖与范围 | packages、pubspec.yaml、pubspec.lock、dart_test.yaml 无 diff；不增加存储 schema 或缓存文件 |

最终日志：`/tmp/wp5-analyze-final.log`、`/tmp/wp5-affected-final.log`、`/tmp/wp5-full-final.log`、`/tmp/wp5-localized-final.log`。完整门禁根 JSON 为 `.dart_tool/test-results/full.json`。

根 JSON 记录 `success: true`、2,118 个非 hidden 测试完成、0 失败。内部包分别为 core 7、api 3、claude_code 345、codex 175、grok 193、sdk 74、foundation 32、markdown 208、plugin_kernel 23、ui 16。最终门禁已包含初始化旧 Future 回归；之前完成的 3,193 条全量保留为开发过程日志 `/tmp/wp5-full-before-initialization-fix.log`，不作为最终提交的验证结果。

## 4. 边界与交接

真实 CLI 探测、原生文件管理器手工打开、macOS 手工退出、Windows/Linux Profile 均未执行；测试使用内存或明确隔离的 fixture，不能替代平台实测。逻辑取消不承诺立即终止底层进程；关闭顺序依靠真实执行排空。

计划下一项为 **集成验收**。回滚按整个 WP-5 提交恢复入口、selector、UI 和测试接缝，不保留两套 detector，不清空用户配置；WP-1/3 的运行事实与显式 owner 生命周期保持独立。

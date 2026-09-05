# Claude 跨平台统一凭据入口验证

日期：2026-09-05。

## 实现范围

- Claude 插件 data 层以 `ClaudeCodeCredentialsService.read()` 为唯一消费入口；
  默认 `LocalClaudeCodeCredentialsService`，由 Provider 组合并注入额度适配器。
- macOS Keychain / 文件回退、Windows/Linux 文件、显式环境 token 均返回同一结果模型。
- 支持 accessToken、可空 refreshToken / UTC expiresAt、scopes、subscriptionType、
  rateLimitTier；过期与未知有效期均可读取，具体操作自行校验。
- 取消旧 reader 与消费者默认创建 reader 的旁路。初始化不预读，不新增共享 hook、
  Bundle 凭据端口、生产 barrel 导出、持久化、刷新或网络写操作。
- 来源优先级与账户隔离、异常分类、可注入平台、外部轮换、脱敏、额度有效期二次检查
  均由合成 fixture 测试覆盖。真实文件 IO 测试只使用自动清理的临时目录。

## 验证结果

| 检查 | 结果 |
|---|---|
| `dart format .` | 通过 |
| 根 `flutter analyze` | 无问题 |
| `bash tool/test_packages.sh --only zeta_agent_provider_claude_code --reporter expanded` | 分析无问题，281 项测试通过 |
| `bash tool/test_affected.sh` 的根测试阶段 | 旧 Dart 文件删除触发自动全量，1,919 项通过 |
| 同一选择器追加的全部内部包测试 | 10 包、1,012 项通过 |
| 内部包分析恢复 | 见下文，全部无问题 |
| `git diff --check` / 依赖锁文件 | 通过 / 未改变 |

全量闭包合计 **2,931 项测试通过**。自动升级已经覆盖根全量与全部内部包，未重复运行
相同测试。选择器首次进程最终退出码为 1：其中 7 个纯 Dart 包的分析服务在遥测网络
请求时异常退出，测试本身均通过。分别以 `CI=true dart analyze` 重跑
`zeta_agent_core`、`zeta_agent_provider_api`、`zeta_agent_provider_claude_code`、
`zeta_agent_provider_codex`、`zeta_agent_provider_grok`、`zeta_agent_provider_sdk`、
`zeta_plugin_kernel`，全部退出码 0、无问题；其余 3 包原分析通过。未修改工具脚本或
用户全局遥测设置。

## 证据与限制

- 读取规则参考本地 Claude Code checkout `77a7934e` 的 auth / secureStorage / OAuth
  client 实现；该项目自述为逆向还原，不能替代官方协议保证。
- 三平台分支与路径由注入平台测试验证；macOS Keychain 的参数、命名和错误路径由
  注入进程验证。本次没有读取真实登录凭据或执行 OAuth 刷新。
- macOS / Windows / Linux 的真实登录账户读取验收均为 **待执行**，不得由模拟测试
  或本机临时文件测试推断通过。

详细契约与使用入口见 `docs/zh/protocols/claude_code_stream_json_protocol.md` §11。

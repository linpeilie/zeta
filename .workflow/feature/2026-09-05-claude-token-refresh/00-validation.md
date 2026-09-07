# Claude Provider 获取与请求前按需刷新

日期：2026-09-05。实现范围：Claude 插件；共享内核仅新增中立获取前准备端口。

## 实现与边界

- `AgentProviderBundle.acquisitionPreparation` / `AgentProviderAcquisitionPreparationPort`：Registry 每次 acquire，包括复用，都等待准备。失败释放本次租约，等待后校验 runtime identity；不为其他 Provider 增加认证分支。
- Claude data 层统一 `ClaudeCodeCredentialsService`：`read()` 保持只读，`ensureFresh()` 判断 `expiresAt <= now + 5 min` 并按需刷新。`LocalClaudeCodeCredentialsService.forProvider` 统一有效环境与 API key/bare 模式路由。
- 获取实例、启动/恢复会话、每个新 turn（含 compact）、模型与套餐额度操作前校验。独立 metadata probe（含显式连接测试）也校验。CLI 自己内部的每次 HTTP/工具继续执行由 CLI 认证；Zeta 不拦截这些内部调用。取消和审批回写不等待认证刷新。
- 正常生产 OAuth endpoint 固定为 `https://platform.claude.com/v1/oauth/token`，client ID 固定为 Claude 生产客户端 ID；发送 refresh grant 和原 scopes，不扩大 scope。15 秒总超时、不跟随重定向、不自动重试。自定义 issuer/client ID 和 staging/local OAuth 刷新拒绝。
- 插件激活级协调器合并同一账户进行中的刷新；跨进程使用 canonical directory 的 `.lock` 目录、原子创建与 mtime 心跳，兼容 Claude 的 proper-lockfile 锁名/租约机制。最长等锁 12 秒、不抢旧锁，锁内重读。
- macOS 更新已选中的 Keychain 条目，命令内容只走 `security -i` stdin；验证长度上限和写回结果，不把 secret 放 argv。Keychain 失败不改写其他来源。
- Windows/Linux 更新原 credentials 文件；macOS 原来源为文件时更新同一文件。POSIX 临时文件写入 secret 前设为 0600，完成后同目录 rename；Windows PowerShell/.NET 复制原 ACL 并以 `File.Replace` 替换。保留无关 envelope/OAuth 字段，完成后重读比较 access/refresh/expiry。正常结束清理临时文件，不建立备份或 Zeta 凭据副本。
- 配额开关仅控制 usage REST，认证维护独立执行。设置页、隐私说明、中英文文案与协议文档已同步。

缺失或未知到期时间的凭据继续交由 CLI 原有认证路径处理；已知过期但不能刷新、锁失败、网络拒绝或写回失败阻止本次操作。此能力只判断本地有效期，不证明未过期 token 未被撤销；未增加 Zeta 401 强制刷新/重放，也没有周期刷新定时器。

## 参考与迁移取舍

- 本地参考：Claude Code 外部源码 checkout `77a7934e`（个人绝对路径已移除，未将该副本当作官方协议证据）。
- `src/utils/auth.ts`：`checkAndRefreshOAuthTokenIfNeeded`、`handleOAuth401Error`；`src/services/oauth/client.ts`：refresh grant 与响应映射；`src/utils/secureStorage/`：Keychain/文件存储策略。
- 该 checkout 自述为逆向还原并含 stub，不将其视为官方稳定协议。没有复制其 force 后仍按到期时间提前返回、忽略保存结果以及凭据存储迁移/删除逻辑。
- proper-lockfile 锁协议核对：[v4.1.2 lockfile.js](https://github.com/moxystudio/node-proper-lockfile/blob/v4.1.2/lib/lockfile.js)。Windows 替换语义参考：[Microsoft ReplaceFileW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew)。

## 验证

测试全部使用合成凭据/伪 HTTP，真实账号凭据未读取、未刷新。外层测试环境另设 `CLAUDE_CODE_OAUTH_TOKEN=zeta-synthetic-test-token` 防止旧运行时 fixture 意外访问宿主凭据；认证功能测试自身注入独立环境和临时目录。

覆盖：三个平台的来源选择与轮换；五分钟边界；refresh token 缺失；外部认证；无效/超大响应；不跟随重定向和不重试；同进程合并和独立协调器的目录锁串行；CLI 外部轮换；来源变化；锁超时/失效；Keychain 拒绝、假成功、stdin 参数及行长上限；POSIX 权限和原子替换；Provider 新请求失败不发送 prompt；新建/复用租约等待、失败释放与关闭/失效期间不返回旧实例；独立连接探测不绕过认证准备。

最终门禁均通过（退出码 0）：

| 检查 | 结果 |
| --- | --- |
| `CI=true dart format .`，随后 `dart format --output=none --set-exit-if-changed .` | 完成格式化；1088 个文件复核为 0 个修改 |
| `CI=true flutter analyze` | No issues found |
| `CI=true flutter gen-l10n` | 已生成中英文资源 |
| `CI=true dart run tool/check_localized_ui_strings.dart --check` | 0 zeta_copy hits，0 allowlist entries |
| `CI=true CLAUDE_CODE_OAUTH_TOKEN=zeta-synthetic-test-token bash tool/test_affected.sh` | 251/302 个根测试文件 + 全部内部包；根 1629 条、内部包 1058 条，总计 2687 条通过 |
| 内部包 analyze | 10 个内部包均通过，由 affected 脚本的 package 门禁执行 |
| `git diff --check` | 通过 |
| 根与内部包 `pubspec.lock` | 无改动 |

最终内部包测试数：core 7、provider_api 3、Claude 327、Codex 175、Grok 193、provider_sdk 74、foundation 32、markdown 208、plugin_kernel 23、ui 16。没有执行真实 CLI/账号冒烟。

最终执行日志保存在本机会话临时目录：`/tmp/zeta-token-gate.log`、`/tmp/zeta-token-root-analyze-final.log`、`/tmp/zeta-token-format-final.log`、`/tmp/zeta-token-format-check.log`、`/tmp/zeta-token-l10n-check-final.log`。日志只含测试/工具输出，未使用真实凭据。

## 真实环境待验证

- macOS 原生临时目录锁、mtime 心跳、0600 文件替换已由合成文件测试执行。Keychain 进程写入使用 fake process/readback 测试，没有改动真实 Keychain。
- Windows/Linux 来源路由通过平台模拟测试；Windows PowerShell/ACL/原子替换和 Linux 原生文件系统尚未在对应设备执行，不能记为三系统原生验收通过。
- 三平台真实 Claude 登录与真实远端 token 轮换均待执行。网络超时/锁丢失/写回失败可能发生于服务端已轮换之后，不能承诺保留可用旧 refresh token；需要时重新登录。
- 目录锁协调遵守同一锁协议的刷新程序；不遵守该锁的外部登录/注销与最终写回之间不存在通用跨进程 CAS。写前来源/内容比较可拒绝已观察到的变化，不能宣称覆盖所有外部竞争。

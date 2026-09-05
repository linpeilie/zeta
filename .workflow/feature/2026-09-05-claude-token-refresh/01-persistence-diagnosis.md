# 启动 persistence 错误排查与修复

## 已确认的代码缺陷

Dart `DateTime.now()` 可携带微秒，而 Claude credentials 的 `expiresAt` 是 Unix 毫秒。原 OAuth client 保留微秒，写入 `millisecondsSinceEpoch` 后丢弃不足一毫秒部分，service 却用两个完整 DateTime 做写后相等比较。因此实际写回成功也会抛出 `persistence`，阻断本次 acquire 和线程列表加载。

用合成期限 `now + 1 hour + 731 microseconds` 在 macOS、Windows、Linux 三种来源路由全部复现：修复前 3 条用例均失败于 `stage=verify, reason=readbackMismatch, refreshCompleted=true`。修复后按存储的毫秒语义比较；OAuth client 同时直接构造毫秒精度的期限。补充反例确认真正相差 1 毫秒仍拒绝，token 和来源校验不放宽。

旧日志未保留阶段，不能证明当时只有这一种原因。这个确定性缺陷足以造成所报现象，本次已修复；不能把当前有效 token 状态当作原日志时刻的状态。

## 只读现场检查

只检查当前进程默认环境对应的 Keychain；原文只在诊断进程内存中使用，输出仅含布尔值/长度/枚举，不记录凭据、账号、路径或原始错误。

- Keychain 读取成功、JSON 可解码，存在 refresh token。
- 存储内容 504 字节，对应交互命令 1082 字节，没有触发 4096 字节预检限制。
- 当前有效期类别为 valid；未调用真实 token endpoint，也未写回真实凭据。
- 这不证明 Zeta 自定义环境使用相同来源，也不证明写权限正常。

## 排查入口与后续处理

仓库根目录执行：

```sh
dart packages/zeta_agent_provider_claude_code/tool/diagnose_credentials.dart
```

需要自定义配置目录时追加 `--config-dir DIRECTORY`。其他环境覆盖须与 Zeta 对齐；不把凭据值作为命令行参数。命令仅调用 read 与命令格式/长度预检，不做刷新或写权限探测。

示例输出只有元信息：`mode=readOnly, refreshAttempted=false, source=keychain, expiry=valid, preflight=passed`。

新错误保持 `persistence` 类别，增加下列字段：

- `stage=preflight`：写前格式/长度检查。
- `stage=write`：进程启动、命令执行、管道或文件写入。
- `stage=verify`：写后读取不可用或数据不一致。
- `reason`：允许的固定枚举，例如 payloadTooLarge、interactionNotAllowed、userCanceled、timeout、readbackMismatch；不保存 stderr。
- `refreshCompleted`：是否已经取得有效远端刷新响应。false/true 区分远端调用前和调用后的持久化失败。
- `exitCode`：可选进程退出码，不等价于 macOS OSStatus。

收到 interactionNotAllowed/userCanceled 时，先检查并解锁对应 Keychain 或处理系统访问提示；不要使用 `-A` 放宽所有应用访问。readbackMismatch 要检查来源和精度/竞争问题，不能吞异常或改写其他来源。只有实际远端 rejected 等证据指向登录失效时，才需要通过 CLI 重新登录。此次缺陷无需删除凭据或清空 Claude 会话。

同时修复写操作超时边界：stdin 写入、退出等待、stdout/stderr 排空均受超时约束，防止进程退出而管道未结束导致挂起。测试覆盖进程启动失败、权限/取消分类、退出码 0 的交互错误、读回失败与 secret 不泄漏。

Apple 工具的交互行长/返回码处理参考 [security.c](https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/security.c)。本机 `security help add-generic-password` 确认支持 `-X`；没有执行真实 Keychain 写入冒烟。

## 验证

- `dart format .`：1091 个文件检查，0 个格式变化。
- `flutter analyze` 与 Claude 包单独 analyze：均无问题。
- `bash tool/test_affected.sh`：选择器因新增工具入口自动升级全量，退出码 0；根应用 1924 条、10 个内部包合计 1076 条，共 3000 条通过。其中 Claude 包 345 条通过。
- 新增回归覆盖三平台来源路由的微秒精度、真实 1 毫秒差异拒绝、错误阶段/原因、超时、脱敏以及只读诊断工具。三平台路由用合成存储验证，不代表在三套原生系统执行了真实刷新。
- 只读诊断命令在当前 macOS 默认环境成功输出安全元信息；未执行真实 OAuth 刷新或凭据写入。
- `git diff --check` 通过；锁文件未变化。

验证日志位于本机临时目录：`/tmp/zeta-persistence-gate.log`、`/tmp/zeta-persistence-root-analyze.log`、`/tmp/zeta-persistence-analyze-final.log`、`/tmp/zeta-persistence-format-final.log`；修复前复现日志为 `/tmp/zeta-persistence-repro.log`。测试进程使用合成 OAuth 环境值，避免旧 fixture 意外访问真实凭据。

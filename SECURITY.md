# 安全策略 / Security Policy

## 上报安全问题

不要在公开 Issue 中提交漏洞细节或真实凭据。优先使用仓库页面的 **Security → Report a vulnerability**。如果该入口不可用，可先向维护者询问安全联系方式，公开内容只说明需要私密沟通，不附漏洞细节。

请提供受影响版本、操作系统、复现步骤和可能影响；示例使用测试数据。维护者不承诺固定响应时限。安全修复优先提供给最新发布版本。

## 需要报告的问题

- 权限卡片展示内容与实际执行不符、绕过用户决定或未经选择扩大权限。
- Zeta 读取或写入超出产品功能范围的文件，或错误处理文件链接导致越界访问。
- 私人消息、回复、文件内容或凭据进入 Zeta 的统计、日志、缓存或系统通知。
- 启动了错误的助手程序，或关闭后仍有本应结束的任务。

Zeta 会为连接、历史查看、统计和诊断读取所连接助手的数据。用户保存配置、管理会话，以及 Claude Code 登录续期都可能写入助手自己的文件。不能把所有助手目录访问都当作违规，也不能把读取权限当作任意写入权限。

## 数据与权限边界

Zeta 没有自己的云端对话服务，但所连接助手可能向模型服务发送消息、图片和文件内容。是否发送及如何保留，由助手和账号设置决定。

Zeta 自有数据保存在系统文档目录的 `.zeta` 文件夹，没有单独加密。完整位置、清理方式和 Claude Code 登录维护说明见[数据与隐私](docs/zh/guide/data-and-privacy.md)。

助手在用户选择的权限范围内执行操作。宽松权限下部分操作无需逐次确认；Zeta 不应自行扩大这些权限。助手自身的模型或工具问题，应同时向对应项目报告。

安装包缺少开发者签名是已知发布限制；异常下载内容、校验不符或非预期程序仍应报告。第三方依赖漏洞请说明在 Zeta 中的影响或复现方式。

## Reporting security issues

Do not put vulnerability details or real credentials in public issues. Prefer **Security → Report a vulnerability** on the repository page. If unavailable, ask the maintainer for a private contact method without posting exploit details.

Include affected versions, operating system, reproduction steps and likely impact, using test data. No fixed response time is promised. Security fixes prioritize the latest release.

Report mismatches between approval cards and execution, bypassed decisions, permission expansion, file access outside the product's scope, sensitive content in Zeta's stored records or notifications, incorrect program launches, and tasks that remain after they should stop.

Zeta reads connected assistants' data for connection, history, statistics and diagnostics. Saving configuration, managing conversations and maintaining Claude Code sign-in may also write their data. Reading is not authorization for unrestricted writing.

Zeta has no cloud conversation service of its own. Assistants may send messages, images and file contents to model services according to their account settings. Zeta's own data is unencrypted in `.zeta` inside the system Documents directory. See [Data and Privacy](docs/en/guide/data-and-privacy.md).

Permissive modes can allow some operations without asking each time. Zeta must not broaden those permissions on its own. Report model or tool issues to the corresponding assistant project as well.

Unsigned packages are a known release limitation. Unexpected downloads, failed checksums and unexpected programs should still be reported. For a dependency vulnerability, describe its impact or reproduction within Zeta.

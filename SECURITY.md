# 安全策略 / Security Policy

中文在前，English below.

---

## 上报漏洞

**请不要通过公开 Issue 上报安全漏洞。**

请使用 GitHub 的私密漏洞上报：仓库页面 → **Security** → **Report a vulnerability**。这个渠道只有维护者可见，可以在修复发布前保持不公开。

上报时请尽量包含：

- 受影响的版本与操作系统；
- 触发条件与复现步骤；
- 你评估的影响范围；
- 如果有 PoC，请**脱敏**后附上（不要包含真实凭证）。

维护者目前只有一人，会尽力在合理时间内响应，但**不承诺固定的响应或修复时限**。修复发布后，如果你愿意，可以在 Release Notes 中署名致谢。

## 支持的版本

项目处于早期阶段（`0.x`），**只对最新发布版本提供安全修复**。请先升级到最新版再上报。

## 威胁模型

Zeta 是本地桌面应用，没有服务端、没有账号体系、不上传用户代码。因此值得关注的风险集中在这几处：

**会拉起本地子进程**
Zeta 通过 stdio 启动并驱动 `codex app-server`、Grok CLI 等本机可执行文件。与此相关的问题都在范围内：可执行文件路径解析被劫持、参数注入、子进程生命周期管理不当导致的进程泄漏或权限扩散。

**代表用户执行 Agent 请求的操作**
Agent 可能请求执行命令、写文件或访问网络。Zeta 的默认策略是**一律需要用户显式授权**。任何能绕过审批、静默提权、或让用户在不知情下授权的路径，都属于安全问题——包括审批卡片与实际执行内容不一致这类"所见非所签"的情况。

**读写本地文件系统**
Zeta 会浏览用户选择的项目目录，并在 `~/.zeta/` 下读写自有数据。路径穿越、符号链接逃逸、越界读取用户未授权的目录，都在范围内。

**敏感数据落盘与外泄**
Zeta 的设计约束是：派生索引与缓存只保存白名单字段，**不持久化 prompt、回复正文、工具输出、原始错误文本、环境变量、凭证或 Provider 原始数据**；日志写入前会对认证头、`Bearer` token、`sk-` 密钥、`api_key`/`token`/`secret`/`password` 类键值做脱敏，并把用户主目录替换为 `~`；系统通知只携带类别和项目目录名。

**任何违反上述约束的实际泄漏都请按安全问题上报**，例如凭证进入日志、prompt 进入统计索引、完整路径出现在系统通知里。

**不触碰其他 CLI 的私有数据**
Zeta 不读取、不迁移、不改写 `~/.codex`、`~/.grok`、`~/.cursor` 及项目内的 `.cursor`。发现任何越界访问请上报。

## 不在范围内

- **Agent 自身的行为。** 如果你授权了一条命令，Agent 执行了它并造成损害，这是预期行为，不是 Zeta 的漏洞。请向对应的 Agent CLI 项目反馈模型或工具层面的问题。
- **Agent CLI 自身的漏洞。** 请上报给 Codex / Grok 各自的项目。
- **安装包未签名。** 已知情况：发布流程不做 Windows 代码签名，也不做 macOS 签名与公证，因此首次运行会有系统提示。这是当前的发布方式，不作为漏洞处理。
- **需要本机已被攻破才能利用的问题。** 攻击者已经拥有你的用户权限时，能读 `~/.zeta/` 属于预期。
- **第三方依赖的已知 CVE**，除非你能说明在 Zeta 中的实际可利用路径。

---

# Security Policy (English)

## Reporting a vulnerability

**Please do not report security vulnerabilities through public issues.**

Use GitHub's private vulnerability reporting: repository → **Security** → **Report a vulnerability**. Only maintainers can see that channel, which keeps the report confidential until a fix ships.

Please include what you can:

- affected version and operating system;
- trigger conditions and reproduction steps;
- your assessment of the impact;
- a **redacted** PoC if you have one (no real credentials, please).

There is currently a single maintainer, who will make a good-faith effort to respond promptly but **cannot commit to fixed response or remediation timelines**. Credit in the release notes is offered if you'd like it.

## Supported versions

The project is early-stage (`0.x`). **Security fixes are provided for the latest release only.** Please upgrade before reporting.

## Threat model

Zeta is a local desktop application with no server, no accounts, and no code upload. The risks worth attention are therefore concentrated here:

**It spawns local subprocesses**
Zeta launches and drives local executables such as `codex app-server` and the Grok CLI over stdio. In scope: hijacked executable path resolution, argument injection, and subprocess lifecycle handling that leaks processes or escalates privileges.

**It performs actions on the agent's behalf**
Agents may request command execution, file writes, or network access. Zeta's default policy requires **explicit user approval for all of it**. Any path that bypasses approval, silently escalates, or gets a user to approve something they didn't understand is a security issue — including "what you saw isn't what you signed" mismatches between the approval card and what actually runs.

**It reads and writes the local filesystem**
Zeta browses the project directory you select and reads/writes its own data under `~/.zeta/`. Path traversal, symlink escapes, and reads outside authorized directories are all in scope.

**Sensitive data at rest and in transit**
Zeta's design constraints: derived indexes and caches store allow-listed fields only and **never persist prompts, response bodies, tool output, raw error text, environment variables, credentials, or provider raw payloads**; logs are redacted before writing (authorization headers, `Bearer` tokens, `sk-` keys, and `api_key`/`token`/`secret`/`password` style values are masked, and the home directory is replaced with `~`); system notifications carry only a category and the project folder name.

**Any actual leak that violates these constraints should be reported as a security issue** — credentials reaching logs, prompts reaching the usage index, full paths appearing in notifications, and so on.

**It never touches other CLIs' private data**
Zeta does not read, migrate, or rewrite `~/.codex`, `~/.grok`, `~/.cursor`, or a project's `.cursor`. Report any out-of-bounds access.

## Out of scope

- **Agent behavior itself.** If you approved a command, the agent ran it, and damage followed, that's expected behavior rather than a Zeta vulnerability. Report model- or tool-level concerns to the corresponding agent CLI project.
- **Vulnerabilities in the agent CLIs.** Report those to Codex / Grok respectively.
- **Unsigned installers.** Known: the release pipeline does not code-sign on Windows, nor sign and notarize on macOS, so first launch shows an OS warning. That's the current distribution model, not a vulnerability.
- **Issues requiring a already-compromised machine.** If an attacker already has your user privileges, reading `~/.zeta/` is expected.
- **Known CVEs in third-party dependencies**, unless you can describe an actually exploitable path within Zeta.

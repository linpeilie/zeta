# Zeta Documentation

English ｜ [中文](../zh/README.md)

Zeta is a desktop application that puts command-line AI coding assistants into a workbench where you can see what they're doing and stay in control.

## Where to start

| If you are… | Start here |
| --- | --- |
| **A user** who wants to install and use it | [Installation and First Run](guide/getting-started.md) → [Interface Tour](guide/workbench.md) → [Approvals, Questions and Plans](guide/approvals.md) |
| **A contributor** reading the code for the first time | [Architecture Overview](architecture/overview.md) → [Glossary](development/glossary.md) → [Contributing](../../CONTRIBUTING.en.md) |
| **An evaluator** interested in the design trade-offs | [Product Requirements](product/product_requirements.md) |
| **A maintainer** cutting a release | [Release Guide](release/release_guide.md) → [Changelog](../../CHANGELOG.md) |

## guide — User guide

Written for people using Zeta; no implementation detail.

| Page | Contents |
| --- | --- |
| [Installation and First Run](guide/getting-started.md) | Requirements, download, first launch, opening a project, first message |
| [Interface Tour](guide/workbench.md) | Title bar, project and conversation lists, conversation area, file tree, narrow windows |
| [Conversations and the Timeline](guide/conversations.md) | Reading the timeline, the composer, choosing a model, cancelling, editing and branching, compacting |
| [Approvals, Questions and Plans](guide/approvals.md) | Permission cards, permission modes, questions, plan mode and execution confirmation |
| [Connecting AI Assistants](guide/agents.md) | Supported assistants, what each supports, the Agents page, detection and connection tests |
| [Notifications](guide/notifications.md) | When you get notified, what notifications contain, where the switches are |
| [Usage Statistics](guide/usage-statistics.md) | Data sources, how calls are counted, filters and details, plan quota |
| [Settings](guide/settings.md) | Every option under General and Appearance |
| [Data and Privacy](guide/data-and-privacy.md) | What Zeta stores, what it reads, how to clear it |
| [Troubleshooting](guide/troubleshooting.md) | Problems by symptom |

## architecture — Architecture

- [Architecture Overview](architecture/overview.md) — layering, the event pipeline, capability negotiation, and how the three kinds of approval differ. Start here as a new contributor.

Not yet translated (read the Chinese versions): [design document](../zh/architecture/design_document.md), [engineering standards](../zh/architecture/engineering_standards.md), [desktop notification design](../zh/architecture/desktop_agent_notification_design.md).

## development — Development

- [Glossary](development/glossary.md) — thread, turn, entryId, bundle, capability, coalescing, lease and other recurring terms

Not yet translated: [developer guide](../zh/development/developer_guide.md).

## product — Product

- [Product Requirements](product/product_requirements.md) — target users, scope, user flows, and what is explicitly out of scope

## protocols — Protocols

- [Codex app-server Protocol Pin](protocols/codex_app_server_protocol.md) — the pinned schema and the upgrade process

Not yet translated (read the Chinese versions):

- [Claude Code stream-json protocol baseline](../zh/protocols/claude_code_stream_json_protocol.md)
- [Claude Code token metering](../zh/protocols/claude_code_token_metering.md)
- [Claude Code provider adapter proposal](../zh/protocols/claude_code_provider_adapter.md) — a historical design proposal; the rejected REST / static catalog approach in it does not describe the current implementation

## release — Release

- [Release Guide](release/release_guide.md) — tag rules, quality gates, artefacts and platform notes

## history — Archive

Kept as historical evidence only. **These do not describe currently supported behaviour.**

- [Cursor Agent Retirement Notes](history/cursor_agent_guide.md)
- [Cursor ACP Historical Release Gate](history/cursor_acp_release_validation.md)
- [Development Log](history/development_log.md)
- [Project Memory](history/project_memory.md)

## Repository root

- [Changelog](../../CHANGELOG.md) — user-visible changes per release
- [Contributing](../../CONTRIBUTING.en.md) — environment, commit format and the architectural rules enforced in review
- [Security policy](../../SECURITY.md) — threat model and how to report vulnerabilities
- [Code of conduct](../../CODE_OF_CONDUCT.md)
- [AGENTS.md](../../AGENTS.md) — the single source of truth for AI collaboration rules (Chinese)

# Zeta project documentation

[中文](../zh/README.md) ｜ English

This repository is the VGV-architecture rewrite of Zeta. The migration is in progress; documentation is updated alongside each migration step.

Not sure where to start? Pick by role:

| You are… | Start here |
| --- | --- |
| A **contributor** reading the code for the first time | [Architecture overview](./architecture/overview.md) → [Glossary](./guides/glossary.md) |
| A **contributor** working on the migration | [Migration topology](./architecture/migration_topology.md) → [Migration task list](./architecture/migration_tasks.md) → [File-by-file manifest](./architecture/migration_manifest.md) |
| A **contributor** about to touch a legacy class | [Ownership map](./architecture/ownership_map.md) |
| A **contributor** about to build a package | [Package API contracts](./architecture/package_api_contracts.md) |
| A **contributor** integrating a provider | [Protocol docs](#protocols) |
| A **contributor** already up to speed | [Developer guide](./guides/developer_guide.md) → [Engineering standards](./architecture/engineering_standards.md) |
| An **evaluator** interested in design trade-offs | [Product requirements](./product/product_requirements.md) → [Design document](./architecture/design_document.md) |
| A **maintainer** cutting a release | [Release guide](./release/release_guide.md) |

## Directory structure

`docs/` is split into two language trees with **identical subdirectories and identical filenames**; the
language is determined by the directory:

```
docs/
├── README.md               language entry point
├── zh/                     Chinese — same subdirectories, same filenames
└── en/                     <- you are here
    ├── README.md
    ├── architecture/       Overview, layering, engineering standards, migration docs   done
    ├── protocols/          Provider protocol baselines                                done
    ├── history/            Retired capabilities and development log, archive only      done
    ├── guides/             Developer guide, glossary, internationalization guide       pending
    ├── product/            Product requirements, troubleshooting and data reference    pending
    ├── release/            Release process                                            pending
    └── images/             Screenshots and capture checklist                           pending
```

"pending" directories are created by their corresponding migration step (Git does not track empty
directories, so they are not visible yet).

**Filenames carry no language suffix.** A new document must be created under **both** `zh/` and `en/`
with the same name, in the same commit. The convention is documented in the
[engineering standards](./architecture/engineering_standards.md).

The sole exception is `history/`: archived documents keep their original language and are not
translated; the other side carries a pointer to them.

### Documents that exist today

The migration is in progress; documents listed below but not yet created are filled in by their corresponding migration step. Available now:

| Document | Purpose |
| --- | --- |
| [Migration topology](./architecture/migration_topology.md) | Boundaries, layering rules, target package topology, gates, roadmap |
| [Migration task list](./architecture/migration_tasks.md) | 37 checkable steps with a per-step definition of done |
| [File-by-file manifest](./architecture/migration_manifest.md) | source→target classification of all 1,507 tracked files |
| [Ownership map](./architecture/ownership_map.md) | Which of the four layers each legacy class belongs to |
| [Architecture decisions](./architecture/architecture_decisions.md) | ADR-001—004 and the cleared open-decision register |
| [Package API contracts](./architecture/package_api_contracts.md) | Barrel exports and interface signatures |
| [Conversation state design](./architecture/agent_conversation_state_design.md) | Field-level design of `AgentConversationBloc` |
| [Three protocol baselines + token metering](#protocols) | The basis for provider adapters |

## architecture

- [**Architecture overview**](./architecture/overview.md)（[中文](../zh/architecture/overview.md)）⭐ — VGV four-layer architecture, package boundaries, event pipeline, capability negotiation. Start here
- [**Migration topology**](./architecture/migration_topology.md)（[中文](../zh/architecture/migration_topology.md)）⭐ — Legacy module breakdown, dependency graph, P0–P7 roadmap
- [**Migration task list**](./architecture/migration_tasks.md)（[中文](../zh/architecture/migration_tasks.md)）⭐ — 37 checkable steps from P-1 to P8, with a per-step definition of done
- [**File-by-file manifest**](./architecture/migration_manifest.md)（[中文](../zh/architecture/migration_manifest.md)）⭐ — source→target classification of the old repo's 1,507 tracked files, each exactly once
- [**Ownership map**](./architecture/ownership_map.md)（[中文](../zh/architecture/ownership_map.md)）⭐ — Legacy controllers/stores/services ruled one by one into Data/Repository/Bloc/Presentation; where all 24 `ChangeNotifier`s go
- [**Architecture decisions**](./architecture/architecture_decisions.md)（[中文](../zh/architecture/architecture_decisions.md)）⭐ — ADR-001—004, their review triggers, and the cleared open-decision register
- [**Package API contracts**](./architecture/package_api_contracts.md)（[中文](../zh/architecture/package_api_contracts.md)）⭐ — Barrel exports and key interface signatures; the precondition for parallel P2 work
- [**Conversation state design**](./architecture/agent_conversation_state_design.md)（[中文](../zh/architecture/agent_conversation_state_design.md)）⭐ — Field-level design of the five `AgentConversationBloc` slices, the event catalogue and cache ownership
- [Layering design](./architecture/layering.md)（[中文](../zh/architecture/layering.md)）— Data / Repository / Bloc / Presentation responsibilities, injection, bloc scoping
- [Design document](./architecture/design_document.md)（[中文](../zh/architecture/design_document.md)）— Runtime composition, UI skeleton, streaming adapter responsibility matrix
- [Engineering standards](./architecture/engineering_standards.md)（[中文](../zh/architecture/engineering_standards.md)）— Architecture review rules, CI gates, bilingual documentation convention

## guides

- [Developer guide](./guides/developer_guide.md)（[中文](../zh/guides/developer_guide.md)）— Environment, commands, package structure, provider integration, testing
- [**Glossary**](./guides/glossary.md)（[中文](../zh/guides/glossary.md)）⭐ — thread / turn / entryId / bundle / capability / coalescing and other recurring terms
- [Internationalization guide](./guides/internationalization.md)（[中文](../zh/guides/internationalization.md)）— string-passing for shared widgets, TextCatalog abstraction, locale freezing

## product

- [Product requirements](./product/product_requirements.md)（[中文](../zh/product/product_requirements.md)）— Target users, capability scope, explicit non-goals
- [Troubleshooting and data reference](./product/troubleshooting.md)（[中文](../zh/product/troubleshooting.md)）— Common problems, what lives in `~/.zeta`, cleanup and reset

## protocols

The three provider protocol baselines are the implementation basis for their Data packages. Required reading before integrating a provider.

- [Codex app-server protocol pinning](./protocols/codex_app_server_protocol.md)（[中文](../zh/protocols/codex_app_server_protocol.md)）— pinned to CLI `0.144.5`; schema snapshot, dual baselines and experimental plan degradation → `packages/codex_app_server_client`
- [Claude Code stream-json protocol baseline](./protocols/claude_code_stream_json_protocol.md)（[中文](../zh/protocols/claude_code_stream_json_protocol.md)）— process arguments, frame shapes, identity and terminal state, model catalog, plan quotas → `packages/claude_code_client`
- [Grok ACP protocol baseline](./protocols/grok_acp_protocol.md)（[中文](../zh/protocols/grok_acp_protocol.md)）— ACP methods, `_x.ai/` extensions, 12 sessionUpdate kinds, permission modes → `packages/grok_acp_client`
- [Claude Code token metering](./protocols/claude_code_token_metering.md)（[中文](../zh/protocols/claude_code_token_metering.md)）— the three metering layers compared against Zeta; required reading before implementing usage mapping

## release

- [Release guide](./release/release_guide.md)（[中文](../zh/release/release_guide.md)）— Tag rules, quality gates, artifacts and platform notes

## history

Kept as historical evidence only. **Does not describe currently supported capabilities.** Archived
documents keep their original language and are not translated, so this directory holds pointers —
see [history/README](./history/README.md).

- [Claude Code provider adapter document (historical proposal)](../zh/history/claude_code_provider_adapter.md) — Chinese only. §2 (integration contract), §4 (data layer design notes) and §6 (semantic mapping) are still design input for `packages/claude_code_client`; do not copy the old repository paths and class names it contains.

## Related files at the repository root

- [README](../../README.md)（[English](../../README.en.md)）
- [Contributing guide](../../CONTRIBUTING.md)（[English](../../CONTRIBUTING.en.md)）
- [Changelog](../../CHANGELOG.md)

---

> During the migration, documents listed here but not yet created are filled in by their corresponding
> migration step; see the mapping in [manifest §11](./architecture/migration_manifest.md).
> The bilingual directory convention is in [task list §1.9](./architecture/migration_tasks.md) and is
> asserted by [step 36](./architecture/migration_tasks.md).

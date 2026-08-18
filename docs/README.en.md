# Zeta project documentation

[中文](./README.md) ｜ English

This repository is the VGV-architecture rewrite of Zeta. The migration is in progress; documentation is updated alongside each migration step.

Not sure where to start? Pick by role:

| You are… | Start here |
| --- | --- |
| A **contributor** reading the code for the first time | [Architecture overview](./architecture/overview.en.md) → [Glossary](./guides/glossary.en.md) |
| A **contributor** working on the migration | [Migration topology](./architecture/migration_topology.en.md) → [Migration task list](./architecture/migration_tasks.en.md) |
| A **contributor** already up to speed | [Developer guide](./guides/developer_guide.en.md) → [Engineering standards](./architecture/engineering_standards.en.md) |
| An **evaluator** interested in design trade-offs | [Product requirements](./product/product_requirements.en.md) → [Design document](./architecture/design_document.en.md) |
| A **maintainer** cutting a release | [Release guide](./release/release_guide.en.md) |

## Directory structure

```
docs/
├── architecture/   Overview, layering design, engineering standards, migration docs
├── guides/         Developer guide, glossary, internationalization guide
├── product/        Product requirements, troubleshooting and data reference
├── protocols/      Provider protocol pinning and adapter designs
├── release/        Release process
├── history/        Retired capabilities and development log, archive only
└── images/         Screenshots and capture checklist
```

**Every document is maintained in both languages**: `xxx.md` (Chinese) and `xxx.en.md` (English). The convention is documented in the [engineering standards](./architecture/engineering_standards.en.md).

## architecture

- [**Architecture overview**](./architecture/overview.en.md)（[中文](./architecture/overview.md)）⭐ — VGV four-layer architecture, package boundaries, event pipeline, capability negotiation. Start here
- [**Migration topology**](./architecture/migration_topology.en.md)（[中文](./architecture/migration_topology.md)）⭐ — Legacy module breakdown, dependency graph, P0–P7 roadmap
- [**Migration task list**](./architecture/migration_tasks.en.md)（[中文](./architecture/migration_tasks.md)）⭐ — Per-layer class design and checkable tasks for all 34 steps
- [Layering design](./architecture/layering.en.md)（[中文](./architecture/layering.md)）— Data / Repository / Bloc / Presentation responsibilities, injection, bloc scoping
- [Design document](./architecture/design_document.en.md)（[中文](./architecture/design_document.md)）— Runtime composition, UI skeleton, streaming adapter responsibility matrix
- [Engineering standards](./architecture/engineering_standards.en.md)（[中文](./architecture/engineering_standards.md)）— Architecture review rules, CI gates, bilingual documentation convention

## guides

- [Developer guide](./guides/developer_guide.en.md)（[中文](./guides/developer_guide.md)）— Environment, commands, package structure, provider integration, testing
- [**Glossary**](./guides/glossary.en.md)（[中文](./guides/glossary.md)）⭐ — thread / turn / entryId / bundle / capability / coalescing and other recurring terms
- [Internationalization guide](./guides/internationalization.en.md)（[中文](./guides/internationalization.md)）— string-passing for shared widgets, TextCatalog abstraction, locale freezing

## product

- [Product requirements](./product/product_requirements.en.md)（[中文](./product/product_requirements.md)）— Target users, capability scope, explicit non-goals
- [Troubleshooting and data reference](./product/troubleshooting.en.md)（[中文](./product/troubleshooting.md)）— Common problems, what lives in `~/.zeta`, cleanup and reset

## protocols

- [Codex app-server protocol pinning](./protocols/codex_app_server_protocol.en.md)（[中文](./protocols/codex_app_server_protocol.md)）
- [Claude Code stream-json protocol baseline](./protocols/claude_code_stream_json_protocol.en.md)（[中文](./protocols/claude_code_stream_json_protocol.md)）
- [Grok ACP protocol baseline](./protocols/grok_acp_protocol.en.md)（[中文](./protocols/grok_acp_protocol.md)）

## release

- [Release guide](./release/release_guide.en.md)（[中文](./release/release_guide.md)）— Tag rules, quality gates, artifacts and platform notes

## history

Kept as historical evidence only. **Does not describe currently supported capabilities.**

## Related files at the repository root

- [README](../README.md)（[English](../README.en.md)）
- [Contributing guide](../CONTRIBUTING.md)（[English](../CONTRIBUTING.en.md)）
- [Changelog](../CHANGELOG.md)

---

> During the migration, documents listed here but not yet created are filled in by their corresponding migration step. See the mapping in [migration task list §0.6](./architecture/migration_tasks.en.md#06-documentation-convention).

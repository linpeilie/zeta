# Cursor ACP Historical Release Gate

Last updated: 2026-07-17

> Translated from [the Chinese original](../../zh/history/cursor_acp_release_validation.md), which is the source of truth if the two diverge.
>
> **Archive.** Cursor is retired; its runtime implementation and real-CLI smoke tooling have been deleted. This page preserves the conclusions of the release gate as it stood before removal, and does not describe current support.

## Conclusions before removal

- Unit tests covered CLI location, process arguments, the ACP provider, session replay, diagnostics, the minimal index, and the agent management repository.
- Synthetic fixtures can only freeze fake/test shapes. They cannot demonstrate real Cursor `messageId` / `eventId`, delta/snapshot behaviour, or replay semantics.
- Without cross-version, cross-platform evidence from the real protocol, Cursor could not be promoted to a stable provider, and no new stream identity rules could be written for it.

## The release gate after retirement

- Cursor appears in no catalog, setting, session creation flow or agent management entry point.
- App composition, bootstrap, deep links, workspace restore and the provider factory never create a Cursor runtime.
- Legacy configuration decodes leniently, displays as unavailable, and falls back safely without saving any configuration.
- A process spy proves Cursor is never launched; data-boundary regression tests prove protected directories, legacy indexes and old configuration are left unchanged.
- Cursor-specific runtime implementation and tests were deleted. The shared ACP decoder, mappers and JSON-RPC transport remain covered by the Grok and Codex regression suites.

Detailed execution records are in Phase 3 of `plan/agent_stream_identity_adaptation_plan.md`.

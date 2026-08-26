# Cursor Agent Retirement Notes

Last updated: 2026-07-17

> Translated from [the Chinese original](../../zh/history/cursor_agent_guide.md), which is the source of truth if the two diverge.
>
> **Archive.** This page records history only and does not describe currently supported behaviour.

Cursor has been retired from Zeta's provider catalog, settings, agent management, runtime composition, process startup, deep links, workspace restore and history loading paths. At the time the retirement completed, the active providers were Codex and Grok. That is a historical snapshot, not today's provider list.

## Final removal state

- The current provider enum, configuration codec, catalog, UI, factory, restore paths, tests and fixtures contain no Cursor.
- No legacy provider id, kind, decode/fallback path or "unavailable" presentation is kept for an unreleased schema.
- The current code does not read, migrate, rewrite or delete Cursor CLI private data.

## Historical evidence

- `plan/cursor_acp_integration_plan.md` (removed along with the `plan/` directory; it survives only in Git history) records the pre-removal implementation background.
- [Historical release gate](cursor_acp_release_validation.md) records the verification requirements and gaps at the time of retirement.
- The synthetic fixtures that existed before removal survive only in Git history. They do not represent the real protocol or current support.

## If Cursor is ever supported again

Any re-introduction must go through a fresh proposal: collect real, redacted live/replay protocol fixtures, and re-complete the catalog, configuration, restore, factory, process, data-boundary and cross-platform gates. Restoring the deleted implementation directly, or treating synthetic fixtures as a protocol contract, is not acceptable.

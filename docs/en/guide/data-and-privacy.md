# Data and Privacy

In one line: **Zeta does not upload your code, has no account system, and collects no telemetry.** This page fills in the details — what it writes to your machine, what it reads from elsewhere, and how to clear all of it.

## Your code stays local

Zeta is a local application with no server side. What it does is launch the AI command-line tools already installed on your machine, pass messages to them, and display the results.

- What Zeta hands the assistant is the **project directory path** and the **path of any file you selected** in the tree — not file contents.
- Whether to read a file, and how much of it, is the assistant's decision, made through a tool call you can see on the timeline.
- Your messages do of course go to the assistant, which sends them on to its model service. That link belongs to the assistant and is identical to using it from your terminal.
- Zeta itself sends no analytics, crash reports or usage data.

## What Zeta writes to your machine

Everything lives in a `.zeta` folder inside your system Documents directory:

| System | Path |
| --- | --- |
| macOS | `~/Documents/.zeta/` |
| Windows | `%USERPROFILE%\Documents\.zeta\` |
| Linux | `~/Documents/.zeta/` (or `$XDG_DOCUMENTS_DIR` if set) |

It's all plain JSON and plain text — open it or delete it whenever you like:

```
.zeta/
├── config/
│   ├── providers.json              per-assistant enabled state, executable path, selected model and permission mode
│   ├── appearance.json             theme, fonts, sizes
│   └── general.json                send shortcut, notification switches, interface language
├── state/
│   ├── ide_session.json            opened projects, current project, expanded tree nodes, selected file, conversation list cache
│   ├── usage_statistics_index.json aggregated usage index, rebuildable
│   └── session/<assistant>/        settings recorded when starting a turn (model, reasoning depth, timestamp)
├── logs/
│   └── zeta-YYYY-MM-DD.log         application log, one file per day
└── cache/
    └── agent_models_v1.json        model list cache, safe to delete
```

If this directory can't be created because of permissions, Zeta doesn't crash — it falls back to keeping state in memory only, so nothing from that run is persisted.

## What Zeta reads from elsewhere

To do its job, Zeta reads the assistants' own directories (`~/.codex`, `~/.grok`, `~/.claude`) for:

- **Connecting and resuming** — reading configuration and conversation history
- **Diagnostics** — reading the assistant's runtime logs for the log viewer
- **Usage statistics** — scanning history records to build the statistics page
- **Sign-in status** — determining whether you're authenticated

Writing is narrower: **Zeta writes to an assistant's configuration file only when you use the configuration editor and click save**, and it backs up the original first. It never migrates, rewrites or deletes an assistant's data otherwise.

## What's in the statistics index

`usage_statistics_index.json` holds a fixed list of fields, and nothing else:

| Stored | Not stored |
| --- | --- |
| Conversation ID, turn ID | Your prompts |
| Start time, duration | The assistant's replies |
| Project path, model name | Tool output |
| Status, token counts | Raw error text |
| Error category | The assistant's session file paths, environment variables, any credentials |

The file is rebuildable. Deleting it only makes the next visit to the statistics page slower — no real data is lost, because the real data lives in the assistants' own history files.

## What's in the logs

Logs are written one file per day and record application-level diagnostics: which operation failed, when a process exited.

Before anything is written, these are masked automatically:

- `Authorization` and `Proxy-Authorization` header values
- Tokens beginning with `Bearer`
- Keys beginning with `sk-`
- Values of keys named `api_key`, `token`, `secret`, `password`, `private_key`
- Your home directory path, replaced with `~`

**Logs can still contain project paths and file names.** Give them a read before pasting into a public issue.

Logs are not cleaned up automatically; delete old files yourself.

## Credentials

Zeta never saves login credentials in its own configuration, caches, or logs.

When using Claude Code, Zeta checks credentials before provider acquisition and new requests, refreshing within five minutes of expiry. It updates only the original Claude store: the macOS Keychain item, or the credentials file on Windows/Linux (also on macOS when that file was the original source). It does not migrate sources or create credential backups. Refresh or writeback failure blocks the operation; cancellation and approval responses remain available.

The quota detail switch controls usage queries separately. Turning it off does not disable credential checks or refresh. See [Connecting AI Assistants](agents.md#claude-codes-quota-detail-switch).

## What's in a notification

System notifications land in your operating system's notification centre, so they are kept deliberately sparse: the title is a category ("Task completed", "Permission required") and the body is the project directory name. No prompts, replies, commands or error details.

## Clearing and resetting

From narrowest to broadest:

| To do this | Delete |
| --- | --- |
| Clear the model list cache | `cache/` |
| Clear usage history | `state/usage_statistics_index.json` |
| Clear the turn settings Zeta recorded | `state/session/` |
| Forget opened projects and the conversation cache | `state/ide_session.json` |
| Reset appearance and general settings | `config/appearance.json`, `config/general.json` |
| Reset assistant configuration (enabled state, model choices) | `config/providers.json` |
| Clear logs | files under `logs/` |
| Full factory reset | the entire `.zeta/` directory |

Restart Zeta afterwards and the missing files are rebuilt with defaults.

**None of this touches your code, and none of it touches the assistants' own configuration or conversation history.** To clear those, go to their directories.

## Reporting security issues

Please don't open a public issue for a security vulnerability. Use GitHub's private reporting channel (repository page → Security → Report a vulnerability). See the [security policy](../../../SECURITY.md).

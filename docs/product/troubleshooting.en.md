# Troubleshooting and data reference

[中文](troubleshooting.md) ｜ English

Start here when something goes wrong. If you don't find an answer, [open an issue](https://github.com/linpeilie/zeta/issues/new/choose) — and skim [what's in the logs](#whats-in-the-logs) before pasting them.

## Contents

- [Install and first launch](#install-and-first-launch)
- [Agent won't connect](#agent-wont-connect)
- [Conversation and timeline](#conversation-and-timeline)
- [Projects and file tree](#projects-and-file-tree)
- [Session restore](#session-restore)
- [Desktop notifications](#desktop-notifications)
- [Usage statistics](#usage-statistics)
- [What Zeta stores on your machine](#what-zeta-stores-on-your-machine)
- [Cleanup and reset](#cleanup-and-reset)
- [Still stuck](#still-stuck)

---

## Install and first launch

### macOS says "cannot be opened because the developer cannot be verified"

Builds aren't code-signed or notarized, so this prompt is expected. Two ways through:

- **Right-click** the app in Finder → **Open** → confirm **Open** in the dialog; or
- Go to **System Settings → Privacy & Security**, find the blocked-app notice, and click **Open Anyway**.

You only need to do this once.

### Windows shows a blue SmartScreen prompt

Same cause — unsigned build. Click **More info** → **Run anyway**.

### Installed the .deb on Linux but can't find the app

Make sure your desktop environment refreshed its application menu, or just run `zeta` from a terminal. If you took the portable tar.gz, extract it and run the `zeta` executable inside.

### Blank window or immediate exit on launch

Check today's file in `~/.zeta/logs/`. Zeta is designed so that startup failures don't crash the app — if it does crash, that's a defect. Please open an issue with the log attached.

---

## Agent won't connect

The most common category by far. **Zeta ships no model of its own** — it drives the agent CLI already installed on your machine, so step one is always confirming the CLI works standalone.

### The agent panel says no CLI detected

Verify in a terminal first:

```sh
codex app-server     # Codex
grok --version       # Grok
```

- **Command not found**: the CLI isn't installed, or isn't on `PATH`. Note that Zeta is a GUI app and may see a different `PATH` than your terminal — CLIs installed under `~/.local/bin` or through version managers like nvm/asdf are often invisible to GUI apps.
- **Command works but Zeta still can't see it**: open **Settings → Agent management**, which shows the detected executable path, version, and sign-in state, and tells you exactly which step is failing.

### The connection test in Agent management fails

The test does three things only: check the version, check the account, perform a protocol handshake. **It never sends a real model request, so it costs nothing.** Match the failure to the cause:

| Symptom | Usual cause |
| --- | --- |
| Executable not found | `PATH` problem — see above |
| Version detection failed | CLI too old, or its output format changed |
| Not signed in | Complete the CLI's own login flow in a terminal first |
| Handshake failed | CLI version incompatible with the protocol Zeta targets |

### Grok sessions get tangled when several are open

Upgrade Grok CLI to **0.2.119 or newer**. That's Zeta's multi-session compatibility baseline; earlier versions don't support multiple sessions, and session state, streaming notifications, and turn terminal states may not be isolated correctly when several Grok sessions run at once.

### The composer is gone — I can read but not send

That thread is read-only. This usually happens after disabling Codex in settings: existing threads remain readable, but no new writable session can be created. Re-enable it to restore the composer.

### An old Cursor config shows as unavailable

Expected. Cursor is retired. Zeta falls back in memory to any enabled, non-retired provider
(Codex, Grok, or Claude Code). It does **not** overwrite your old config and does not read or
modify any Cursor session data.

---

## Conversation and timeline

### An approval or question card vanished before I could answer

Approval cards are pinned above the composer and can't be pushed away by new messages. A card disappearing usually means:

- you already decided;
- the request timed out;
- you answered the same request elsewhere (e.g. in the CLI itself);
- the provider process exited.

Resolved requests deliberately don't reappear in the timeline.

### The agent said it would run a command, then nothing happened

Check whether it's waiting on your approval. Zeta's default policy is conservative and **never auto-authorizes commands, file writes, or network access**. If the window is in the background, check your system notifications.

### I clicked "Run plan" and it didn't behave as expected

Running a plan **always starts a new Default turn** rather than continuing the current one. That's deliberate: plan approval and actual execution are separate acts, and execution pre-authorizes nothing the plan mentioned. To keep iterating on the plan instead, use **Keep planning / send revisions**.

### Scrolling gets choppy on very long timelines

The timeline is virtualized and shouldn't stutter. If it does, please open an issue with a rough turn count and message volume.

---

## Projects and file tree

### Some directories are missing from the file tree

These are ignored on purpose so that opening a large repo doesn't hang:

```
.dart_tool   .git   .idea   .vscode   build   node_modules
```

The list is currently fixed and not configurable.

### Opening a big repo is slow

The tree is **lazy-loaded** — a directory is read only when you expand it, never recursively scanned up front. If even the top level is slow, the repo root itself probably has a huge number of entries, or it lives on a network/sync drive.

### I selected a file but the agent doesn't seem to see its contents

That's the current design boundary: Zeta passes the **project path and the selected file path** as context and **never reads file contents automatically**. Whether and how much to read is the agent's call, made through tool calls — which means you can see exactly what it read in the timeline.

---

## Session restore

### A project disappeared from the list after restart

Restore filters out directories that no longer exist. Check that:

- the project path still exists (not moved or deleted);
- the app can read it (external drives, network volumes, or protected folders on macOS may need extra permission).

### Are my old conversations still there after restart?

Yes. Per-project thread history stays available and resumable. If a thread opens empty, the provider-side session may no longer be recoverable.

---

## Desktop notifications

### The turn finished but I got no notification

Notifications fire **only when you aren't already looking at that thread**. When all three of these hold, Zeta assumes you're watching and stays quiet:

1. the Zeta window has focus;
2. the current page is the Agent home (not Settings or Usage statistics);
3. the open thread is the one that produced the event.

Any one of them failing produces a notification. Also check **Settings → General**: the master **System notifications** switch, plus the **Turn finished** and **Action required** category switches.

### The OS never shows notifications at all

Confirm Zeta has permission at the system level:

- **macOS**: System Settings → Notifications → Zeta
- **Windows**: Settings → System → Notifications
- **Linux**: depends on your desktop environment's notification daemon

### Why are notifications so terse?

By design. The title carries only a category ("Task completed", "Permission needed"), and the body is just `<project folder> · Agent thread`. Your prompts, responses, commands, full paths, question text, and error details **never** appear — system notifications land in the OS notification center, which is not the place for any of that.

---

## Usage statistics

### The numbers don't match what my CLI reports

The accounting rules are explicit and may differ from your assumptions:

- one turn counts as one call;
- `completed` counts as success; `failed` and `interrupted` count as failures;
- **running and unknown states are excluded from the success-rate denominator**;
- root threads from the CLI, VS Code, `codex exec`, and Zeta are all counted, **including archived threads but excluding sub-agents** (to avoid double counting).

### Time-to-first-token shows very few samples

Only samples where Codex explicitly returned `time_to_first_token_ms` are used; missing ones are not approximated. The page states the valid sample count.

### Plan quota information looks incomplete

Only fields the provider actually returned are shown: plan type, percentage windows, reset time, and optional balance. Zeta does **not** infer absolute token allowances or expiry dates the provider didn't supply.

---

## What Zeta stores on your machine

Everything lives under `~/.zeta/` (`%USERPROFILE%\.zeta\` on Windows) as plain JSON you can inspect or delete at any time.

```
~/.zeta/
├── config/
│   ├── providers.json                 Agent provider configuration
│   ├── appearance.json                Theme and font settings
│   └── general.json                   Send shortcut, notification switches
├── state/
│   ├── ide_session.json               Open projects, selected file, expansion, thread cache
│   ├── usage_statistics_index.json    Derived usage index
│   ├── migration_marker.json          One-time migration marker
│   └── cursor_sessions.json           Retired leftover; never read or written at runtime
├── logs/
│   └── zeta-YYYY-MM-DD.log            Daily-rotated application log
└── cache/
    └── agent_models_v1.json           Model catalog cache, safe to delete
```

**Zeta reads private data owned by active agent CLIs when a feature requires it.** The corresponding Provider data adapter may read configuration, session history, logs, and account metadata for connection setup, history recovery, diagnostics, and usage statistics. Raw bodies, credentials, and private paths are not copied into Zeta's derived indexes. Read access does not imply automatic migration, rewriting, or deletion; configuration is written only when you explicitly use the configuration editor. Cursor is retired, so its session data remains outside runtime reads and writes.

### What's in the usage index

`usage_statistics_index.json` stores only normalized allow-listed fields: thread ID, turn ID, timestamp, project, model, status, latency, token counts, error category.

It does **not** store prompts, response bodies, tool output, raw error text, session file paths, environment variables, credentials, or provider raw payloads. The file is rebuildable — deleting it only loses historical stats.

### What's in the logs

Logs rotate daily and record application-level diagnostics. Redaction runs before writing: authorization headers, `Bearer` tokens, `sk-` prefixed keys, and `api_key` / `token` / `secret` / `password` style values are masked, and your home directory path is replaced with `~`.

That said, **logs can still contain project paths and filenames**, so give them a look before pasting into an issue.

Logs are **not** pruned automatically — delete old files yourself.

---

## Cleanup and reset

From narrowest to broadest:

| Goal | Delete |
| --- | --- |
| Clear the model catalog cache | `~/.zeta/cache/` |
| Clear historical statistics | `~/.zeta/state/usage_statistics_index.json` |
| Forget opened projects and thread cache | `~/.zeta/state/ide_session.json` |
| Reset appearance and general settings | `~/.zeta/config/appearance.json`, `general.json` |
| Clear logs | files under `~/.zeta/logs/` |
| **Full factory reset** | the entire `~/.zeta/` directory |

Restart Zeta afterwards and missing files are recreated with defaults. **None of this touches your code, or your agent CLI's own configuration and session history.**

---

## Still stuck

When opening an issue, please include:

- OS and version
- Zeta version (About page or installer filename)
- Agent CLI and version (`codex --version` / `grok --version`)
- Steps to reproduce
- Relevant logs, redacted

Don't open public issues for security vulnerabilities — use GitHub's private reporting instead (Security → Report a vulnerability).

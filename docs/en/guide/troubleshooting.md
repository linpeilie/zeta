# Troubleshooting

Find your symptom below. If it isn't here, [open an issue](https://github.com/linpeilie/zeta/issues/new/choose) — and before attaching logs, read [what's in the logs](data-and-privacy.md#whats-in-the-logs).

- [Installation and first launch](#installation-and-first-launch)
- [Assistant won't connect](#assistant-wont-connect)
- [Conversations and the timeline](#conversations-and-the-timeline)
- [Projects and the file tree](#projects-and-the-file-tree)
- [Session restore](#session-restore)
- [Desktop notifications](#desktop-notifications)
- [Usage statistics](#usage-statistics)
- [Still stuck](#still-stuck)

## Installation and first launch

### macOS says the developer cannot be verified

The packages aren't code-signed, so this is expected. Two ways in:

- **Right-click** Zeta in Finder, choose Open, and confirm in the dialog; or
- Go to System Settings → Privacy & Security, find the blocked-app notice, and click "Open Anyway".

You only have to do this once.

### Windows shows a blue SmartScreen dialog

Same cause. Click "More info", then "Run anyway".

### Installed the .deb on Linux but can't find the app

Refresh your desktop environment's application menu, or just run `zeta` from a terminal. With the tar.gz build, extract it and run the `zeta` binary inside.

### Blank window on launch, or it exits immediately

Check today's file in the log directory (path in [Data and Privacy](data-and-privacy.md#what-zeta-writes-to-your-machine)). Zeta is designed not to crash when startup fails, so if it really did crash, that's a defect — please open an issue with the log.

### Settings don't stick after restarting

If Zeta can't create its data directory — insufficient permissions, a full disk, a Documents folder redirected somewhere unwritable — it falls back to keeping state in memory, which looks exactly like settings resetting on every launch. Check that your Documents directory is writable.

## Assistant won't connect

This is the most common category of problem. Zeta ships no model; it drives the AI command-line tool on your machine. **So the first step is always to confirm that tool works on its own.**

### Zeta says it isn't detected

Verify in a terminal first:

```sh
codex --version     # Codex
grok --version      # Grok
claude --version    # Claude Code
```

- **Command not found** — it isn't installed, or it isn't on your system `PATH`.
- **The command works but Zeta still can't find it** — this is the classic case. Zeta is a graphical application, and the `PATH` it sees is often not the one in your terminal. If the tool lives in `~/.local/bin`, or was installed via nvm, asdf or volta, graphical apps usually can't see it.

  The reliable fix is to add the tool's directory to your system-level `PATH` (not just your shell startup script), then quit Zeta completely and reopen it.

Open **Settings → Agents**; the Diagnostics section of the detail page shows exactly which step failed, which beats guessing.

### The connection test fails

The connection test does three things: read the version, check sign-in status, and open one connection. **It sends no prompt, calls no model, and costs nothing.**

Match the message to the cause:

| Symptom | Usual cause |
| --- | --- |
| Executable not found | A `PATH` problem — see above |
| Version detection failed | Too old, or its output format changed |
| Not signed in | Complete the login in your terminal first |
| Handshake failed (the two can't agree on how to talk) | Version outside the range Zeta supports — see [version requirements](agents.md#version-requirements) |

### I can chat in the terminal but Zeta says I'm not signed in

"The CLI works" and "the account is signed in" are not always the same thing. An API key, a third-party endpoint, or a different configuration directory can each cause a mismatch.

For Claude Code, run `claude auth status --json` in an environment as close to Zeta's as you can and see what it reports. If it says logged out but you can clearly use it, click **Test connection** in Zeta — if that passes, the path Zeta is using works.

On macOS, a graphical app's environment variables and keychain access context differ from a terminal's; on Windows, installation method can cause similar differences. Start by checking that the executable path shown on the Agents page is the one you expect.

### The model list is empty

The model list comes from what the assistant reports. An empty list usually means you aren't signed in, or the connection didn't establish. Run a connection test on the detail page first.

When a refresh fails, Zeta keeps the previously cached list (up to 7 days) and labels it as cached.

### Grok gets confused with several conversations open

Upgrade Grok to **0.2.119 or newer**. Earlier versions don't support multiple concurrent conversations, so state isn't kept apart when you open or run several at once.

### The composer is gone and I can only read

That conversation is read-only because the assistant it belongs to has been disabled in settings. Re-enable it under **Settings → Agents** — the history was never going anywhere.

## Conversations and the timeline

### A permission card vanished before I answered

Approval cards sit in a fixed area above the composer and are never pushed out by new messages. A card disappearing usually means:

- You already answered it
- The request timed out
- You answered the same request elsewhere (in the assistant's own CLI, for instance)
- The assistant's process exited

Requests you've responded to don't reappear — that's deliberate.

### The assistant says it will run a command, then nothing happens

Check whether it's waiting on your approval. Zeta doesn't auto-authorise commands, file writes or network access. If the window is in the background, check your system notifications.

### I accepted the plan but it didn't start working

That's expected. After accepting a plan there's an execution confirmation step asking which permissions to run with. Once you confirm, Zeta starts a **new turn** to execute — so permissions are still requested one at a time as it goes. See [Approvals, Questions and Plans](approvals.md#execution-confirmation).

### After branching, my files aren't back to how they were

Branching only affects the conversation record; it doesn't touch your files. Anything the assistant already wrote to disk is still there. Use your own version control to undo file changes.

### Scrolling is choppy in a long conversation

Scrolling shouldn't stutter however long the conversation is. If it does, please open an issue with a rough turn count.

## Projects and the file tree

### Some directories are missing from the tree

These are skipped deliberately, to keep large repositories usable. The list is currently fixed and not configurable:

```
.dart_tool   .git   .idea   .vscode   build   node_modules
```

### Opening a large repository is slow

The tree loads on demand — a directory level is only read when you expand it, never recursively up front. If even the top level is slow, the repository root probably has an enormous number of entries, or it's on a network or sync drive.

### I selected a file but the assistant doesn't seem to see it

That's the design boundary. Zeta passes the **project path and the selected file path**, and does not read file contents. Whether to read the file, and how much, is up to the assistant — which is why you can see it happen on the timeline.

## Session restore

### A project disappeared from the list after restarting

Restore filters out directories that no longer exist. Check that:

- The project path is still there and hasn't been moved or deleted
- The app has permission to read it (on macOS, external drives, network volumes and protected folders may need extra authorisation)

### I'm back on the welcome page — are my conversations gone?

No. Expand the project and its history is there; click one to continue. If a conversation opens empty, the assistant's own record of it may no longer be resumable.

## Desktop notifications

### The task finished but I got no notification

Notifications only fire when you **aren't already looking at that conversation**. Zeta stays quiet when all three of these hold:

1. The Zeta window has focus
2. The conversation view is showing (not Settings or Usage statistics)
3. The conversation currently open is the one the event came from

If any one fails, you get a notification. Also check the three switches under **Settings → General → Notifications**.

### The operating system isn't showing them at all

Confirm Zeta has permission:

- **macOS** — System Settings → Notifications → Zeta
- **Windows** — Settings → System → Notifications
- **Linux** — depends on your desktop's notification service

### Clicking a notification doesn't open the conversation

If that conversation has been deleted, or isn't in your current project list, Zeta says so explicitly. Reopening the relevant project usually brings it back.

### Why are notifications so sparse?

By design. System notifications land in your operating system's notification centre, and Zeta doesn't put your prompts, replies, commands or error details there. See [Data and Privacy](data-and-privacy.md#whats-in-a-notification).

## Usage statistics

### The numbers don't match what I see elsewhere

The accounting is explicit and may differ from your expectation:

- One **turn** counts as one call
- The success-rate denominator only includes finished calls (completed / failed / cancelled); **running and unknown are excluded**
- Only "completed" counts as success
- Statistics read the assistants' own local history, so they **include calls you made in the terminal**, not just from Zeta

### The response-time sample count is tiny

Only calls where the assistant explicitly reported a time to first token are counted; missing samples are not approximated. The page shows the valid sample count.

### Plan quota is incomplete

Zeta shows only what the assistant actually reports and doesn't extrapolate the rest. When something can't be read, it keeps what it could get (the plan name, say) and marks the rest as temporarily unavailable instead of showing zero.

Claude Code's five-hour window, weekly windows and extra quota require the quota detail switch to be on. Leaving it off doesn't affect the plan name.

### It says "some data unavailable"

Statistics rely on scanning local history files, and occasionally a file won't read or a line is corrupt. Zeta skips those, shows the rest, and states what's missing. Other numbers remain correct.

### It says "no usage records"

If you know you've used it, check two things: whether the time range is narrower than you thought, and whether the Agent filter is set to an assistant you haven't used.

## Still stuck

When opening an issue, please include:

- Operating system and version
- Zeta version (it's in the package file name)
- Which assistant and which version
- Steps to reproduce
- Relevant logs — give them a read first for paths you'd rather not publish

Please don't open a public issue for a security vulnerability. Use GitHub's private reporting instead (repository page → Security → Report a vulnerability).

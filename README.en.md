<div align="center">

<img src="assets/branding/zeta_logo.svg" alt="Zeta" width="96" />

# Zeta

**A desktop workbench for command-line AI coding assistants — one where you can see what they're doing and stay in control.**

macOS · Windows · Linux ｜ Runs locally ｜ Open source

[![CI](https://github.com/linpeilie/zeta/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/linpeilie/zeta/actions/workflows/ci.yml)
[![Release](https://github.com/linpeilie/zeta/actions/workflows/release.yml/badge.svg)](https://github.com/linpeilie/zeta/actions/workflows/release.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[中文](README.md) ｜ English

<!-- Screenshots pending; see docs/images/README.md for the capture spec
<img src="docs/images/hero.png" alt="Zeta workbench" width="900" />
-->

</div>

---

## What Zeta is

Codex, Claude Code and Grok are capable assistants, but they all live inside a terminal window:

- Which files did it actually change? Scroll back through hundreds of lines to find out.
- It wants to run a command, and you get one "y / n" before it's gone.
- Where did yesterday's conversation get to? Closing the terminal ended it.
- A task ran for five minutes, you switched away, and it turns out it has been waiting on you for the last ten.

Zeta moves all of that into a desktop application. Projects and past conversations on the left, a complete working timeline in the middle, the file tree on the right. Every step the assistant takes — what it said, how it reasoned, which tools it called, which lines it changed — is laid out in order and stays there for you to scroll back through.

It doesn't replace your code editor, and it doesn't upload your code. It does one thing: **make it clear what the assistant is doing on your machine, and let you stop it at any point.**

## What it does

**A complete working timeline**
Replies, reasoning, tool calls, and the turn's code diff, all on one continuous timeline with syntax highlighting. Consecutive commands and file edits are grouped automatically so the view stays readable.

**It asks when it should ask**
Running a command, writing a file, reaching the network — all require your approval by default. Approval cards sit in a fixed area above the composer and are never pushed out by new messages. Zeta never approves anything for you.

**Review the plan, then act**
Have the assistant propose an approach first and confirm it before anything runs. Accepting a plan **does not** authorise the commands in it — those are still requested one at a time. You can iterate on the plan before committing to it.

**It tells you when it's done**
Task finished, approval needed, question waiting — if you aren't watching that conversation, you get a system notification plus a taskbar or Dock hint. Clicking through takes you straight to the conversation. Notifications carry only a category like "Task completed", never your code or prompts.

**Close it and pick up where you left off**
Project list, current project, expanded tree nodes, selected file, panel widths and conversation history are all restored on the next launch.

**See what you're spending**
Built-in usage statistics: filter by time, project and model to see call counts, success rate, token spend and response times, along with your plan's usage windows and reset times. Every number comes from what the assistant actually reported — nothing is estimated.

**A composer that gets out of the way**
Paste a screenshot straight in, `@` to reference project files, `$` to insert a skill, `/` for the command menu. Arrow keys to choose, Enter to confirm.

**Two themes, desktop density**
A light and a dark theme, draggable panel widths, collapsible columns that become overlays on narrow windows, and separately configurable interface and code fonts.

## Supported assistants

| Assistant | Vendor | Notes |
| --- | --- | --- |
| **Codex** | OpenAI | The most complete support: resume, archive, branch, plan mode, skills, image input, model and reasoning depth, usage statistics |
| **Grok** | xAI | Plan mode and plan approval, conversation modes, skills, file references; archive and branch not yet supported |
| **Claude Code** | Anthropic | Plan mode and plan approval, four permission modes, context compaction, subscription quota detail; file references and skills not yet supported |

Zeta only shows what your assistant can actually do: anything it can't, simply doesn't appear, rather than failing when clicked. Full table in [Connecting AI Assistants](docs/en/guide/agents.md#what-each-assistant-supports).

> Cursor was supported previously and has been retired. Zeta does not launch Cursor and does not read or write anything under `~/.cursor`.

## Where your data lives

- **Your code stays local.** Zeta passes the project path and any file path you selected to the local AI command-line tool. It uploads nothing itself, and has no account system and no telemetry.
- **Assistant configuration stays put.** Unless you explicitly save from Zeta's configuration editor, Zeta doesn't touch anything under `~/.codex`, `~/.grok` or `~/.claude`.
- **Zeta's own data** lives in a `.zeta` folder inside your system Documents directory (settings, session state, logs, cache) — all plain JSON you can read or delete at any time.
- **The statistics index stores only what it needs**: conversation ID, time, project, model, status, duration, token counts. Never prompts, replies, tool output, or raw error text.

File-by-file details and how to clear them: [Data and Privacy](docs/en/guide/data-and-privacy.md).

## Quick start

**1. Install an AI assistant first**

Zeta ships no model. Install and sign in to [Codex CLI](https://github.com/openai/codex), Claude Code or Grok CLI, and confirm it works in your terminal.

**2. Install Zeta**

Download the package for your platform from the [Releases page](https://github.com/linpeilie/zeta/releases). The packages aren't code-signed yet, so you'll need to allow the first launch (right-click → Open on macOS; "Run anyway" past SmartScreen on Windows).

**3. Open a project and start talking**

Launch Zeta → "Open project folder" → pick a local repository → describe what you want in the composer and press Enter. To have it plan first, type `/` and pick `Plan`.

Assistant not detected? Open **Settings → Agents** — it shows exactly which step failed. The connection test only performs a handshake; it calls no model and costs nothing.

Full walkthrough: [Installation and First Run](docs/en/guide/getting-started.md).

## Documentation

**User documentation** ([English](docs/en/README.md) ｜ [中文](docs/zh/README.md))

- [Installation and First Run](docs/en/guide/getting-started.md) · [Interface Tour](docs/en/guide/workbench.md) · [Conversations and the Timeline](docs/en/guide/conversations.md)
- [Approvals, Questions and Plans](docs/en/guide/approvals.md) · [Connecting AI Assistants](docs/en/guide/agents.md) · [Notifications](docs/en/guide/notifications.md)
- [Usage Statistics](docs/en/guide/usage-statistics.md) · [Settings](docs/en/guide/settings.md) · [Data and Privacy](docs/en/guide/data-and-privacy.md)
- [Troubleshooting](docs/en/guide/troubleshooting.md)

**Project documentation**

- [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.en.md) · [Security policy](SECURITY.md) · [Code of conduct](CODE_OF_CONDUCT.md)
- [Architecture overview](docs/en/architecture/overview.md) · [Glossary](docs/en/development/glossary.md) · [Developer guide](docs/zh/development/developer_guide.md)

## Contributing

Contributions are welcome. Read the **[contributing guide](CONTRIBUTING.en.md)** before you start — this project has a set of architectural constraints that are enforced in review, and a PR that violates them won't be merged even if the feature works.

Zeta is a Flutter Desktop application. Dart SDK `^3.12.2`; CI runs Flutter stable 3.44.4.

```sh
flutter pub get
flutter run -d macos    # or -d windows / -d linux
```

Before committing, run in order:

```sh
dart format .
flutter analyze
bash tool/test_affected.sh   # only the tests affected by your change
```

Don't run the full suite in your development loop — CI is where the full suite is enforced. The full matrix is in [`AGENTS.md`](AGENTS.md).

## Not included

Zeta is an agent collaboration panel, not a full IDE. These are out of scope for now:

A built-in code editor · in-editor diffs and file editing · remote repositories and cloud sync · user accounts · a full plugin system · mobile

## Licence

[GPL-3.0](LICENSE). You are free to use, modify and distribute this project, but modified versions must also be released under GPL-3.0.

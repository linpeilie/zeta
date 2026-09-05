# Installation and First Run

This page walks you through your first session: install an AI assistant, install Zeta, open a project, send your first message.

## Before you start: install an AI assistant

Zeta ships no model and has no account system. It is a shell that drives the command-line AI coding assistants already installed on your machine. So the first step isn't downloading Zeta — it's getting at least one of these working:

| Assistant | Vendor | Install | Sign in |
| --- | --- | --- | --- |
| Codex | OpenAI | See [Codex CLI](https://github.com/openai/codex) | Run `codex login` |
| Claude Code | Anthropic | `npm install -g @anthropic-ai/claude-code` | Run `claude auth login` |
| Grok | xAI | See xAI's documentation | Run `grok login` |

Once installed, talk to it in your terminal first and confirm it answers. Zeta only puts a graphical interface in front of it — anything that doesn't work on the command line won't work in Zeta either.

Version requirements:

- **Codex** 0.142.5 or newer. Below that, Zeta marks it as unsupported and stops sending messages.
- **Grok** 0.2.119 or newer. Earlier versions can't keep concurrent sessions apart, so state gets crossed when you open several at once.
- **Claude Code** 2.1.22x or newer is the range currently verified.

## System requirements

- macOS 10.15 or later, on Intel and Apple silicon
- Windows 10 or 11, 64-bit
- Linux 64-bit, with the GTK 3, fontconfig, util-linux and xz runtime libraries (the `.deb` and `.rpm` packages declare these automatically)

## Download and install

Grab the package for your platform from the [Releases page](https://github.com/linpeilie/zeta/releases). Every package ships with a matching `.sha256` file you can use to verify the download.

| Platform | Installer | Portable |
| --- | --- | --- |
| macOS (universal — Intel and Apple silicon) | `zeta-<version>-macos-universal.dmg` | `zeta-<version>-macos-universal.zip` |
| macOS (Apple silicon only / Intel only) | `...-macos-arm64.dmg` / `...-macos-x86_64.dmg` | matching `.zip` |
| Windows 64-bit | `zeta-<version>-windows-x86_64-setup.exe` | `zeta-<version>-windows-x86_64.zip` |
| Linux 64-bit | `.deb` / `.rpm` / `.AppImage` | `zeta-<version>-linux-x86_64.tar.gz` |

If you're unsure which macOS package to take, take the universal one.

### Your OS will block the first launch

The packages are not code-signed yet, so your operating system will warn you the first time. This is expected, and you only have to deal with it once:

- **macOS**: when you see "cannot be opened because the developer cannot be verified", right-click Zeta in Finder, choose Open, then confirm. You can also go to System Settings → Privacy & Security and click "Open Anyway".
- **Windows**: when SmartScreen shows its blue dialog, click "More info", then "Run anyway".
- **Linux**: if Zeta doesn't appear in your application menu after installing the `.deb` or `.rpm`, refresh the menu or just run `zeta` from a terminal. With the tar.gz, extract it and run the `zeta` binary inside.

## First launch

You land on the welcome page. In the background, Zeta scans your machine for installed assistants and lists what it finds, each with a status:

- **Available** — installed, signed in, ready to use.
- **Sign-in required** — the program is there, but you haven't logged in. Run the login command in your terminal.
- **Not detected** — Zeta couldn't find the program. Usually it isn't on your system `PATH`.
- **Error** — found, but it won't start, or its version is out of range.

If nothing is detected, don't reinstall yet. Open **Settings → Agents**: it shows exactly which step failed — finding the executable, reading the version, checking sign-in status, or opening a connection. See [Connecting AI Assistants](agents.md).

## Open a project

Click "Open project folder" on the welcome page and pick a local code directory. The title bar menu (**File → Open project**) does the same thing.

The window then splits into three columns: projects and conversations on the left, the conversation in the middle, the project's file tree on the right.

The file tree loads on demand — Zeta only reads a directory level when you expand it, so opening a large repository doesn't hang. These directories are skipped to keep the tree readable: `.dart_tool`, `.git`, `.idea`, `.vscode`, `build`, `node_modules`.

## Send your first message

Type what you want in the composer — something like "explain how this project is organized" — and press Enter.

Here's what happens next:

1. Zeta starts the assistant you picked and tells it which directory you're working in.
2. The assistant goes to work. What it says, what it reasons through, and every tool it calls appear in order on the timeline in the middle column.
3. If it wants to run a command, change a file, or reach the network, an approval card appears above the composer and waits for you. **Zeta never approves anything on your behalf.**
4. When the turn ends, if files changed, a summary appears on the timeline. Expand it to see exactly which lines changed.

To make it plan before it acts, type `/` in the composer and pick `Plan`. It will produce a plan for you to review before anything runs. See [Approvals, Questions and Plans](approvals.md).

## Where to go next

- [Interface Tour](workbench.md) — what each column does, how to collapse them, how to switch projects and conversations
- [Conversations and the Timeline](conversations.md) — reading the timeline, editing past messages, branching
- [Approvals, Questions and Plans](approvals.md) — permission cards, questions, plan mode
- [Connecting AI Assistants](agents.md) — what each assistant supports, and what to do when detection fails
- [Data and Privacy](data-and-privacy.md) — what Zeta writes to your machine

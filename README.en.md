<div align="center">

<img src="assets/branding/zeta_logo.svg" alt="Zeta" width="96" />

# Zeta

**A desktop workbench for command-line AI coding agents — so you can actually see what they're doing.**

macOS · Windows · Linux ｜ Runs locally ｜ Open source

[中文](README.md) ｜ English

</div>

---

## What is Zeta

Today's AI coding agents (Codex CLI, Grok, and friends) are powerful — and they all live inside a dark terminal window:

- Which files did it actually change? Scroll back through hundreds of log lines to find out.
- It wants to run a command, and you get one shot at "y / n" before it scrolls past.
- Where did yesterday's conversation leave off? Closing the terminal closed the door.
- It ran for five minutes, you switched tasks, and it turns out it's been waiting on your approval for ten.

**Zeta moves all of that into a real desktop app.** Projects and past conversations on the left, the agent's full working timeline in the middle, your project file tree on the right. Every step the agent takes — what it said, what it reasoned about, which tools it called, which lines it changed — is laid out in order and stays scrollable.

It isn't trying to be your code editor, and it doesn't upload your code anywhere. It does one thing: **let you see exactly what an AI is doing on your machine, and stop it whenever you want.**

## Why it's worth a try

**The work is visible**
Replies, reasoning, tool calls, and the per-turn code diff all live in one continuous, syntax-highlighted timeline. No more archaeology in scrollback.

**It asks before it acts**
Running commands, writing files, and network access all require your approval by default. Approval cards are pinned above the composer so new messages can't push them out of view. Zeta never pre-authorizes anything on your behalf.

**Plan first, then execute**
Ask the agent to draft a plan, read it, and only then let it run. You can send revisions mid-way. Planning and execution are two clearly separate actions — running a plan always starts a fresh turn.

**It taps you on the shoulder**
Turn finished, approval needed, agent has a question — if you aren't looking at that conversation, you get a system notification, plus taskbar flashing on Windows and a Dock badge on macOS. Click it and you land back in the right thread. Notifications only carry a category like "Task completed" — never your code, prompts, or file paths.

**Close it and pick up where you left off**
Project list, current project, expanded folders, selected file, recent threads — all restored on restart. Every project keeps its conversation history, ready to resume.

**Know what you're spending**
A built-in usage page: filter by time, project, agent, and model to see call counts, success rate, token usage, and latency, plus your plan's current usage window and reset time. Everything shown comes from what the provider actually returned — nothing is estimated.

**A composer that gets out of the way**
Paste or attach screenshots straight in, type `$` for Skills, `/` for the command menu, `@` to reference project files. Arrow keys to pick, Enter to confirm.

**Two themes, desktop density**
Dark "Graphite Night" and light "Graphite Day", draggable panel widths, and side panels that collapse into overlays when the window gets narrow.

## Supported agents

| Agent | Status | Notes |
| --- | --- | --- |
| **Codex CLI** | ✅ Default | Full support: session resume, plan mode, Skills, model switching, usage stats |
| **Grok** | ✅ Supported | Connected over ACP; capabilities degrade automatically based on handshake |

Zeta negotiates capabilities: anything an agent doesn't support simply isn't rendered, rather than failing silently when clicked. Adding a new agent requires no UI changes.

> Cursor was supported once and has been retired. Zeta never launches Cursor and never reads or modifies anything under `~/.cursor`.

## Where your data lives

- **Your code stays local.** Zeta passes only the project path and your selected file path to the local AI CLI. It uploads nothing and has no accounts.
- **Your CLI config stays put.** Zeta does not touch `~/.codex` or `~/.grok`.
- **Zeta's own data lives in `~/.zeta/`** (settings, session state, logs, cache) as plain versioned JSON you can inspect or delete at any time.
- **The usage index stores only the essentials**: thread ID, timestamp, project, model, status, latency, token counts. No prompts, no response bodies, no tool output, no raw error text.

## Download and install

Grab a build for your platform from the [Releases page](https://github.com/linpeilie/zeta/releases):

| Platform | Installer | Portable |
| --- | --- | --- |
| macOS (Intel / Apple Silicon universal) | `zeta-<version>-macos-universal.dmg` | `...-macos-universal.zip` |
| Windows x64 | `zeta-<version>-windows-x64-setup.exe` | `...-windows-x64.zip` |
| Linux x64 | `zeta_<version>_amd64.deb` | `zeta-<version>-linux-x64.tar.gz` |

Every package ships with a `.sha256` checksum file.

Builds are **not code-signed**, so the first launch triggers an OS warning:

- **macOS**: if you see "cannot be opened because the developer cannot be verified", right-click the app in Finder → **Open** → confirm; or go to **System Settings → Privacy & Security** and click **Open Anyway**.
- **Windows**: on the SmartScreen prompt, click **More info** → **Run anyway**.

## Get started in three steps

**1. Install an agent CLI first**

Zeta is a shell — it ships no model of its own. Install and sign in to [Codex CLI](https://github.com/openai/codex) (recommended) or Grok CLI, and confirm it works in your terminal.

**2. Open your project**

Launch Zeta → click **Open directory** in the Projects panel → pick a local repo. The file tree loads on the right, skipping `.git`, `node_modules`, `build`, and similar folders.

**3. Start talking**

Describe what you want in the composer and hit Enter. Want a plan first? Type `/` and pick **Plan**.

> CLI not detected? Open **Settings → Agent management** for identity, version, sign-in state, and a connection test that tells you exactly where things break. The test performs a handshake only — it never triggers a billable model call.

## Contributing

Zeta is a Flutter Desktop app on Dart SDK `^3.12.2`; CI builds with Flutter stable 3.44.4.

```sh
flutter pub get
flutter run -d macos    # or -d windows / -d linux
```

Before submitting, run in order:

```sh
dart format .
flutter analyze
flutter test
```

Architecture rules, provider onboarding, event-pipeline invariants, and review gates live in [`docs/`](docs/README.md) (Chinese):

- [Product requirements](docs/product_requirements.md) — target users, scope, user flows
- [Design document](docs/design_document.md) — layering, UI skeleton, provider abstraction
- [Developer guide](docs/developer_guide.md) — commands, event pipeline, UI details
- [Engineering standards](docs/engineering_standards.md) — architecture review rules
- [Release guide](docs/release_guide.md) — tag rules and release workflow
- [AGENTS.md](AGENTS.md) — AI collaboration rules and commit format

Adding a provider should touch only its own data files, the neutral domain contracts, the factory wiring, and contract tests. Shared layers (decoder, event pipeline, timeline store) must contain no provider-specific branching.

## Not included

Zeta is an agent collaboration panel, not a full IDE. The following are **not** available and aren't planned near-term:

Built-in code editor · file content reading and in-editor diff · remote repos and cloud sync · accounts · a full plugin system · mobile

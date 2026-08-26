# Connecting AI Assistants

"Agent" in Zeta means a command-line AI coding assistant installed on your machine. Zeta ships no model of its own. What it does is put these assistants behind a graphical interface and make their behaviour visible.

## Three are supported today

| Assistant | Vendor | Command | Configuration file |
| --- | --- | --- | --- |
| Codex | OpenAI | `codex` | `~/.codex/config.toml` |
| Grok | xAI | `grok` | `~/.grok/config.toml` |
| Claude Code | Anthropic | `claude` | `~/.claude/settings.json` |

Zeta never modifies these files unless you edit and save them yourself in Zeta's configuration editor.

> Cursor was supported previously and has been retired. Zeta does not launch Cursor and does not read or write anything under `~/.cursor`.

## What each assistant supports

Assistants differ in what they can do. Zeta's approach is that **features an assistant can't provide simply don't appear in the interface**, rather than giving you a button that errors when clicked. So a missing button is usually not a bug.

| What you can do | Codex | Grok | Claude Code |
| --- | :---: | :---: | :---: |
| Start a conversation | ✓ | ✓ | ✓ |
| Resume a past conversation | ✓ | ✓ | ✓ |
| Browse conversation history | ✓ | ✓ | ✓ |
| Cancel a running turn | ✓ | ✓ | ✓ |
| Add to a turn while it runs | ✓ | — | — |
| Rename a conversation | ✓ | ✓ | — |
| Archive / unarchive | ✓ | — | — |
| Branch a conversation | ✓ | — | — |
| Delete a conversation | ✓ | ✓ | — |
| Remove from Zeta's list only | — | — | ✓ |
| Compact context (`/compact`) | ✓ | — | ✓ |
| Reference files with `@` | ✓ | ✓ | — |
| Insert skills with `$` | ✓ | ✓ | — |
| Attach images | ✓ | — | — |
| Permission approval | ✓ | ✓ | ✓ |
| Questions from the assistant | ✓ | ✓ | ✓ |
| Plan mode (read-only planning, no file changes) | ✓ | ✓ | ✓ |
| Enter plan mode from the `/` menu | ✓ | ✓ | —&nbsp;¹ |
| An explicit "Accept plan" card | —&nbsp;² | ✓ | ✓ |
| Model selection | ✓ | ✓ | ✓ |
| Adjustable reasoning depth | ✓ | ✓ | ✓ |
| Fast tier | ✓ | — | — |
| Usage and quota statistics | ✓ | ✓ | ✓ |

¹ With Claude Code you select Plan in the permission mode control instead; the effect is the same.
² With Codex, the planning turn goes straight to execution confirmation — there's no separate accept step.

The table is a conservative floor. Once connected, Zeta adjusts based on the version and capabilities the assistant actually reports — branching at a specific past turn, for instance, needs Codex 0.144.5 or newer, and the option doesn't appear below that. The list of conversation modes is likewise reported by the assistant after connecting.

## The Agents page

**Settings → Agents** is where you go for anything assistant-related.

The list on the left switches between **Installed** and **All supported**, and you can search by name or vendor. **Auto-detect** rescans your machine.

Each row shows that assistant's sign-in status, version, and runtime state, with an enable toggle on the right. Disabling an assistant stops its running tasks and makes existing conversations read-only — Zeta warns you before doing it.

Opening an assistant gives you three tabs.

### Basics

- **Attributes** — name, vendor, how Zeta communicates with it.
- **Version** — the version you have installed, and the latest version Zeta could look up.
- **Paths and commands** — the executable path Zeta actually uses and the full launch command. You can copy the command or open the containing folder.
- **Diagnostics** — the result of the last detection run, item by item: whether the executable exists, sign-in evidence, whether the connection works, handshake results, negotiated capabilities, version compatibility. When something is wrong, this says which step failed and suggests what to do.

Three buttons sit at the top of the page: **Test connection**, **View runtime logs**, and **Disable agent**.

### Models

Lists the models currently available from this assistant, with the data source and when it was last updated. If loading fails, the reason is shown — most often it's that you aren't signed in.

### Configuration

Edit the assistant's configuration file inside Zeta.

- It opens read-only, with sensitive values (keys, tokens) masked. Click **Show sensitive values** to edit the full content.
- The format is validated before saving; invalid content is never written out.
- The original file is backed up before saving.
- If the file changed on disk while you were editing, Zeta stops and asks whether to overwrite instead of silently clobbering it.
- As a safety measure, Zeta refuses to write through a symbolic link.

Codex needs to be restarted for a saved configuration to take effect, and Zeta says so after saving.

## How detection works

Auto-detection runs these steps in order and tells you exactly where it stopped:

1. **File detection** — find the executable on your system `PATH`
2. **Process startup** — try to launch it
3. **Version detection** — read its version number
4. **Sign-in check** — determine authentication status
5. **Handshake** — open a connection and confirm both sides understand each other
6. **Configuration read** — check the configuration file

Step 1 is the usual failure. Zeta is a graphical application, and the `PATH` it sees is often not the one in your terminal — if your assistant lives in `~/.local/bin`, or was installed via nvm, asdf or a similar version manager, graphical apps typically can't see it.

## Testing the connection

**Test connection** does a full round trip: start the process, complete a handshake, read back identity and capabilities, then disconnect.

**It sends no prompt, calls no model, and costs nothing.** When it finishes you get the elapsed time and what was negotiated.

For Claude Code, the test sends a promptless initialisation request. Worth knowing: the Claude command-line tool may use that opportunity to reach the network or refresh its own cache and authentication state. That part is outside Zeta's control.

## Runtime logs

**View runtime logs** opens the assistant's own log output, filterable by level and searchable by keyword. **Copy logs** copies a **redacted** version — authorisation headers, tokens and keys are masked.

Even so, logs can still contain project paths and file names. Give them a look before pasting into a public issue.

## Claude Code's quota detail switch

The Claude Code page has a **Quota detail** switch, off by default.

Turning it on lets Zeta read Claude Code's stored credentials momentarily and make one usage query, so it can show the five-hour window, weekly windows and extra quota.

Leaving it off doesn't affect normal use: the model list and plan name always come from the Claude command-line tool itself, independently of this switch.

Either way, Zeta **never refreshes, writes back, or stores** those credentials — they stay in memory only for the duration of that single read-only request.

## Version requirements

| Assistant | Requirement | Notes |
| --- | --- | --- |
| Codex | 0.142.5 or newer | Below this, Zeta marks it unsupported and stops sending messages |
| Grok | 0.2.119 or newer | Earlier versions can't isolate concurrent conversations |
| Claude Code | 2.1.22x or newer recommended | The range currently verified |

If your version is newer than what Zeta has verified, the interface labels it "newer, not fully verified". Things generally work; they just haven't been checked end to end.

## Common questions

**It works in my terminal but Zeta says it isn't installed.** See the `PATH` note under "How detection works", and [Troubleshooting](troubleshooting.md#assistant-wont-connect).

**I can chat in the terminal but Zeta says I'm not signed in.** For some assistants, "the CLI works" and "the account is signed in" are not the same thing — API keys, third-party endpoints, or a different configuration directory can all cause a mismatch. Click **Test connection**; if it passes, the path Zeta is using works.

**A button I expected isn't there.** Check the support table above. It usually means the assistant doesn't support it.

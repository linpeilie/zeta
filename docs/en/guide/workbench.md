# Interface Tour

Zeta has one window and one layout that never changes: a title bar and three columns. This page covers what each area does.

## Title bar

Zeta draws its own title bar. From left to right:

- **Menu** — **File → Open project** adds a local directory; **File → Quit** closes the app.
- **Left column toggle** — collapse or expand the projects column.
- **Back to workbench** — return to the conversation view from Settings or Usage statistics.
- **Usage statistics** — open the statistics page: call counts, token spend, plan quota.
- **Settings** — open the settings page.
- **Right column toggle** — collapse or expand the files column. This button only works in the conversation view; it's greyed out on the Settings and Usage pages.
- **Window buttons** — minimise, maximise / restore, close.

Whether each column is shown, how wide it is, and what's expanded inside it are all remembered and restored on the next launch.

## Welcome page

With no project open, the middle column shows the welcome page:

- **Open project folder** — pick a local code directory.
- **Recent conversations** — your latest conversations across all projects. Click one to jump straight back in.
- **Installed providers** — the AI assistants Zeta found on your machine, each with a status (available / sign-in required / not detected / error / detecting). Detection runs in the background, so you'll see "detecting" briefly on first launch.

## Left column: projects and conversations

The left column is a single card with three parts.

### Project list

Each row is a local directory you've opened, sorted by most recently used. Click one to switch to it.

Each row has a "New conversation" button. The menu next to it offers:

- Refresh the conversation list
- Reveal the directory in your system file manager (Finder on macOS, File Explorer on Windows)
- Remove the project from the list — this never deletes anything on disk

Projects with a running task are marked as such.

### Conversation list

Expand a project to see its conversation history. Click one to continue it; the history reloads.

Which actions are available depends on the assistant you're using — see [what each assistant supports](agents.md#what-each-assistant-supports):

- **Rename** — change the conversation title.
- **Archive / unarchive** — tuck away conversations you're done with.
- **Branch** — copy this conversation into a new one, leaving the original intact.
- **Remove from Zeta's list** — drop Zeta's record only; the assistant's own history files stay untouched.
- **Delete** — permanent, cannot be undone.

### Usage summary

At the bottom of the card is a small read-only usage panel, collapsed by default. It shows your current assistant's plan, the tightest remaining quota window, and today's token spend. Expand it for more detail, or open the full [Usage Statistics](usage-statistics.md) page.

## Middle column: the conversation

This is the main work area: the timeline on top, the composer below.

The timeline holds everything that happened in this conversation, in order — what you said, what the assistant replied, how it reasoned, every tool it called, and every file it changed. See [Conversations and the Timeline](conversations.md).

The toolbar above the timeline has:

- The **project name** and **conversation title** (click the title to rename)
- **Context** — opens a side panel with the conversation's details: name, ID, message count, which assistant, context window limit, token usage (input / output / cached), created and last-active times. The panel also has a **Raw messages** view showing the unprocessed exchange, which you can select and copy.
- **More** — rename, branch, archive, and other conversation actions.

Approval cards appear in a fixed area just above the composer. They stay put; new messages never push them out of view.

## Right column: files

The right column is the current project's file tree.

It loads on demand: Zeta only reads a directory level when you expand it, so even very large repositories open quickly. These directories are skipped, and the list is currently fixed:

```
.dart_tool   .git   .idea   .vscode   build   node_modules
```

Clicking a file selects it, and the selected path is passed to the assistant as context. **Zeta does not read the file contents and send them** — whether to read the file, and how much of it, is the assistant's decision, and you'll see it happen on the timeline.

Which directories are expanded and which file is selected are restored on the next launch.

## Narrow windows

When the window gets narrow, the side columns switch from fixed panes to overlays: they slide over the conversation when opened and close when you click elsewhere. The conversation area stays fully usable.

## Theme and type size

Zeta has a light and a dark theme, either following your system or set explicitly. Interface and code fonts are configured separately, each with its own typeface and size. See [Settings](settings.md).

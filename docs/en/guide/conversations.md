# Conversations and the Timeline

The timeline is the heart of Zeta. Every step the assistant takes on your machine is laid out in order, and you can scroll back through all of it. This page covers what's on the timeline and what you can do with it.

## How a conversation is structured

A **conversation** is one continuous exchange with an assistant; you can pick it up days later. It belongs to a project and to a specific assistant — a conversation started with Codex stays a Codex conversation.

Conversations are made of **turns**. You send a message, the assistant does its work and answers: that's one turn. A turn ends in one of four states:

| State | Meaning |
| --- | --- |
| Streaming | The assistant is working |
| Completed | Finished normally |
| Failed | Something went wrong; the timeline explains what, with a suggested next step |
| Interrupted | You cancelled it, or the assistant's process exited |

Turns are separated on the timeline by generous whitespace and a hairline rule, so boundaries are easy to spot.

## What appears on the timeline

**Your messages** — shown as sent, including files you referenced and skills you inserted.

**The assistant's replies** — rendered as Markdown, with syntax-highlighted code blocks.

**Reasoning** — the assistant's thinking before it answers, collapsed by default. Not every assistant provides this.

**Tool calls** — every time the assistant reads a file, edits one, runs a command, searches, or fetches a page, it appears as its own entry, labelled with the kind of action (read / edit / delete / move / search / execute / fetch) and its state (pending / in progress / completed / failed / cancelled). Expand one to see exactly which file, which command, and what came back.

Consecutive similar operations are grouped: several commands in a row become one **command group**, several file edits become one **file edit group**. This keeps the timeline readable.

**Turn changes** — when a turn ends having touched files, a summary appears showing how many files changed and whether each was created, modified, deleted or moved. Expand it to review the actual changes:

- Unified diff — the familiar view, with added and removed lines colour-coded
- Replaced snippet — before and after, side by side
- Written content — the full contents of a newly created file

Large blocks scroll independently and support keyboard paging.

**Everything else** — questions from the assistant, permission requests, plan approvals, context compaction, sub-task activity, model reroutes, retry waits. All of it appears as its own timeline entry. Nothing is hidden.

## Reading long conversations

As a conversation grows:

- A **conversation map** on the side lists every turn with its number and state. Click one to jump to it.
- Scrolling back doesn't yank you to the bottom when new content arrives. A "new content" indicator appears instead; click it to return to the latest.
- Scrolling stays smooth however long the conversation gets — hundreds of turns included.

## The composer

Typing a trigger character opens a picker. Use the arrow keys to choose and Enter to confirm:

| Type | What it does |
| --- | --- |
| `@` | Reference a file from the project. Type to filter; the selection is inserted as a clickable chip. |
| `$` | Insert a skill — a reusable instruction package the assistant provides. |
| `/` | Open the command menu: `Plan` (enter plan mode) and `Compact` (compress this conversation's context), followed by the available skills. |

You can also paste a screenshot straight into the composer, or use "Attach image" to pick a local file.

Each of these depends on what your assistant supports. Options it doesn't support simply don't appear — you never get a button that does nothing when clicked.

The send shortcut defaults to Enter. You can change it to Cmd + Enter or Ctrl + Enter in settings, in which case Enter inserts a newline.

## Choosing a model and reasoning depth

There's a model picker near the composer. Pick a model; if it supports adjustable reasoning depth, those options appear below it. Some models also offer a **Fast** tier for quicker responses, which is incompatible with certain reasoning depths — when they conflict, Zeta asks you to choose rather than silently changing your setting.

Model and reasoning changes **take effect from the next turn** and never interrupt a turn in flight. The interface says so explicitly.

If the model you picked becomes unavailable, Zeta switches to one that works and tells you which.

## Stopping mid-turn

While the assistant is working, the send button becomes **Cancel turn**. Click it and it stops.

Changes already made are not rolled back. Files that were written stay written — Zeta does not undo work on your disk.

## Rewriting history: editing and branching

To rephrase and try again, hover one of your earlier messages and click **Edit message**. When you send the edit, Zeta does **not** overwrite the original conversation. It creates a **new branch** starting from just before that message, and the original stays intact.

Likewise, if a turn failed, **Branch and retry** starts over from that point.

One thing to be clear about: **branching only affects the conversation record, not your files.** Anything the assistant already wrote to disk is still there. To undo file changes, use your own version control.

## Compacting context

An assistant can only hold so much of a conversation in mind at once (its context window). Long conversations fill it up. Type `/` and pick `Compact` to have the assistant compress the conversation's context and free up room. When it happens, a "context compacted" entry appears on the timeline so you know.

Some assistants compact on their own when the window gets tight. That also leaves a mark on the timeline.

## Read-only conversations

If a conversation says it's read-only and the composer is gone, the assistant it belongs to has been disabled in settings. The history is still fully browsable; you just can't send anything. Re-enable it under **Settings → Agents**.

## Looking at the raw exchange

The **Context** panel above the timeline has a **Raw messages** view showing the unprocessed exchange between Zeta and the assistant. You can select text directly, or use **Copy original** to copy a whole entry. This is the place to look when you're debugging something, or want to confirm the rendered view isn't leaving anything out.

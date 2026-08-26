# Approvals, Questions and Plans

Zeta's default position is simple: **it never agrees to anything for you.** If the assistant wants to run a command, write a file, or reach the network, it asks first. This page covers how it asks, what your options are, and how plan mode works.

There are four situations that need your input, and Zeta keeps them strictly separate:

1. **Permission approval** — the assistant wants to do something with side effects
2. **Questions** — the assistant needs information from you to continue
3. **Plan approval** — the assistant proposes an approach and asks whether you accept it
4. **Execution confirmation** — the plan is accepted; which permissions should it run with?

In all four cases, the card appears in a fixed area above the composer. New messages never push it out of view.

## Permission approval

### What's on the card

A permission card tells you three things: **what kind of operation** it is (run a command / apply file changes / grant permissions / confirm), **exactly what it wants to do** (which command, which file, what change), and **which assistant** is asking.

### Your options

| Option | Effect |
| --- | --- |
| Allow | Permits this one occurrence. |
| Deny | Refuses. The assistant is told, and usually adapts or asks you something. |
| Allow for this session | Stops asking about operations of this kind for the rest of the conversation. Expires with the session. |
| Always allow | Remembers the decision for future operations of this kind. |

Some requests also offer **Override guard**, for operations the assistant's own safety policy blocked. This appears only when the assistant explicitly offers it.

### The card disappeared before I answered

Requests you've responded to don't reappear — that's deliberate. If a card vanished without you touching it, it's usually one of:

- The request timed out
- You answered the same request somewhere else (in the assistant's own CLI, for instance)
- The assistant's process exited

### Permission modes

Beyond approving one request at a time, you can set the overall stance for a conversation with the **permission mode** control next to the composer. Each assistant offers its own set:

- **Codex** — Read only / Workspace write / Full access. Custom permission profiles defined in your Codex configuration also show up here.
- **Claude Code** — Ask (prompt on every high-risk tool) / Accept edits (auto-allow editing tools, still ask for the rest) / Plan (read-only, produces a plan) / Bypass permissions (skips permission checks — high risk).
- **Grok** — Ask / Auto / Always approve.

When a mode change takes effect depends on the assistant: some apply it on the next turn, some on your next send, some only in a new conversation. The interface tells you which. You can't switch modes mid-turn; Zeta asks you to wait for the turn to finish.

Choosing a permissive mode means you have deliberately given up per-request confirmation. Zeta will honour that, but it won't make that choice for you.

## Questions from the assistant

Sometimes the assistant needs input before it can continue — picking between approaches, for instance. That shows up as a question card, kept separate from permission approvals.

A request can contain several questions. The card shows which one you're on, and you can move back and forth. For each question:

- Options may be single-choice or multiple-choice (the card says which)
- You can pick "Other" and write your own answer
- You can skip a question
- When you're done, **Submit answers** sends them all back at once

If a request arrives with no answerable questions in it, Zeta says so rather than leaving you staring at an empty card.

## Plan mode

To make the assistant think before it acts, use plan mode.

### Entering plan mode

Type `/` in the composer and pick `Plan`. A "Plan" badge appears on the composer, marking the next turn as read-only planning — **the assistant cannot change files in this mode.**

You can also select Plan directly in the permission mode control (Claude Code supports this).

### Reading the plan

The plan appears in a dedicated panel, listing the steps with their state (pending / in progress / completed). During execution the panel updates in place, and you can collapse it.

### Three ways out

Once you've read the plan:

- **Accept plan** — you approve the approach. Note that accepting a plan **only confirms the approach**. It does not authorise the commands and file operations it describes; those are still requested one at a time. (Codex skips this step: the planning turn goes straight to the execution confirmation below.)
- **Revise** — add to or change the requirements in the composer and let the assistant rework the plan. You can iterate.
- **Abandon** — drop it and go back to a normal conversation.

### Execution confirmation

After you accept a plan, there's one more step: Zeta asks **which permissions to execute with.**

This separation is deliberate. Approving a plan and running it are two different things, and accepting a plan pre-authorises nothing. The confirmation card shows:

- How many steps the plan has
- Which permission mode this run will use. It defaults to whatever was in effect before you entered plan mode; if that's no longer valid, it falls back to the assistant's conservative default and the card labels it as such.
- An option to pick a different mode **for this run only**, marked as such and not saved for later

Once you confirm, Zeta starts a **new ordinary turn** to execute the plan rather than continuing the planning turn. So permissions are still requested as execution proceeds.

If no permission option is currently available, Zeta requires you to choose one before executing rather than quietly picking a default.

## One rule that never bends

Whatever you do, there is one thing Zeta never does: **authorise an operation you haven't explicitly agreed to.** Plan approval doesn't pre-authorise execution, execution confirmation doesn't pre-authorise individual commands, and permissive modes are ones you chose yourself, with the interface stating what they mean.

## Related

- [Conversations and the Timeline](conversations.md) — everything that happens after an approval lands on the timeline
- [Notifications](notifications.md) — pending approvals notify you when you're not watching that conversation
- [Connecting AI Assistants](agents.md) — which assistant supports which kinds of approval

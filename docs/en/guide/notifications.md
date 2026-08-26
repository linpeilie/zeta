# Notifications

While the assistant works, you're usually doing something else. When a task finishes, or it's stuck waiting for you, Zeta uses a system notification to get your attention.

## When you get notified

Zeta only notifies you when **you aren't already looking at that conversation.** Three conditions have to hold simultaneously for it to stay quiet:

1. The Zeta window has focus
2. The conversation view is showing (not Settings, not Usage statistics)
3. The conversation currently open is the one the event came from

All three, and Zeta assumes you're watching and doesn't interrupt. If any one of them fails, you get a notification.

## What it notifies you about

Two categories, each with its own switch in settings.

**Task finished**

- Task completed
- Task failed
- Task interrupted

**Needs your confirmation**

- Permission required
- Question waiting for an answer
- Plan waiting for approval
- Plan ready to execute

## What a notification looks like

The title is just the category — "Task completed", "Permission required". The body is the project directory name and "Agent session".

Notifications **never** contain your prompt, the assistant's reply, command text, full paths, question wording, or error details. That's deliberate: system notifications land in your operating system's notification centre, which is not the place for any of that. To see what actually happened, click through to the conversation.

Clicking a notification brings Zeta to the front and opens the matching conversation. If that conversation has been deleted or isn't in your current project list, Zeta tells you it can't open it rather than failing silently.

## Taskbar and Dock

There are quieter signals too:

- **Windows** — the taskbar icon flashes and shows an unread count
- **macOS** — a badge on the Dock icon
- **Linux** — depends on your desktop environment, usually a window urgency hint

These clear on their own once you return to the conversation.

## Where the switches are

**Settings → General → Notifications** has three:

| Switch | What it does |
| --- | --- |
| System notifications | The master switch. With this off, the other two do nothing. |
| Task finished | Notify when a task completes, fails or is interrupted. |
| Needs confirmation | Notify when a permission, question, plan approval or execution confirmation is waiting. |

## Not getting notifications

First check that your operating system grants Zeta permission:

- **macOS** — System Settings → Notifications → Zeta
- **Windows** — Settings → System → Notifications
- **Linux** — depends on whether your desktop's notification service is running

Then check you aren't being filtered out by the "you're already watching" rule above. More cases in [Troubleshooting](troubleshooting.md#desktop-notifications).

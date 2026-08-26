# Settings

The gear icon in the title bar opens settings. Navigation is on the left, content on the right.

There are three sections: General, Appearance, and Agents. Agents has [its own page](agents.md#the-agents-page).

## General

### Message sending

**Send shortcut** — which key sends a message from the composer:

| Option | Sends | New line |
| --- | --- | --- |
| Enter (default) | Enter | Shift + Enter |
| Cmd + Enter (macOS) | Cmd + Enter | Enter |
| Ctrl + Enter (Windows / Linux) | Ctrl + Enter | Enter |

If you write multi-line prompts often, the second option is easier to live with.

### Notifications

Three switches controlling when Zeta interrupts you with a system notification:

| Switch | Default | What it does |
| --- | --- | --- |
| System notifications | On | Master switch. With this off, the other two do nothing. |
| Task finished | On | Notify when a task completes, fails or is interrupted. |
| Needs confirmation | On | Notify when a permission, question, plan approval or execution confirmation is waiting. |

Notifications only fire when you aren't already looking at that conversation — see [Notifications](notifications.md) for the exact rule.

### Interface language

Switch between English and Simplified Chinese. **The change requires restarting the app**, and the interface says so.

On first launch, Zeta follows your system language.

## Appearance

### Theme

| Option | What it does |
| --- | --- |
| Follow system | Uses your system's current light or dark preference and tracks changes. |
| Light | Light background, low-contrast borders, azure accent. |
| Dark | Dark background, high-contrast panels, bright accent. |

### Fonts

Interface and code fonts are configured separately, each with its own typeface and size.

**Interface font** is used for ordinary interface text and Markdown prose. It defaults to the bundled Geist. You can also pick your system default, or choose from the fonts installed on your machine — the list is searchable.

**Code font** is used for code blocks, commands, diffs and tool output. It defaults to the bundled JetBrainsMono.

**Sizes** are adjusted independently:

| Item | Range |
| --- | --- |
| Interface size | 10–20 px |
| Code size | 10–24 px |

Use the minus and plus buttons on either side. Changes apply immediately.

If a font you selected is later uninstalled from your system, Zeta says it couldn't load it and falls back to the default rather than rendering nothing.

## Where settings are stored

Everything is written as plain JSON under `config/` in Zeta's data directory:

- `appearance.json` — theme, fonts, sizes
- `general.json` — send shortcut, notification switches, interface language
- `providers.json` — each assistant's enabled state, executable path, selected model and permission mode

Delete any of them and they're rebuilt with defaults on the next launch. For exact paths, see [Data and Privacy](data-and-privacy.md).

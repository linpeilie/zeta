# Installation and First Run

Set up an AI assistant before installing Zeta.

## Prepare an assistant

Zeta supports Codex, Grok and Claude Code. Follow your chosen assistant's official instructions to install it and sign in, then check that it works independently. Zeta does not provide a model account or pay model fees.

If these tools are new to you, complete the assistant's own introduction first. See [Connecting AI Assistants](agents.md#versions) for compatibility information.

## Install Zeta

Download a package for your system from [Releases](https://github.com/linpeilie/zeta/releases). Use the system requirements and files listed for that release.

| Computer | Package |
| --- | --- |
| Mac | A `.dmg`; choose one containing `universal` if unsure which chip you have |
| 64-bit Windows | The installer ending in `setup.exe`; after setup, open Zeta from the Start menu |
| 64-bit Linux | A `.deb`, `.rpm` or `.AppImage` suitable for your system |

Portable archives are also available: extract one and run Zeta. The `.sha256` files let you check that a download is intact.

Current packages do not have a developer signature, so your system may show a warning on first launch. Confirm that the file came from this project's release page before allowing it to open. A damaged-file message or an antivirus alert is a different issue; see [Troubleshooting](troubleshooting.md#installation-and-startup).

## Open a project

1. Start Zeta.
2. Choose “Open project folder”, or use “File → Open project”.
3. Select the local folder you want the assistant to work with.

The left side lists projects and conversations. The middle holds the conversation, and the right side lists files. Selecting a file gives the assistant a reference to it; ask in your message if you want it to read the contents.

## Send your first message

Try a request you can check easily, such as “Explain the main folders in this project”. Enter sends the message by default; Shift + Enter adds a new line.

Replies and operation records appear as the assistant works. Permission requests and questions appear above the input box. Read them before responding. Whether each operation needs confirmation depends on your permission settings.

You can cancel a task, but files already changed will not be restored.

## No assistant found

Open “Settings → Agents” and run automatic detection. Select the assistant to inspect the result, follow any installation, sign-in or version advice, then test the connection. See [Connecting AI Assistants](agents.md).

Continue with the [Interface Tour](workbench.md), [Conversations](conversations.md) and [Approvals and Plans](approvals.md). Read [Data and Privacy](data-and-privacy.md) before working with private projects.

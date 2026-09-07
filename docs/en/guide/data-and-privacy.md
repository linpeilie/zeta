# Data and Privacy

Zeta runs locally, with no cloud conversation service or telemetry of its own. **Your messages and code are not necessarily confined to your computer: the connected assistant may send them to a model service.**

## What goes to the assistant

When you send a message, the assistant receives your message, attached images, file references and the locations of the current project and selected file. It can read files within your chosen permissions and use their contents to answer.

Network use, transmitted content and server retention depend on the assistant, account and settings. Check these before working with private or work material.

## What Zeta saves

Zeta saves settings, project lists, usage summaries, logs and model lists in a `.zeta` folder inside the system Documents directory. Common locations are below. Redirecting or syncing Documents changes the actual location too.

| System | Common location |
| --- | --- |
| macOS | `~/Documents/.zeta/` |
| Windows | `%USERPROFILE%\Documents\.zeta\` |
| Linux | `.zeta` inside your Documents directory |

These files are not separately encrypted. Someone with access may see project paths, conversation names, model choices and usage.

Zeta's statistics and logs do not store message bodies, assistant replies, tool output or sign-in credentials. The assistant may still save complete conversations in its own history.

## Assistant data and sign-in

Zeta reads the connected assistant's configuration, account status, history and logs to connect, resume conversations, diagnose problems and show usage.

These actions can change the assistant's own data:

- Saving on the Configuration page updates its configuration and backs up the previous file.
- Supported rename, archive and delete actions change the assistant's saved conversations.
- With Claude Code, Zeta may update existing sign-in information to keep it signed in. A failed update may require signing in again.

“Remove from Zeta list” hides a listing without deleting the assistant's history. Claude Code's quota-details switch controls extra usage queries only; switching it off does not stop checks needed to maintain sign-in.

## Logs and notifications

Logs record operating status and problems. Common passwords and keys are masked, but check private paths, filenames and account information before sharing. Old logs currently require manual cleanup.

System notifications contain an event category and a short project name, without messages, commands or error bodies. A project name itself may be private; turn off [system notifications](notifications.md) if you do not want it in the notification center.

## Clear or reset data

**Quit Zeta first and back up files you intend to remove.** All paths below are relative to the `.zeta` folder above.

| Data | Location | Effect |
| --- | --- | --- |
| Cached model list | `cache/` | Read again when needed |
| Cached usage summary | `state/usage_statistics_index.json` | Rebuilt from assistant history that still exists |
| Zeta's per-conversation settings | `state/session/` | Extra model and other details absent from assistant history may be lost |
| Opened projects and layout | `state/ide_session.json` | Reopen projects and adjust layout |
| Appearance, language and shortcuts | `config/appearance.json`, `config/general.json` | Return to defaults |
| Enabled assistants and preferences | `config/providers.json` | Choose assistants and preferences again |
| Claude list hiding and conversation decisions | `state/claude_code/` | Hidden entries may reappear; remembered decisions are cleared |
| Application logs | `logs/` | Corresponding diagnostic records are lost |
| All Zeta settings and records | The entire `.zeta` folder | Resets all of the above |

These actions do not delete project files or the assistant's own configuration and complete history. Rebuilding a cache cannot restore assistant history that has already been deleted.

Report security issues as described in the [Security Policy](../../../SECURITY.md), without posting private information publicly.
